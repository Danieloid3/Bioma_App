"""Black-box realtime chat test against a running API and its real Redis/PostgreSQL.

Run after ``docker compose up --build``:
``BIOMA_API_URL=http://localhost:8001 pytest -q backend/tests/test_api_chat_realtime_http.py``
"""

import json
import os
import threading
import time
from urllib.request import Request, urlopen

import pytest

API_URL = os.getenv("BIOMA_API_URL")
PASSWORD = "Bioma2026!"


def _request(path: str, *, method: str = "GET", payload: dict | None = None, token: str | None = None) -> dict:
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = Request(
        f"{API_URL}{path}",
        method=method,
        headers=headers,
        data=json.dumps(payload).encode() if payload is not None else None,
    )
    with urlopen(request, timeout=15) as response:
        return json.loads(response.read())


def _login(email: str) -> str:
    return _request("/v1/auth/login", method="POST", payload={"email": email, "password": PASSWORD})["access_token"]


def _read_first_event(token: str, received: list[dict]) -> None:
    try:
        request = Request(
            f"{API_URL}/v1/chat/events",
            headers={"Authorization": f"Bearer {token}", "Accept": "text/event-stream"},
        )
        with urlopen(request, timeout=4) as response:
            for raw_line in response:
                line = raw_line.decode().strip()
                if line.startswith("data:"):
                    received.append(json.loads(line[5:].strip()))
                    return
    except (TimeoutError, OSError):
        return


@pytest.mark.skipif(not API_URL, reason="set BIOMA_API_URL to run the HTTP integration test")
def test_chat_sse_notifies_members_but_not_non_members() -> None:
    assert API_URL is not None
    camila = _login("camila.andrade@yarumo.org")
    nestor = _login("nestor.quinones@yarumo.org")
    valentina = _login("valentina.rios@yarumo.org")
    directory = _request("/v1/researchers", token=camila)["items"]
    nestor_id = next(item["researcher_id"] for item in directory if item["full_name"] == "Néstor Quiñones")
    channel = _request(
        "/v1/chat/channels",
        method="POST",
        token=camila,
        payload={"channel_type": "direct", "member_ids": [nestor_id]},
    )

    member_events: list[dict] = []
    outsider_events: list[dict] = []
    member_listener = threading.Thread(target=_read_first_event, args=(nestor, member_events), daemon=True)
    outsider_listener = threading.Thread(target=_read_first_event, args=(valentina, outsider_events), daemon=True)
    member_listener.start()
    outsider_listener.start()
    time.sleep(0.5)  # subscriptions are registered before the committed write

    _request(
        f"/v1/chat/channels/{channel['channel_id']}/messages",
        method="POST",
        token=camila,
        payload={"message_text": "Prueba automática de señal SSE."},
    )
    member_listener.join(6)
    outsider_listener.join(6)

    assert member_events == [{"type": "message.created", "channel_id": channel["channel_id"]}]
    assert not any(event["channel_id"] == channel["channel_id"] for event in outsider_events)
