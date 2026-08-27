from typing import Annotated

import asyncpg
from fastapi import APIRouter, Depends

from app.application.use_cases.catalog import ListResearchers, ListSites, ListSpecies
from app.domain.models import Actor
from app.infrastructure.db.repositories import PostgresCatalogRepository
from app.presentation.api.dependencies import get_actor_connection
from app.presentation.api.errors import COMMON_ERROR_RESPONSES

router = APIRouter(tags=["catalog"])
ConnectionDependency = Annotated[tuple[Actor, asyncpg.Connection], Depends(get_actor_connection)]


@router.get("/v1/species", responses=COMMON_ERROR_RESPONSES)
async def list_species(connection_dependency: ConnectionDependency) -> dict[str, object]:
    _, connection = connection_dependency
    return {"items": await ListSpecies(PostgresCatalogRepository(connection)).execute()}


@router.get("/v1/sites", responses=COMMON_ERROR_RESPONSES)
async def list_sites(connection_dependency: ConnectionDependency) -> dict[str, object]:
    _, connection = connection_dependency
    return {"items": await ListSites(PostgresCatalogRepository(connection)).execute()}


@router.get("/v1/researchers", responses=COMMON_ERROR_RESPONSES)
async def list_researchers(connection_dependency: ConnectionDependency) -> dict[str, object]:
    _, connection = connection_dependency
    return {"items": await ListResearchers(PostgresCatalogRepository(connection)).execute()}
