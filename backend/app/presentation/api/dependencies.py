from collections.abc import AsyncIterator
from typing import Annotated
from uuid import UUID

import jwt
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordBearer

from app.domain.models import Actor
from app.infrastructure.config import Settings, get_settings
from app.infrastructure.db.database import Database

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/v1/auth/login")


def get_database(request: Request) -> Database:
    return request.app.state.database


async def get_current_actor(
    token: Annotated[str, Depends(oauth2_scheme)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> Actor:
    try:
        claims = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
        return Actor(
            researcher_id=UUID(claims["sub"]),
            full_name=str(claims["name"]),
            role_title=str(claims["role"]),
            accreditation_level=int(claims["accreditation_level"]),
        )
    except (jwt.PyJWTError, KeyError, ValueError) as error:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid access token") from error


async def get_actor_connection(
    actor: Annotated[Actor, Depends(get_current_actor)],
    database: Annotated[Database, Depends(get_database)],
) -> AsyncIterator[tuple[Actor, object]]:
    async with database.actor_transaction(actor.researcher_id) as connection:
        yield actor, connection

