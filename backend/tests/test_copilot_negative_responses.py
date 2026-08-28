from uuid import UUID

from app.application.use_cases.answer_copilot_question import (
    NO_AUTHORIZED_CONTEXT_RESPONSE,
    NO_CITED_SOURCES_RESPONSE,
    AnswerCopilotQuestion,
)
from app.domain.models import (
    Actor,
    CatalogKnowledgeItem,
    ConversationMessage,
    CopilotAnswer,
    CopilotSource,
)


class FakeEmbeddings:
    async def embed_query(self, text: str) -> list[float]:
        return [0.0, 1.0]


class FakeCopilot:
    def __init__(self) -> None:
        self.called = False

    async def answer(self, **_: object) -> CopilotAnswer:
        self.called = True
        return CopilotAnswer("unexpected", (), "fake", 1, 1)


def actor() -> Actor:
    return Actor(
        researcher_id=UUID("80000000-0000-0000-0000-000000000001"),
        full_name="Valentina Ríos",
        role_title="Field Technician",
        accreditation_level=1,
    )


async def test_copilot_denies_transparently_when_rls_returns_no_authorized_context() -> None:
    copilot = FakeCopilot()
    audit_calls: list[dict[str, object]] = []

    async def context(_: list[float]) -> list[CopilotSource]:
        return []

    async def audit(**kwargs: object) -> object:
        audit_calls.append(kwargs)
        return UUID("80000000-0000-0000-0000-000000000002")

    answer = await AnswerCopilotQuestion(
        embeddings=FakeEmbeddings(), copilot=copilot, context=context, audit=audit
    ).execute(actor=actor(), question="¿Dónde está el jaguar confidencial?")

    assert answer.text == NO_AUTHORIZED_CONTEXT_RESPONSE
    assert answer.sources == ()
    assert answer.model_name == "bioma-policy"
    assert answer.audit_usage_id == UUID("80000000-0000-0000-0000-000000000002")
    assert not copilot.called
    assert audit_calls[0]["sources"] == ()


async def test_copilot_never_receives_sources_not_returned_by_authorized_context() -> None:
    source = CopilotSource(
        sighting_id=UUID("80000000-0000-0000-0000-000000000003"),
        observation_reference="obs-public-1",
        species_common_name="Oso de anteojos",
        field_notes="Avistamiento autorizado.",
        similarity=0.95,
    )
    received_sources: list[CopilotSource] = []

    class CapturingCopilot:
        async def answer(self, **kwargs: object) -> CopilotAnswer:
            received_sources.extend(kwargs["sources"])  # type: ignore[arg-type]
            return CopilotAnswer("Respuesta con [obs-public-1].", (source,), "fake", 2, 1)

    async def context(_: list[float]) -> list[CopilotSource]:
        return [source]

    async def audit(**_: object) -> object:
        return UUID("80000000-0000-0000-0000-000000000004")

    answer = await AnswerCopilotQuestion(
        embeddings=FakeEmbeddings(), copilot=CapturingCopilot(), context=context, audit=audit
    ).execute(actor=actor(), question="¿Qué observaciones autorizadas existen?")

    assert received_sources == [source]
    assert answer.sources == (source,)


async def test_copilot_returns_and_audits_only_authorized_sources_cited_in_answer() -> None:
    bear = CopilotSource(
        sighting_id=UUID("80000000-0000-0000-0000-000000000005"),
        observation_reference="obs-bear-1",
        species_common_name="Oso de anteojos",
        field_notes="Rastros de alimentación.",
        similarity=0.96,
    )
    jaguar = CopilotSource(
        sighting_id=UUID("80000000-0000-0000-0000-000000000006"),
        observation_reference="obs-jaguar-1",
        species_common_name="Jaguar",
        field_notes="Registro autorizado pero no citado.",
        similarity=0.74,
    )
    audit_calls: list[dict[str, object]] = []

    class BearOnlyCopilot:
        async def answer(self, **_: object) -> CopilotAnswer:
            return CopilotAnswer("Hay un registro de oso [obs-bear-1].", (bear, jaguar), "fake", 4, 2)

    async def context(_: list[float]) -> list[CopilotSource]:
        return [bear, jaguar]

    async def audit(**kwargs: object) -> object:
        audit_calls.append(kwargs)
        return UUID("80000000-0000-0000-0000-000000000007")

    answer = await AnswerCopilotQuestion(
        embeddings=FakeEmbeddings(), copilot=BearOnlyCopilot(), context=context, audit=audit
    ).execute(actor=actor(), question="¿Se han visto osos?")

    assert answer.sources == (bear,)
    assert audit_calls[0]["sources"] == (bear,)


