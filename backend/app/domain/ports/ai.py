from typing import Protocol, Sequence

from app.domain.models import CopilotAnswer, CopilotSource


class EmbeddingProvider(Protocol):
    model_name: str

    async def embed_query(self, text: str) -> list[float]: ...

    async def embed_document(self, text: str) -> list[float]: ...


class CopilotProvider(Protocol):
    model_name: str

    async def answer(
        self,
        *,
        actor_name: str,
        actor_role: str,
        question: str,
        sources: Sequence[CopilotSource],
        system_prompt: str,
    ) -> CopilotAnswer: ...

