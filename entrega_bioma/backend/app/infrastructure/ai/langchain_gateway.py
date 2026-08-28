from collections.abc import Sequence

from langchain_core.messages import AIMessage, BaseMessage, HumanMessage, SystemMessage
from langchain_openai import ChatOpenAI, OpenAIEmbeddings

from app.domain.models import (
    CatalogKnowledgeItem,
    ConversationMessage,
    CopilotAnswer,
    CopilotSource,
)


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
        history: Sequence[ConversationMessage] = (),
        catalog_knowledge: Sequence[CatalogKnowledgeItem] = (),
    ) -> CopilotAnswer:
        sections: list[str] = [f"Investigador autenticado: {actor_name} ({actor_role})."]

        if catalog_knowledge:
            cat_lines: list[str] = ["=== Catálogo de Especies y Sitios de Bioma ==="]
            for item in catalog_knowledge:
                if item.catalog_type == "species":
                    cat_lines.append(
                        f"• [{item.source_reference}] {item.common_name} ({item.scientific_name}, UICN: {item.iucn_category}): "
                        f"{item.description or ''} Hábitat: {item.habitat or ''}. "
                        f"Dieta: {item.diet or ''}. Estado de conservación: {item.conservation_status or ''}."
                    )
                elif item.catalog_type == "site":
                    cat_lines.append(
                        f"• [{item.source_reference}] {item.common_name} ({item.region}, Ecosistema: {item.ecosystem or 'N/A'}): "
                        f"{item.description or ''}"
                    )
            sections.append("\n".join(cat_lines))

        if sources:
            context_blocks: list[str] = ["=== Evidencia autorizada ==="]
            for source in sources:
                if source.source_type == "message":
                    context_blocks.append(f"[{source.observation_reference}] Mensaje de {source.species_common_name}: {source.field_notes}")
                else:
                    loc = f" (Sitio: {source.site_name}, {source.region})" if source.site_name else ""
                    context_blocks.append(f"[{source.observation_reference}] Especie: {source.species_common_name}{loc}. Notas de campo: {source.field_notes}")
            sections.append("\n".join(context_blocks))

        sections.append(f"Pregunta del investigador: {question}")
        content = "\n\n".join(sections)



        messages: list[BaseMessage] = [SystemMessage(content=system_prompt)]
        for msg in history:
            if msg.role == "user":
                messages.append(HumanMessage(content=msg.content))
            elif msg.role == "assistant":
                messages.append(AIMessage(content=msg.content))

        messages.append(HumanMessage(content=content))

        response = await self._chat.ainvoke(messages)
        usage = getattr(response, "usage_metadata", {}) or {}
        return CopilotAnswer(
            text=str(response.content),
            sources=tuple(sources),
            model_name=self.model_name,
            input_tokens=int(usage.get("input_tokens", 0)),
            output_tokens=int(usage.get("output_tokens", 0)),
        )
