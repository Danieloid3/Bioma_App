from fastapi import FastAPI, HTTPException, status
from fastapi.testclient import TestClient
from pydantic import BaseModel

from app.presentation.api.errors import install_exception_handlers
from app.presentation.api.middleware import correlation_id_middleware


class RequiredPayload(BaseModel):
    name: str


def build_test_app() -> FastAPI:
    app = FastAPI()
    app.middleware("http")(correlation_id_middleware)
    install_exception_handlers(app)

    @app.get("/protected")
    async def protected() -> None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid token")

    @app.post("/payload")
    async def payload(_: RequiredPayload) -> dict[str, bool]:
        return {"ok": True}

    return app


def test_correlation_id_is_preserved_when_valid() -> None:
    correlation_id = "f1a1e395-2d30-48f1-a7c0-3d69c8c51111"

    response = TestClient(build_test_app()).get(
        "/protected", headers={"X-Correlation-ID": correlation_id}
    )

    assert response.status_code == status.HTTP_401_UNAUTHORIZED
    assert response.headers["X-Correlation-ID"] == correlation_id
    assert response.json()["error"] == {
        "code": "invalid_access_token",
        "message": "Token de acceso inválido.",
        "correlation_id": correlation_id,
    }


def test_validation_error_does_not_echo_the_invalid_input() -> None:
    response = TestClient(build_test_app()).post("/payload", json={"name": 42})

    assert response.status_code == status.HTTP_422_UNPROCESSABLE_CONTENT
    assert response.json()["error"]["code"] == "validation_error"
    assert response.json()["error"]["details"] == [
        {"field": "name", "message": "Input should be a valid string"}
    ]
    assert "input" not in response.text
