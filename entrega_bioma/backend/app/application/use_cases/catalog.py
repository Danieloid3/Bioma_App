from dataclasses import dataclass

from app.domain.models import ResearcherDirectoryItem, Site, Species
from app.domain.ports.repositories import CatalogRepository


@dataclass(slots=True)
class ListSpecies:
    catalog: CatalogRepository

    async def execute(self) -> list[Species]:
        return await self.catalog.list_species()


@dataclass(slots=True)
class ListSites:
    catalog: CatalogRepository

    async def execute(self) -> list[Site]:
        return await self.catalog.list_sites()


@dataclass(slots=True)
class ListResearchers:
    catalog: CatalogRepository

    async def execute(self) -> list[ResearcherDirectoryItem]:
        return await self.catalog.list_researchers()
