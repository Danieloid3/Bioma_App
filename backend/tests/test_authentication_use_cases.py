from datetime import UTC, datetime
from uuid import UUID

import pytest

from app.application.use_cases.authentication import Login, Logout, RefreshSession
from app.domain.errors import InvalidCredentials, InvalidRefreshToken
from app.domain.models import Actor, LoginResearcher


class FakeAuthenticationRepository:
    def __init__(self, researcher: LoginResearcher | None) -> None:
        self.researcher = researcher
        self.created: dict[str, object] | None = None
        self.revoked: dict[str, str] | None = None

    async def find_for_login(self, email: str) -> LoginResearcher | None:
        return self.researcher if self.researcher and self.researcher.email == email else None

    async def create_refresh_token(self, **kwargs) -> None:
        self.created = kwargs

    async def rotate_refresh_token(self, **kwargs) -> Actor:
        if kwargs["current_token_hash"] == "digest:invalid":
            raise InvalidRefreshToken
        return self.researcher.actor  # type: ignore[union-attr]

    async def revoke_refresh_token_family(self, **kwargs) -> None:
        self.revoked = kwargs


class FakePasswords:
    def verify(self, password: str, password_hash: str) -> bool:
        return password == "correct" and password_hash == "stored-hash"


class FakeRefreshTokens:
    def __init__(self) -> None:
        self.counter = 0

    def generate(self) -> str:
        self.counter += 1
        return f"refresh-{self.counter}"

    def digest(self, token: str) -> str:
        return f"digest:{token}"


class FakeAccessTokens:
    expires_in_seconds = 900

    def issue(self, actor: Actor) -> str:
        return f"access:{actor.researcher_id}"


@pytest.fixture
def researcher() -> LoginResearcher:
    return LoginResearcher(
        researcher_id=UUID("80000000-0000-0000-0000-000000000001"),
        full_name="Camila Andrade",
        email="camila.andrade@yarumo.org",
        password_hash="stored-hash",
        role_title="Scientific Coordinator",
        accreditation_level=3,
        is_active=True,
    )


async def test_login_uses_a_hashed_opaque_refresh_token(researcher: LoginResearcher) -> None:
    repository = FakeAuthenticationRepository(researcher)
    refresh_tokens = FakeRefreshTokens()

    result = await Login(
        repository=repository,
        passwords=FakePasswords(),
        access_tokens=FakeAccessTokens(),
        refresh_tokens=refresh_tokens,
        refresh_token_days=14,
    ).execute(email="CAMILA.ANDRADE@YARUMO.ORG", password="correct")

    assert result.access_token.startswith("access:")
    assert result.refresh_token == "refresh-1"
    assert repository.created is not None
    assert repository.created["token_hash"] == "digest:refresh-1"
    assert repository.created["token_hash"] != result.refresh_token
    assert isinstance(repository.created["family_id"], UUID)
    assert isinstance(repository.created["expires_at"], datetime)
    assert repository.created["expires_at"].tzinfo is UTC


async def test_login_does_not_distinguish_unknown_accounts_from_wrong_passwords() -> None:
    use_case = Login(
        repository=FakeAuthenticationRepository(None),
        passwords=FakePasswords(),
        access_tokens=FakeAccessTokens(),
        refresh_tokens=FakeRefreshTokens(),
        refresh_token_days=14,
    )

    with pytest.raises(InvalidCredentials):
        await use_case.execute(email="unknown@yarumo.org", password="incorrect")


async def test_refresh_requires_a_cookie_and_rotates_the_token(researcher: LoginResearcher) -> None:
    repository = FakeAuthenticationRepository(researcher)
    refresh_tokens = FakeRefreshTokens()
    use_case = RefreshSession(
        repository=repository,
        access_tokens=FakeAccessTokens(),
        refresh_tokens=refresh_tokens,
        refresh_token_days=14,
    )

    with pytest.raises(InvalidRefreshToken):
        await use_case.execute(refresh_token=None)

    result = await use_case.execute(refresh_token="previous")

    assert result.refresh_token == "refresh-1"
    assert result.expires_in == 900


async def test_logout_revokes_the_refresh_token_family(researcher: LoginResearcher) -> None:
    repository = FakeAuthenticationRepository(researcher)
    await Logout(repository=repository, refresh_tokens=FakeRefreshTokens()).execute(
        refresh_token="session-token"
    )

    assert repository.revoked == {"token_hash": "digest:session-token", "reason": "logout"}
