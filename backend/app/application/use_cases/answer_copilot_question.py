import re
from collections.abc import Awaitable, Callable, Sequence
from dataclasses import dataclass

from app.domain.errors import InvalidQuestion
from app.domain.models import (
    Actor,
    CatalogKnowledgeItem,
    ConversationMessage,
    CopilotAnswer,
    CopilotSource,
)
from app.domain.ports.ai import CopilotProvider, EmbeddingProvider

SYSTEM_PROMPT_VERSION = "2026-08-27.5"
SYSTEM_PROMPT = """You are Bioma's scientific wildlife copilot for the Yarumo Foundation.
You have access to:
1. The Official Bioma Catalog of Species and Monitored Sites (biological descriptions, habitats, diet, conservation status, ecosystems).
2. Authorized Field Sightings and monitoring notes recovered under strict research accreditation.

Guidelines:
- Answer naturally, warmly, factually and professionally in Spanish.
- Use rich, clear Markdown formatting:
  * Highlight species names, monitored sites, and key biological terms with bold (**Oso de anteojos**, **PNN Chingaza**, **Vulnerable (VU)**).
  * Use clean bullet points (- item) when presenting traits, diet, records, or multi-part observations.
- When referencing field sightings, cite every factual statement with the exact bracketed observation reference right after the statement, for example [obs-5001].
- When asked about a species' biology, diet, habitat, or conservation status, use the official Bioma Catalog information provided in context to give an accurate, natural and complete scientific explanation.
- Never invent coordinates or cite observation references that were not provided in context.
- If the query cannot be answered from the provided catalog or authorized sightings, state transparently and politely that no authorized data is available for that request."""


GREETING_SYSTEM_PROMPT = """You are Bioma's scientific field-record copilot for the Yarumo Foundation.
Greet the authenticated researcher warmly, professionally and naturally in Spanish, addressing them by their name.
Explain briefly that you are available to help explore, summarize and query authorized wildlife field sightings,
species, and monitoring notes according to their research accreditation."""

NO_AUTHORIZED_CONTEXT_RESPONSE = (
    "No dispongo de contexto autorizado suficiente para responder esa consulta. "
    "No puedo inferir ni aproximar información que no esté disponible para tu nivel de acceso."
)
NO_CITED_SOURCES_RESPONSE = (
    "No puedo presentar una respuesta verificable porque no se incluyeron citas válidas "
    "a los avistamientos autorizados."
)
_CITATION_PATTERN = re.compile(r"\[([A-Za-z0-9][A-Za-z0-9_-]{0,63})\]")
_GREETING_PATTERN = re.compile(
    r"^(hola|buenos\s+d[ií]as|buenas\s+tardes|buenas\s+noches|buenas|qu[eé]\s+tal|c[oó]mo\s+est[aá]s|"
    r"qui[eé]n\s+eres|qu[eé]\s+puedes\s+hacer|qu[eé]\s+haces|ayuda|gracias|muchas\s+gracias|hello|hi)\b",
    re.IGNORECASE,
)


def _is_greeting(text: str) -> bool:
    clean = text.strip()
    return bool(_GREETING_PATTERN.search(clean)) and len(clean.split()) <= 10


def _cited_sources(text: str, authorized_sources: Sequence[CopilotSource]) -> tuple[CopilotSource, ...]:
    """Return authorized sources explicitly cited in answer order, without trusting the model."""
    sources_by_reference = {source.observation_reference: source for source in authorized_sources}
    cited: list[CopilotSource] = []
    seen_references: set[str] = set()
    for match in _CITATION_PATTERN.finditer(text):
        reference = match.group(1)
        if reference not in seen_references and (source := sources_by_reference.get(reference)):
            cited.append(source)
            seen_references.add(reference)
    return tuple(cited)


@dataclass(slots=True)
class AnswerCopilotQuestion:
    embeddings: EmbeddingProvider
    copilot: CopilotProvider
    context: Callable[[Sequence[float]], Awaitable[list[CopilotSource]]]
    audit: Callable[..., Awaitable[object]]
    catalog: Callable[[], Awaitable[list[CatalogKnowledgeItem]]] | None = None

    async def execute(
        self,
        *,
        actor: Actor,
        question: str,
        history: Sequence[ConversationMessage] = (),
    ) -> CopilotAnswer:
        clean_question = question.strip()
        if not clean_question:
            raise InvalidQuestion("question is required")

        if _is_greeting(clean_question):
            answer = await self.copilot.answer(
                actor_name=actor.full_name,
                actor_role=actor.role_title,
                question=clean_question,
                sources=(),
                system_prompt=GREETING_SYSTEM_PROMPT,
                history=history,
            )
            final_answer = CopilotAnswer(
                text=answer.text,
                sources=(),
                model_name=answer.model_name,
                input_tokens=answer.input_tokens,
                output_tokens=answer.output_tokens,
            )
            await self.audit(
                prompt=clean_question,
                answer=final_answer.text,
                system_prompt_version=SYSTEM_PROMPT_VERSION,
                model_name=final_answer.model_name,
                input_tokens=final_answer.input_tokens,
                output_tokens=final_answer.output_tokens,
                sources=(),
            )
            return final_answer

        query_embedding = await self.embeddings.embed_query(clean_question)
        sources = await self.context(query_embedding)
        catalog_items: list[CatalogKnowledgeItem] = []
        if self.catalog is not None:
            catalog_items = await self.catalog()

        if sources or catalog_items:
            answer = await self.copilot.answer(
                actor_name=actor.full_name,
                actor_role=actor.role_title,
                question=clean_question,
                sources=sources,
                system_prompt=SYSTEM_PROMPT,
                history=history,
                catalog_knowledge=catalog_items,
            )
            cited_sources = _cited_sources(answer.text, sources)
            if sources and not cited_sources:
                final_answer = CopilotAnswer(
                    text=NO_CITED_SOURCES_RESPONSE,
                    sources=(),
                    model_name=answer.model_name,
                    input_tokens=answer.input_tokens,
                    output_tokens=answer.output_tokens,
                )
            else:
                final_answer = CopilotAnswer(
                    text=answer.text,
                    sources=cited_sources,
                    model_name=answer.model_name,
                    input_tokens=answer.input_tokens,
                    output_tokens=answer.output_tokens,
                )
        else:
            final_answer = CopilotAnswer(
                text=NO_AUTHORIZED_CONTEXT_RESPONSE,
                sources=(),
                model_name="bioma-policy",
                input_tokens=0,
                output_tokens=0,
            )


        await self.audit(
            prompt=clean_question,
            answer=final_answer.text,
            system_prompt_version=SYSTEM_PROMPT_VERSION,
            model_name=final_answer.model_name,
            input_tokens=final_answer.input_tokens,
            output_tokens=final_answer.output_tokens,
            sources=final_answer.sources,
        )
        return final_answer


