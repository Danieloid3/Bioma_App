import asyncio
from typing import Annotated

from fastapi import APIRouter, Depends, Request, Response, status
from pydantic import BaseModel, Field

from app.application.use_cases.authentication import Login, Logout, RefreshSession
from app.domain.errors import RateLimitExceeded
from app.domain.models import Actor, AuthenticationResult
from app.infrastructure.config import Settings, get_settings
from app.infrastructure.db.database import Database
from app.infrastructure.db.repositories import PostgresAuthenticationRepository
from app.infrastructure.rate_limit import RedisRateLimiter, private_fingerprint
from app.infrastructure.security import (
    BcryptPasswordVerifier,
    JwtAccessTokenIssuer,
    OpaqueRefreshTokenService,
)
from app.presentation.api.dependencies import get_database, get_rate_limiter
from app.presentation.api.errors import COMMON_ERROR_RESPONSES

router = APIRouter(prefix="/v1/auth", tags=["authentication"])
DatabaseDependency = Annotated[Database, Depends(get_database)]
RateLimiterDependency = Annotated[RedisRateLimiter, Depends(get_rate_limiter)]
SettingsDependency = Annotated[Settings, Depends(get_settings)]


class LoginRequest(BaseModel):
    email: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=1, max_length=128)


class AuthenticatedResearcherResponse(BaseModel):
    researcher_id: str
    full_name: str
    role_title: str
    accreditation_level: int
    avatar_key: str


class AuthenticationResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int
    researcher: AuthenticatedResearcherResponse


def _access_token_issuer(settings: Settings) -> JwtAccessTokenIssuer:
    return JwtAccessTokenIssuer(
        secret=settings.jwt_secret,
        algorithm=settings.jwt_algorithm,
        expires_in_minutes=settings.access_token_minutes,
    )


def _authentication_response(result: AuthenticationResult) -> AuthenticationResponse:
    actor: Actor = result.actor
    return AuthenticationResponse(
        access_token=result.access_token,
        expires_in=result.expires_in,
        researcher=AuthenticatedResearcherResponse(
            researcher_id=str(actor.researcher_id),
            full_name=actor.full_name,
            role_title=actor.role_title,
            accreditation_level=actor.accreditation_level,
            avatar_key=actor.avatar_key,
        ),
    )


def _set_refresh_cookie(
    response: Response, result: AuthenticationResult, settings: Settings
) -> None:
    response.set_cookie(
        key=settings.refresh_cookie_name,
        value=result.refresh_token,
        max_age=settings.refresh_token_days * 24 * 60 * 60,
        httponly=True,
        secure=settings.refresh_cookie_secure,
        samesite=settings.refresh_cookie_samesite,
        path="/v1/auth",
    )


@router.post("/login", response_model=AuthenticationResponse, responses=COMMON_ERROR_RESPONSES)
async def login(
    payload: LoginRequest,
    request: Request,
    response: Response,
    database: DatabaseDependency,
    settings: SettingsDependency,
    rate_limiter: RateLimiterDependency,
) -> AuthenticationResponse:
    client_ip = request.client.host if request.client else "unknown"
    account_key = private_fingerprint(settings.jwt_secret, payload.email.strip().casefold())
    decisions = await asyncio.gather(
        rate_limiter.check(
            key=f"bioma:rl:login:ip:{client_ip}",
            limit=settings.rate_limit_login_ip,
            window_seconds=settings.rate_limit_window_seconds,
        ),
        rate_limiter.check(
            key=f"bioma:rl:login:account:{account_key}",
            limit=settings.rate_limit_login_account,
            window_seconds=settings.rate_limit_window_seconds,
        ),
    )
    blocked = next((decision for decision in decisions if not decision.allowed), None)
    if blocked:
        raise RateLimitExceeded(blocked.retry_after)
    async with database.connection() as connection:
        result = await Login(
            repository=PostgresAuthenticationRepository(connection),
            passwords=BcryptPasswordVerifier(),
            access_tokens=_access_token_issuer(settings),
            refresh_tokens=OpaqueRefreshTokenService(),
            refresh_token_days=settings.refresh_token_days,
        ).execute(email=payload.email, password=payload.password)
    _set_refresh_cookie(response, result, settings)
    return _authentication_response(result)


@router.post("/refresh", response_model=AuthenticationResponse, responses=COMMON_ERROR_RESPONSES)
async def refresh(
    request: Request,
    response: Response,
    database: DatabaseDependency,
    settings: SettingsDependency,
) -> AuthenticationResponse:
    async with database.connection() as connection:
        result = await RefreshSession(
            repository=PostgresAuthenticationRepository(connection),
            access_tokens=_access_token_issuer(settings),
            refresh_tokens=OpaqueRefreshTokenService(),
            refresh_token_days=settings.refresh_token_days,
        ).execute(refresh_token=request.cookies.get(settings.refresh_cookie_name))
    _set_refresh_cookie(response, result, settings)
    return _authentication_response(result)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT, responses=COMMON_ERROR_RESPONSES)
async def logout(
    request: Request, database: DatabaseDependency, settings: SettingsDependency
) -> Response:
    async with database.connection() as connection:
        await Logout(
            repository=PostgresAuthenticationRepository(connection),
            refresh_tokens=OpaqueRefreshTokenService(),
        ).execute(refresh_token=request.cookies.get(settings.refresh_cookie_name))
    response = Response(status_code=status.HTTP_204_NO_CONTENT)
    response.delete_cookie(
        key=settings.refresh_cookie_name,
        path="/v1/auth",
        secure=settings.refresh_cookie_secure,
        httponly=True,
        samesite=settings.refresh_cookie_samesite,
    )
    return response
