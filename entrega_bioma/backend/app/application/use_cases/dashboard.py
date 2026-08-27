from dataclasses import dataclass

from app.domain.models import ActivityItem, ClassificationCount, DashboardSummary
from app.domain.ports.repositories import DashboardRepository


@dataclass(slots=True)
class GetDashboard:
    dashboard: DashboardRepository

    async def execute(self) -> tuple[DashboardSummary, list[ClassificationCount], list[ActivityItem]]:
        summary = await self.dashboard.summary()
        classification = await self.dashboard.classification()
        activity = await self.dashboard.activity(limit=6)
        return summary, classification, activity
