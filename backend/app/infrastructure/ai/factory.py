from app.domain.ports.ai import CopilotProvider, EmbeddingProvider
from app.infrastructure.ai.langchain_gateway import LangChainOpenAIGateway
from app.infrastructure.config import Settings


def build_ai_gateway(settings: Settings) -> tuple[EmbeddingProvider, CopilotProvider]:
    """Factory pattern: the application depends on ports, never on a model vendor."""
    if settings.bio_llm_provider != "openai":
        raise ValueError(f"unsupported AI provider: {settings.bio_llm_provider}")
    if (
        not settings.openai_api_key
        or not settings.bio_llm_model
        or not settings.bio_embedding_model
    ):
        raise ValueError("AI provider configuration is incomplete")
    gateway = LangChainOpenAIGateway(
        api_key=settings.openai_api_key,
        chat_model=settings.bio_llm_model,
        embedding_model=settings.bio_embedding_model,
    )
    return gateway, gateway
