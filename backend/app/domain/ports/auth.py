from datetime import datetime
from typing import Protocol
from uuid import UUID

from app.domain.models import Actor, LoginResearcher


class AuthenticationRepository(Protocol):
    async def find_for_login(self, email: str) -> LoginResearcher | None: ...

    async def create_refresh_token(
        self, *, researcher_id: UUID, token_hash: str, family_id: UUID, expires_at: datetime
    ) -> None: ...

    async def rotate_refresh_token(
        self, *, current_token_hash: str, next_token_hash: str, next_expires_at: datetime
    ) -> Actor: ...

    async def revoke_refresh_token_family(self, *, token_hash: str, reason: str) -> None: ...


class PasswordVerifier(Protocol):
    def verify(self, password: str, password_hash: str) -> bool: ...


class RefreshTokenService(Protocol):
    def generate(self) -> str: ...

    def digest(self, token: str) -> str: ...


class AccessTokenIssuer(Protocol):
    expires_in_seconds: int

    def issue(self, actor: Actor) -> str: ...
