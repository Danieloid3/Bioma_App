import logging
from time import perf_counter
from uuid import UUID, uuid4

from fastapi import Request, Response

logger = logging.getLogger(__name__)


def _correlation_id(value: str | None) -> str:
    if value:
        try:
            return str(UUID(value))
        except ValueError:
            pass
    return str(uuid4())


async def correlation_id_middleware(request: Request, call_next) -> Response:
    correlation_id = _correlation_id(request.headers.get("X-Correlation-ID"))
    request.state.correlation_id = correlation_id
    started_at = perf_counter()
    response = await call_next(request)
    response.headers["X-Correlation-ID"] = correlation_id
    logger.info(
        "request_completed correlation_id=%s method=%s path=%s status_code=%s duration_ms=%.2f",
        correlation_id,
        request.method,
        request.url.path,
        response.status_code,
        (perf_counter() - started_at) * 1000,
    )
    return response
