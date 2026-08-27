from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from uuid import uuid4

from app.domain.errors import InvalidCredentials, InvalidRefreshToken
from app.domain.models import Actor, AuthenticationResult
from app.domain.ports.auth import (
    AccessTokenIssuer,
    AuthenticationRepository,
    PasswordVerifier,
    RefreshTokenService,
)


@dataclass(slots=True)
class Login:
    repository: AuthenticationRepository
    passwords: PasswordVerifier
    access_tokens: AccessTokenIssuer
    refresh_tokens: RefreshTokenService
    refresh_token_days: int

    async def execute(self, *, email: str, password: str) -> AuthenticationResult:
        researcher = await self.repository.find_for_login(email.strip().casefold())
        if researcher is None or not researcher.is_active:
            raise InvalidCredentials
        if not self.passwords.verify(password, researcher.password_hash):
            raise InvalidCredentials
        return await _issue_session(
            repository=self.repository,
            access_tokens=self.access_tokens,
            refresh_tokens=self.refresh_tokens,
            refresh_token_days=self.refresh_token_days,
            actor=researcher.actor,
            family_id=uuid4(),
        )


@dataclass(slots=True)
class RefreshSession:
    repository: AuthenticationRepository
    access_tokens: AccessTokenIssuer
    refresh_tokens: RefreshTokenService
    refresh_token_days: int

    async def execute(self, *, refresh_token: str | None) -> AuthenticationResult:
        if not refresh_token:
            raise InvalidRefreshToken
        next_refresh_token = self.refresh_tokens.generate()
        actor = await self.repository.rotate_refresh_token(
            current_token_hash=self.refresh_tokens.digest(refresh_token),
            next_token_hash=self.refresh_tokens.digest(next_refresh_token),
            next_expires_at=_refresh_expiry(self.refresh_token_days),
        )
        return AuthenticationResult(
            actor=actor,
            access_token=self.access_tokens.issue(actor),
            refresh_token=next_refresh_token,
            expires_in=self.access_tokens.expires_in_seconds,
        )


@dataclass(slots=True)
class Logout:
    repository: AuthenticationRepository
    refresh_tokens: RefreshTokenService

    async def execute(self, *, refresh_token: str | None) -> None:
        if refresh_token:
            await self.repository.revoke_refresh_token_family(
                token_hash=self.refresh_tokens.digest(refresh_token), reason="logout"
            )


def _refresh_expiry(refresh_token_days: int) -> datetime:
    return datetime.now(UTC) + timedelta(days=refresh_token_days)


async def _issue_session(
    *,
    repository: AuthenticationRepository,
    access_tokens: AccessTokenIssuer,
    refresh_tokens: RefreshTokenService,
    refresh_token_days: int,
    actor: Actor,
    family_id,
) -> AuthenticationResult:
    refresh_token = refresh_tokens.generate()
    await repository.create_refresh_token(
        researcher_id=actor.researcher_id,
        token_hash=refresh_tokens.digest(refresh_token),
        family_id=family_id,
        expires_at=_refresh_expiry(refresh_token_days),
    )
    return AuthenticationResult(
        actor=actor,
        access_token=access_tokens.issue(actor),
        refresh_token=refresh_token,
        expires_in=access_tokens.expires_in_seconds,
    )
