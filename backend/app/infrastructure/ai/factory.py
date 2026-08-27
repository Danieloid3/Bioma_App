from app.domain.ports.ai import CopilotProvider, EmbeddingProvider
from app.infrastructure.ai.langchain_gateway import LangChainOpenAIGateway
from app.infrastructure.ai.local_gateway import LocalAiGateway
from app.infrastructure.config import Settings


def build_ai_gateway(settings: Settings) -> tuple[EmbeddingProvider, CopilotProvider]:
    """Factory pattern: the application depends on ports, never on a model vendor."""
    if (
        settings.bio_llm_provider == "openai"
        and settings.openai_api_key
        and settings.bio_llm_model
        and settings.bio_embedding_model
    ):
        gateway = LangChainOpenAIGateway(
            api_key=settings.openai_api_key,
            chat_model=settings.bio_llm_model,
            embedding_model=settings.bio_embedding_model,
        )
        return gateway, gateway

    # Fallback to offline local gateway for local development and demos
    local_gateway = LocalAiGateway(
        model_name=settings.bio_llm_model or "bioma-local-copilot",
        embedding_model_name=settings.bio_embedding_model or "local-embedding-1536",
    )
    return local_gateway, local_gateway