async def test_copilot_hides_uncitable_model_response_and_audits_no_citations() -> None:
    source = CopilotSource(
        sighting_id=UUID("80000000-0000-0000-0000-000000000008"),
        observation_reference="obs-bear-2",
        species_common_name="Oso de anteojos",
        field_notes="Registro autorizado.",
        similarity=0.94,
    )
    audit_calls: list[dict[str, object]] = []

    class UncitedCopilot:
        async def answer(self, **_: object) -> CopilotAnswer:
            return CopilotAnswer("Hay evidencia reciente.", (source,), "fake", 3, 2)

    async def context(_: list[float]) -> list[CopilotSource]:
        return [source]

    async def audit(**kwargs: object) -> object:
        audit_calls.append(kwargs)
        return UUID("80000000-0000-0000-0000-000000000009")

    answer = await AnswerCopilotQuestion(
        embeddings=FakeEmbeddings(), copilot=UncitedCopilot(), context=context, audit=audit
    ).execute(actor=actor(), question="¿Se han visto osos?")

    assert answer.text == NO_CITED_SOURCES_RESPONSE
    assert answer.sources == ()
    assert audit_calls[0]["sources"] == ()


async def test_channel_history_can_answer_without_citing_unrelated_sighting_candidates() -> None:
    source = CopilotSource(
        sighting_id=UUID("80000000-0000-0000-0000-000000000010"),
        observation_reference="obs-unrelated-1",
        species_common_name="Rana",
        field_notes="Registro no relacionado.",
        similarity=0.51,
    )

    class ConversationalCopilot:
        async def answer(self, **_: object) -> CopilotAnswer:
            return CopilotAnswer("Sí, Sofía dijo que está bien.", (), "fake", 4, 5)

    async def context(_: list[float]) -> list[CopilotSource]:
        return [source]

    async def audit(**_: object) -> object:
        return UUID("80000000-0000-0000-0000-000000000011")

    answer = await AnswerCopilotQuestion(
        embeddings=FakeEmbeddings(), copilot=ConversationalCopilot(), context=context, audit=audit
    ).execute(
        actor=actor(),
        question="¿Cómo está Sofía?",
        history=[ConversationMessage(role="user", content="Sofía dijo que está bien.")],
    )

    assert answer.text == "Sí, Sofía dijo que está bien."
    assert answer.sources == ()


async def test_citations_match_references_case_insensitively() -> None:
    source = CopilotSource(
        sighting_id=UUID("80000000-0000-0000-0000-000000000012"),
        observation_reference="obs-5004",
        species_common_name="Colibrí chillón",
        field_notes="Registro autorizado.",
        similarity=0.9,
    )

    class CitingCopilot:
        async def answer(self, **_: object) -> CopilotAnswer:
            return CopilotAnswer("Se registró el ave [OBS-5004].", (source,), "fake", 2, 3)

    async def audit(**_: object) -> object:
        return UUID("80000000-0000-0000-0000-000000000013")

    async def context(_: list[float]) -> list[CopilotSource]:
        return [source]

    answer = await AnswerCopilotQuestion(
        embeddings=FakeEmbeddings(), copilot=CitingCopilot(), context=context, audit=audit
    ).execute(actor=actor(), question="¿Qué ave fue registrada?")

    assert answer.sources == (source,)


async def test_catalog_citation_is_validated_and_returned_as_its_own_source_type() -> None:
    catalog_id = UUID("80000000-0000-0000-0000-000000000014")

    class CatalogCopilot:
        async def answer(self, **_: object) -> CopilotAnswer:
            return CopilotAnswer(f"El jaguar es un felino [species-{catalog_id}].", (), "fake", 2, 3)

    async def context(_: list[float]) -> list[CopilotSource]: return []
    async def catalog(_: list[float]) -> list[CatalogKnowledgeItem]:
        return [CatalogKnowledgeItem(catalog_type="species", catalog_id=catalog_id, source_reference=f"species-{catalog_id}", common_name="Jaguar", description="Felino silvestre")]
    async def audit(**_: object) -> object: return UUID("80000000-0000-0000-0000-000000000015")

    answer = await AnswerCopilotQuestion(embeddings=FakeEmbeddings(), copilot=CatalogCopilot(), context=context, audit=audit, catalog=catalog).execute(actor=actor(), question="Háblame del jaguar")
    assert len(answer.sources) == 1
    assert answer.sources[0].source_type == "species"
    assert answer.sources[0].sighting_id == catalog_id


async def test_catalog_answer_falls_back_to_verifiable_database_text_when_model_omits_citation() -> None:
    catalog_id = UUID("80000000-0000-0000-0000-000000000016")

    class UncitedCatalogCopilot:
        async def answer(self, **_: object) -> CopilotAnswer:
            return CopilotAnswer("El jaguar es un felino.", (), "fake", 2, 3)

    async def context(_: list[float]) -> list[CopilotSource]: return []
    async def catalog(_: list[float]) -> list[CatalogKnowledgeItem]:
        return [CatalogKnowledgeItem(catalog_type="species", catalog_id=catalog_id, source_reference=f"species-{catalog_id}", common_name="Jaguar", description="Felino silvestre")]
    async def audit(**_: object) -> object: return UUID("80000000-0000-0000-0000-000000000017")

    answer = await AnswerCopilotQuestion(embeddings=FakeEmbeddings(), copilot=UncitedCatalogCopilot(), context=context, audit=audit, catalog=catalog).execute(actor=actor(), question="Háblame del jaguar")
    assert answer.model_name == "bioma-catalog-policy"
    assert f"[species-{catalog_id}]" in answer.text
    assert answer.sources[0].source_type == "species"
