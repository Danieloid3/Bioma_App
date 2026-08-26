from collections.abc import Sequence

from langchain_core.messages import HumanMessage, SystemMessage
from langchain_openai import ChatOpenAI, OpenAIEmbeddings

from app.domain.models import CopilotAnswer, CopilotSource


class LangChainOpenAIGateway:
    """Adapter from domain ports to LangChain's provider-specific integrations."""

    def __init__(self, *, api_key: str, chat_model: str, embedding_model: str) -> None:
        self.model_name = chat_model
        self._chat = ChatOpenAI(api_key=api_key, model=chat_model, temperature=0)
        self._embeddings = OpenAIEmbeddings(api_key=api_key, model=embedding_model)
        self.embedding_model_name = embedding_model

    async def embed_query(self, text: str) -> list[float]:
        return await self._embeddings.aembed_query(text)

    async def embed_document(self, text: str) -> list[float]:
        return (await self._embeddings.aembed_documents([text]))[0]

    async def answer(
        self,
        *,
        actor_name: str,
        actor_role: str,
        question: str,
        sources: Sequence[CopilotSource],
        system_prompt: str,
    ) -> CopilotAnswer:
        context = "\n\n".join(
            f"[{source.observation_reference}] {source.species_common_name}: {source.field_notes}"
            for source in sources
        ) or "No authorized context was retrieved."
        response = await self._chat.ainvoke(
            [
                SystemMessage(content=system_prompt),
                HumanMessage(
                    content=(
                        f"Authenticated researcher: {actor_name} ({actor_role}).\n"
                        f"Authorized context only:\n{context}\n\nQuestion: {question}"
                    )
                ),
            ]
        )
        usage = getattr(response, "usage_metadata", {}) or {}
        return CopilotAnswer(
            text=str(response.content),
            sources=tuple(sources),
            model_name=self.model_name,
            input_tokens=int(usage.get("input_tokens", 0)),
            output_tokens=int(usage.get("output_tokens", 0)),
        )

