from uuid import UUID

from app.application.use_cases.answer_copilot_question import (
    NO_AUTHORIZED_CONTEXT_RESPONSE,
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
    assert audit_calls[0]["sources"] == []


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

    await AnswerCopilotQuestion(
        embeddings=FakeEmbeddings(), copilot=CapturingCopilot(), context=context, audit=audit
    ).execute(actor=actor(), question="¿Qué observaciones autorizadas existen?")

    assert received_sources == [source]
