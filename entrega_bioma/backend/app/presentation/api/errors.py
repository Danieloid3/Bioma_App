import logging
from collections.abc import Sequence
from typing import Any

import asyncpg
from fastapi import FastAPI, HTTPException, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.domain.errors import (
    InvalidCredentials,
    InvalidQuestion,
    InvalidRefreshToken,
    RateLimitExceeded,
    RefreshTokenReuseDetected,
)

logger = logging.getLogger(__name__)


POSTGRES_ERROR_MAP: dict[str, tuple[int, str, str]] = {
    "42501": (status.HTTP_403_FORBIDDEN, "forbidden", "No tienes permisos para esta operación."),
    "22023": (status.HTTP_422_UNPROCESSABLE_CONTENT, "invalid_request", "Solicitud inválida."),
    "23505": (status.HTTP_409_CONFLICT, "resource_conflict", "El recurso ya existe."),
    "P0001": (status.HTTP_401_UNAUTHORIZED, "authentication_required", "Autenticación requerida."),
    "P0002": (status.HTTP_404_NOT_FOUND, "species_not_found", "Especie no encontrada."),
    "P0003": (status.HTTP_404_NOT_FOUND, "site_not_found", "Sitio no encontrado."),
    "P0004": (status.HTTP_404_NOT_FOUND, "sighting_not_found", "Avistamiento no encontrado."),
    "P0005": (status.HTTP_404_NOT_FOUND, "sighting_not_found", "Avistamiento no encontrado."),
}


class ErrorDetail(BaseModel):
    field: str
    message: str


class ApiError(BaseModel):
    code: str
    message: str
    correlation_id: str
    details: list[ErrorDetail] | None = None


class ApiErrorResponse(BaseModel):
    error: ApiError


COMMON_ERROR_RESPONSES = {
    status.HTTP_401_UNAUTHORIZED: {"model": ApiErrorResponse},
    status.HTTP_403_FORBIDDEN: {"model": ApiErrorResponse},
    status.HTTP_404_NOT_FOUND: {"model": ApiErrorResponse},
    status.HTTP_409_CONFLICT: {"model": ApiErrorResponse},
    status.HTTP_422_UNPROCESSABLE_CONTENT: {"model": ApiErrorResponse},
    status.HTTP_500_INTERNAL_SERVER_ERROR: {"model": ApiErrorResponse},
    status.HTTP_429_TOO_MANY_REQUESTS: {"model": ApiErrorResponse},
}


def _correlation_id(request: Request) -> str:
    return getattr(request.state, "correlation_id", "unknown")


def _error_response(
    request: Request,
    *,
    status_code: int,
    code: str,
    message: str,
    details: Sequence[dict[str, str]] | None = None,
    headers: dict[str, str] | None = None,
) -> JSONResponse:
    content: dict[str, Any] = {
        "error": {
            "code": code,
            "message": message,
            "correlation_id": _correlation_id(request),
        }
    }
    if details:
        content["error"]["details"] = list(details)
    return JSONResponse(status_code=status_code, content=content, headers=headers)


def _validation_details(error: dict[str, Any]) -> dict[str, str]:
    location = ".".join(str(value) for value in error.get("loc", ()) if value != "body")
    return {"field": location or "request", "message": str(error.get("msg", "Valor inválido."))}


def install_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(RateLimitExceeded)
    async def rate_limit_handler(request: Request, exc: RateLimitExceeded) -> JSONResponse:
        return _error_response(
            request,
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            code="rate_limit_exceeded",
            message="Has superado el límite temporal de solicitudes.",
            headers={"Retry-After": str(exc.retry_after)},
        )

    @app.exception_handler(InvalidQuestion)
    async def invalid_question_handler(request: Request, _: InvalidQuestion) -> JSONResponse:
        return _error_response(
            request,
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            code="invalid_question",
            message="La pregunta no puede estar vacía.",
        )

    @app.exception_handler(InvalidCredentials)
    async def invalid_credentials_handler(request: Request, _: InvalidCredentials) -> JSONResponse:
        return _error_response(
            request,
            status_code=status.HTTP_401_UNAUTHORIZED,
            code="invalid_credentials",
            message="Correo o contraseña inválidos.",
        )

    @app.exception_handler(InvalidRefreshToken)
    async def invalid_refresh_token_handler(
        request: Request, _: InvalidRefreshToken
    ) -> JSONResponse:
        return _error_response(
            request,
            status_code=status.HTTP_401_UNAUTHORIZED,
            code="invalid_refresh_token",
            message="La sesión no puede renovarse.",
        )

    @app.exception_handler(RefreshTokenReuseDetected)
    async def refresh_token_reuse_handler(
        request: Request, _: RefreshTokenReuseDetected
    ) -> JSONResponse:
        return _error_response(
            request,
            status_code=status.HTTP_401_UNAUTHORIZED,
            code="refresh_token_reuse_detected",
            message="La sesión fue invalidada por seguridad.",
        )

    @app.exception_handler(RequestValidationError)
    async def request_validation_error_handler(
        request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        return _error_response(
            request,
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            code="validation_error",
            message="La solicitud no cumple el contrato de la API.",
            details=[_validation_details(error) for error in exc.errors()],
        )

    @app.exception_handler(HTTPException)
    @app.exception_handler(StarletteHTTPException)
    async def http_exception_handler(
        request: Request, exc: HTTPException | StarletteHTTPException
    ) -> JSONResponse:
        status_code = exc.status_code
        code, message = {
            status.HTTP_401_UNAUTHORIZED: ("invalid_access_token", "Token de acceso inválido."),
            status.HTTP_403_FORBIDDEN: ("forbidden", "No tienes permisos para esta operación."),
            status.HTTP_404_NOT_FOUND: ("not_found", "Recurso no encontrado."),
            status.HTTP_405_METHOD_NOT_ALLOWED: ("method_not_allowed", "Método no permitido."),
        }.get(status_code, ("http_error", "No fue posible procesar la solicitud."))
        return _error_response(
            request,
            status_code=status_code,
            code=code,
            message=message,
            headers=getattr(exc, "headers", None),
        )

    @app.exception_handler(asyncpg.PostgresError)
    async def postgres_error_handler(request: Request, exc: asyncpg.PostgresError) -> JSONResponse:
        status_code, code, message = POSTGRES_ERROR_MAP.get(
            exc.sqlstate,
            (status.HTTP_500_INTERNAL_SERVER_ERROR, "database_error", "Error interno."),
        )
        if status_code >= 500:
            logger.exception("database_error correlation_id=%s", _correlation_id(request))
        return _error_response(
            request, status_code=status_code, code=code, message=message
        )

    @app.exception_handler(Exception)
    async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
        logger.exception("unhandled_error correlation_id=%s", _correlation_id(request))
        return _error_response(
            request,
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            code="internal_error",
            message="Error interno.",
        )
