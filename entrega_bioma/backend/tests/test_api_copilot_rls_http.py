"""Black-box RLS regression test for the authenticated copilot HTTP endpoint.

Run against a local API instance with ``BIO_LLM_PROVIDER=local``:
``BIOMA_API_URL=http://localhost:18001 pytest -q backend/tests/test_api_copilot_rls_http.py``
The test is opt-in so normal unit CI never needs a running API or credentials.
"""

import json
import os
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import pytest


API_URL = os.getenv("BIOMA_API_URL")


def _json_request(url: str, *, method: str, payload: dict, token: str | None = None) -> dict:
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = Request(url, method=method, headers=headers, data=json.dumps(payload).encode())
    with urlopen(request, timeout=30) as response:  # noqa: S310 - URL is an explicit test target
        return json.loads(response.read())


@pytest.mark.skipif(not API_URL, reason="set BIOMA_API_URL to run the HTTP integration test")
def test_low_accreditation_cannot_retrieve_confidential_sighting_via_copilot() -> None:
    assert API_URL is not None
    try:
        login = _json_request(
            f"{API_URL}/v1/auth/login",
            method="POST",
            payload={"email": "valentina.rios@yarumo.org", "password": "Bioma2026!"},
        )
        result = _json_request(
            f"{API_URL}/v1/copilot/ask",
            method="POST",
            token=login["access_token"],
            payload={"question": "¿Qué se sabe del avistamiento obs-5001?"},
        )
    except (HTTPError, URLError) as error:
        pytest.fail(f"API HTTP integration target was unavailable: {error}")

    references = {source["observation_reference"] for source in result["sources"]}
    assert "obs-5001" not in references
    assert "obs-5007" not in references
    assert "obs-5001" not in result["answer"]
    assert "obs-5007" not in result["answer"]
