from uuid import UUID

from app.application.use_cases.answer_copilot_question import (
    NO_AUTHORIZED_CONTEXT_RESPONSE,
    NO_CITED_SOURCES_RESPONSE,
    AnswerCopilotQuestion,
)
from app.domain.models import Actor, CopilotAnswer, CopilotSource


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
