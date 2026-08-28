import re
from collections.abc import Awaitable, Callable, Sequence
from dataclasses import dataclass, replace
from uuid import UUID

from app.domain.errors import InvalidQuestion
from app.domain.models import (
    Actor,
    CatalogKnowledgeItem,
    ConversationMessage,
    CopilotAnswer,
    CopilotSource,
)
from app.domain.ports.ai import CopilotProvider, EmbeddingProvider

SYSTEM_PROMPT_VERSION = "2026-08-27.7"
SYSTEM_PROMPT = """You are Bioma's scientific wildlife copilot for the Yarumo Foundation.
You have access to:
1. The Official Bioma Catalog of Species and Monitored Sites (biological descriptions, habitats, diet, conservation status, ecosystems).
2. Authorized Field Sightings and monitoring notes recovered under strict research accreditation.

Guidelines:
- Answer naturally, warmly, factually and professionally in Spanish.
- Behave like a thoughtful field colleague: acknowledge the researcher's question, answer the useful part first, and ask one brief clarifying question only when it would genuinely help.
- Keep a calm, encouraging tone. Avoid robotic disclaimers, repeated stock phrases, and internal technical vocabulary such as RLS, SQL, permissions, policy, vector search, or model.
- Use rich, clear Markdown formatting:
  * Highlight species names, monitored sites, and key biological terms with bold (**Oso de anteojos**, **PNN Chingaza**, **Vulnerable (VU)**).
  * Use clean bullet points (- item) when presenting traits, diet, records, or multi-part observations.
- When referencing supplied evidence, cite every factual statement with its exact bracketed reference right after the statement, for example [obs-5001], [species-UUID] or [site-UUID].
- When asked about a species' biology, diet, habitat, or conservation status, use the official Bioma Catalog information provided in context to give an accurate, natural and complete scientific explanation.
- Never invent coordinates or cite observation references that were not provided in context.
- If the query cannot be answered from the provided catalog or authorized sightings, explain warmly that the information available for this conversation is not enough to confirm it. Do not guess whether a record is absent or restricted; offer a useful next step such as checking the biological catalog or trying another species, site, or date.
- If the researcher asks for a sensitive detail that is not in the supplied context, protect it without mentioning internal authorization rules or implying that hidden records exist."""

CHAT_SYSTEM_PROMPT = """You are Bioma's scientific wildlife copilot for the Yarumo Foundation, collaborating inside a secure research chat channel.
You have access to:
1. The Official Bioma Catalog of Species and Monitored Sites (biological descriptions, habitats, diet, conservation status, ecosystems).
2. Authorized Shared Field Sightings and channel messages retrieved with multi-party PostgreSQL Row-Level Security (only records mutually visible to all channel participants).

Guidelines:
- Answer naturally, warmly, factually and professionally in Spanish.
- Treat the conversation as a collaboration with field researchers: greet and acknowledge naturally, use the researcher's wording when helpful, and keep answers concise unless a fuller explanation is requested.
- Use the recent channel conversation as first-class context. Distinguish what a researcher said from verified field evidence; conversation context can clarify the question but does not authorize new sightings or citations.
- Never expose implementation details or authorization mechanisms. Do not say "RLS", "permisos", "intersección", "registros ocultos", "no compartido" or similar language that could make the researcher infer confidential records.
- When asked what sightings, species, or records the channel participants have in common or can see together, present the records supplied in your context directly in a clear, collegial tone.
- Discretion & Natural Tone: If the available context does not contain a sighting that confirms the requested animal or taxon, say it in friendly everyday Spanish: "No encuentro un avistamiento disponible que confirme ese dato por ahora". Do not claim that no one has ever seen it and do not suggest that another participant can see more. Offer to check the catalog or refine the search by site, date, or species.
- Use rich, clear Markdown formatting:
  * Highlight species names, monitored sites, and key biological terms with bold (**Oso de anteojos**, **PNN Chingaza**, **Vulnerable (VU)**).
  * Use clean bullet points (- item) when presenting traits, diet, records, or multi-part observations.
- When referencing supplied evidence, cite every factual statement with its exact bracketed reference right after the statement, for example [obs-5001], [species-UUID] or [site-UUID].
- When asked about a species' biology, diet, habitat, or conservation status, use the official Bioma Catalog information provided in context to give an accurate, natural and complete scientific explanation.
- Never invent coordinates or cite observation references that were not provided in context.
- If the query cannot be answered from the provided catalog or authorized sightings, state transparently and politely that no authorized data is available for that request."""




