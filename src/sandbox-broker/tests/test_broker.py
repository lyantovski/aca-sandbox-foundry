import httpx
import pytest

from main import create_app


@pytest.fixture(autouse=True)
def clear_broker_token(monkeypatch):
    monkeypatch.delenv("ACA_SANDBOX_BROKER_TOKEN", raising=False)


@pytest.mark.asyncio
async def test_fetch_adapts_existing_implementation():
    calls = []

    async def fetcher(*, urls, topic, status_callback):
        calls.append((urls, topic))
        await status_callback([{"status": "active", "sandbox_id": "sandbox-1"}])
        return ([{"url": urls[0]}], [], [{"status": "success"}])

    app = create_app(fetcher)
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://broker"
    ) as client:
        response = await client.post(
            "/fetch", json={"urls": ["https://example.com/page"], "topic": "ACA"}
        )

    assert response.status_code == 200
    assert calls == [(["https://example.com/page"], "ACA")]
    assert response.json()["sandbox_statuses"] == [{"status": "success"}]


@pytest.mark.asyncio
async def test_status_reports_only_confirmed_sandbox_instances():
    async def fetcher(*, urls, topic, status_callback):
        await status_callback(
            [{"status": "active", "sandbox_id": "sandbox-confirmed"}]
        )
        return ([], [], [{"status": "success", "sandbox_id": "sandbox-confirmed"}])

    app = create_app(fetcher)
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://broker"
    ) as client:
        response = await client.post(
            "/fetch",
            json={
                "urls": ["https://example.com"],
                "topic": "ACA",
                "request_id": "run-1",
            },
        )
        status = await client.get("/status/run-1")

    assert response.status_code == 200
    assert status.status_code == 200
    assert status.json()["sandbox_statuses"][0]["sandbox_id"] == "sandbox-confirmed"


@pytest.mark.asyncio
async def test_configuration_error_is_explicit():
    async def fetcher(**_):
        raise ValueError("Missing required env vars")

    app = create_app(fetcher)
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://broker"
    ) as client:
        response = await client.post(
            "/fetch", json={"urls": ["https://example.com"], "topic": "ACA"}
        )

    assert response.status_code == 503
    assert response.json()["detail"] == "Missing required env vars"


@pytest.mark.asyncio
async def test_configured_token_is_accepted(monkeypatch):
    monkeypatch.setenv("ACA_SANDBOX_BROKER_TOKEN", "broker-secret")

    async def fetcher(**_):
        return ([], [], [])

    app = create_app(fetcher)
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://broker"
    ) as client:
        response = await client.post(
            "/fetch",
            headers={"x-internal-token": "broker-secret"},
            json={"urls": ["https://example.com"], "topic": "ACA"},
        )

    assert response.status_code == 200


@pytest.mark.asyncio
@pytest.mark.parametrize("supplied_token", [None, "wrong-secret"])
async def test_configured_token_rejects_missing_or_invalid(
    monkeypatch, supplied_token
):
    monkeypatch.setenv("ACA_SANDBOX_BROKER_TOKEN", "broker-secret")
    called = False

    async def fetcher(**_):
        nonlocal called
        called = True
        return ([], [], [])

    app = create_app(fetcher)
    headers = {"x-internal-token": supplied_token} if supplied_token else {}
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://broker"
    ) as client:
        response = await client.post(
            "/fetch",
            headers=headers,
            json={"urls": ["https://example.com"], "topic": "ACA"},
        )

    assert response.status_code == 401
    assert response.json()["detail"] == "Valid internal broker token required"
    assert called is False
