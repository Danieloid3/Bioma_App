import hashlib
import secrets
from datetime import UTC, datetime, timedelta

import bcrypt
import jwt

from app.domain.models import Actor


class BcryptPasswordVerifier:
    def verify(self, password: str, password_hash: str) -> bool:
        try:
            return bcrypt.checkpw(password.encode(), password_hash.encode())
        except (TypeError, ValueError):
            return False


class OpaqueRefreshTokenService:
    def generate(self) -> str:
        return secrets.token_urlsafe(48)

    def digest(self, token: str) -> str:
        return hashlib.sha256(token.encode()).hexdigest()


class JwtAccessTokenIssuer:
    def __init__(self, *, secret: str, algorithm: str, expires_in_minutes: int) -> None:
        self._secret = secret
        self._algorithm = algorithm
        self.expires_in_seconds = expires_in_minutes * 60

    def issue(self, actor: Actor) -> str:
        issued_at = datetime.now(UTC)
        return jwt.encode(
            {
                "sub": str(actor.researcher_id),
                "name": actor.full_name,
                "role": actor.role_title,
                "accreditation_level": actor.accreditation_level,
                "type": "access",
                "iat": issued_at,
                "exp": issued_at + timedelta(seconds=self.expires_in_seconds),
            },
            self._secret,
            algorithm=self._algorithm,
        )
