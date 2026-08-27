from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status

from app.infrastructure.db.database import Database
from app.presentation.api.dependencies import get_database
from app.presentation.api.errors import ApiErrorResponse

router = APIRouter(tags=["health"])


@router.get("/health", summary="Service liveness")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@router.get(
    "/ready",
    summary="Service readiness",
    responses={status.HTTP_503_SERVICE_UNAVAILABLE: {"model": ApiErrorResponse}},
)
async def readiness(database: Annotated[Database, Depends(get_database)]) -> dict[str, str]:
    if not await database.is_ready():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="database unavailable"
        )
    return {"status": "ready"}