GREETING_SYSTEM_PROMPT = """You are Bioma's scientific field-record copilot for the Yarumo Foundation.
Greet the authenticated researcher warmly, professionally and naturally in Spanish, addressing them by their name.
Explain briefly that you are available to help explore, summarize and query authorized wildlife field sightings,
species, and monitoring notes according to their research accreditation."""

NO_AUTHORIZED_CONTEXT_RESPONSE = (
    "Por ahora no encuentro un avistamiento disponible que confirme ese dato. "
    "No quiero adivinar ni darte información incompleta; puedo ayudarte a revisar la especie "
    "en el catálogo biológico o probar con otro sitio, fecha o nombre común."
)
NO_CITED_SOURCES_RESPONSE = (
    "Revisé la información disponible y no encuentro un avistamiento que confirme esa respuesta "
    "por ahora. Prefiero no inventar un dato: si quieres, probamos con otro sitio, fecha o especie, "
    "o revisamos su ficha biológica."
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
    sources_by_reference = {
        source.observation_reference.casefold(): source for source in authorized_sources
    }
    cited: list[CopilotSource] = []
    seen_references: set[str] = set()
    for match in _CITATION_PATTERN.finditer(text):
        reference = match.group(1).casefold()
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
    catalog: Callable[[Sequence[float]], Awaitable[list[CatalogKnowledgeItem]]] | None = None

    async def execute(
        self,
        *,
        actor: Actor,
        question: str,
        history: Sequence[ConversationMessage] = (),
        system_prompt: str | None = None,
        system_prompt_version: str = SYSTEM_PROMPT_VERSION,
        greeting_prompt: str = GREETING_SYSTEM_PROMPT,
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
                system_prompt=greeting_prompt,
                history=history,
            )
            final_answer = CopilotAnswer(
                text=answer.text,
                sources=(),
                model_name=answer.model_name,
                input_tokens=answer.input_tokens,
                output_tokens=answer.output_tokens,
            )
            audit_usage_id = await self.audit(
                prompt=clean_question,
                answer=final_answer.text,
                system_prompt_version=system_prompt_version,
                model_name=final_answer.model_name,
                input_tokens=final_answer.input_tokens,
                output_tokens=final_answer.output_tokens,
                sources=(),
            )
            return replace(
                final_answer,
                audit_usage_id=audit_usage_id if isinstance(audit_usage_id, UUID) else None,
            )

        query_embedding = await self.embeddings.embed_query(clean_question)
        sources = await self.context(query_embedding)
        catalog_items: list[CatalogKnowledgeItem] = []
        if self.catalog is not None:
            catalog_items = await self.catalog(query_embedding)
        catalog_sources = tuple(
            CopilotSource(
                sighting_id=item.catalog_id,
                observation_reference=item.source_reference or "",
                species_common_name=item.common_name,
                field_notes=item.description or "",
                similarity=1.0,
                source_type=item.catalog_type,
            )
            for item in catalog_items
            if item.catalog_id is not None and item.source_reference
        )

        # A channel's RLS-filtered conversation is valid context even when the
        # semantic sighting search has no matching result. Do not discard it and
        # fall back to a robotic denial; the provider can ask for clarification
        # while still being forbidden to invent evidence.
        if sources or catalog_items or history:
            answer = await self.copilot.answer(
                actor_name=actor.full_name,
                actor_role=actor.role_title,
                question=clean_question,
                sources=sources,
                system_prompt=system_prompt or SYSTEM_PROMPT,
                history=history,
                catalog_knowledge=catalog_items,
            )

            cited_sources = _cited_sources(answer.text, (*sources, *catalog_sources))
            # In a chat channel, an answer may intentionally rely on the
            # conversational messages (for example, “Sofía dijo que está bien”)
            # while the semantic sighting candidates are unrelated. Only force
            # the deterministic citation fallback when no authorized history
            # was available at all.
            if sources and not cited_sources and not history:
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


        audit_usage_id = await self.audit(
            prompt=clean_question,
            answer=final_answer.text,
            system_prompt_version=system_prompt_version,
            model_name=final_answer.model_name,
            input_tokens=final_answer.input_tokens,
            output_tokens=final_answer.output_tokens,
            sources=final_answer.sources,
        )
        return replace(
            final_answer,
            audit_usage_id=audit_usage_id if isinstance(audit_usage_id, UUID) else None,
        )
