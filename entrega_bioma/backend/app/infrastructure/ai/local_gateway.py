import hashlib
import math
import re
from collections.abc import Sequence

from app.domain.models import (
    CatalogKnowledgeItem,
    ConversationMessage,
    CopilotAnswer,
    CopilotSource,
)


class LocalAiGateway:
    """Local offline gateway for development and demonstration without external API keys."""

    def __init__(
        self,
        *,
        model_name: str = "bioma-local-copilot",
        embedding_model_name: str = "local-embedding-1536",
    ) -> None:
        self.model_name = model_name
        self.embedding_model_name = embedding_model_name

    def _text_to_vector(self, text: str, dim: int = 1536) -> list[float]:
        tokens = re.findall(r"[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ0-9]+", text.lower())
        vector = [0.0] * dim
        if not tokens:
            vector[0] = 1.0
            return vector

        for token in tokens:
            h = int(hashlib.sha256(token.encode("utf-8")).hexdigest(), 16)
            for shift in (0, 16, 32, 48):
                idx = (h >> shift) % dim
                vector[idx] += 1.0

        norm = math.sqrt(sum(v * v for v in vector))
        if norm > 0.0:
            return [v / norm for v in vector]
        vector[0] = 1.0
        return vector

    async def embed_query(self, text: str) -> list[float]:
        return self._text_to_vector(text)

    async def embed_document(self, text: str) -> list[float]:
        return self._text_to_vector(text)

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
        if not sources and history:
            latest = next((message for message in reversed(history) if message.role == "user"), None)
            detail = f' Recuerdo que se comentó: “{latest.content}”.' if latest else ""
            text = (
                "Sí, tengo presente el contexto de esta conversación, aunque no encontré un "
                f"avistamiento verificable que lo confirme todavía.{detail} "
                "Si quieres, puedo ayudarte a precisar la especie, el sitio o la fecha."
            )
            return CopilotAnswer(
                text=text,
                sources=(),
                model_name=self.model_name,
                input_tokens=len(question.split()),
                output_tokens=len(text.split()),
            )

        if not sources:
            return CopilotAnswer(
                text="No dispongo de contexto autorizado suficiente para responder esa consulta.",
                sources=(),
                model_name=self.model_name,
                input_tokens=len(question.split()),
                output_tokens=12,
            )

        lines = [
            "De acuerdo con los registros autorizados para tu nivel de investigación:",
            "",
        ]
        for source in sources:
            lines.append(
                f"• Se registra **{source.species_common_name}** ([{source.observation_reference}]): {source.field_notes}"
            )

        answer_text = "\n".join(lines)
        input_tokens = len(question.split()) + sum(len(s.field_notes.split()) for s in sources)
        output_tokens = len(answer_text.split())

        return CopilotAnswer(
            text=answer_text,
            sources=tuple(sources),
            model_name=self.model_name,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
        )
