from typing import Annotated

import asyncpg
from fastapi import APIRouter, Depends

from app.application.use_cases.dashboard import GetDashboard
from app.domain.models import Actor
from app.infrastructure.db.repositories import PostgresDashboardRepository
from app.presentation.api.dependencies import get_actor_connection
from app.presentation.api.errors import COMMON_ERROR_RESPONSES

router = APIRouter(prefix="/v1/dashboard", tags=["dashboard"])
ConnectionDependency = Annotated[tuple[Actor, asyncpg.Connection], Depends(get_actor_connection)]


@router.get("", responses=COMMON_ERROR_RESPONSES)
async def get_dashboard(connection_dependency: ConnectionDependency) -> dict[str, object]:
    _, connection = connection_dependency
    summary, classification, activity = await GetDashboard(PostgresDashboardRepository(connection)).execute()
    return {"summary": summary, "classification": classification, "activity": activity}
