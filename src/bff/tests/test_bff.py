import httpx
import pytest
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from main import create_app


@pytest.fixture(autouse=True)
def clear_auth_requirement(monkeypatch):
    monkeypatch.delenv("AUTH_REQUIRED", raising=False)


@pytest.fixture
def downstream():
    app = FastAPI()

    @app.get("/health")
    async def health():
        return {"status": "healthy", "agent": "research-agent"}

    @app.post("/a2a")
    async def a2a(request: Request):
        return JSONResponse(
            {
                "authorization": request.headers.get("authorization"),
                "body": await request.json(),
            }
        )

    return app


@pytest.mark.asyncio
async def test_proxy_uses_server_token_and_ignores_browser_token(monkeypatch, downstream):
    monkeypatch.setenv("RESEARCH_AGENT_URL", "http://research")
    monkeypatch.setenv("A2A_AUTH_TOKEN", "server-secret")
    app = create_app()
    app.state.http_transport = httpx.ASGITransport(app=downstream)

    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://bff"
    ) as client:
        response = await client.post(
            "/api/agents/research/a2a",
            headers={"authorization": "Bearer browser-secret"},
            json={"topic": "ACA"},
        )

    assert response.status_code == 200
    assert response.json() == {
        "authorization": "Bearer server-secret",
        "body": {"topic": "ACA"},
    }


@pytest.mark.asyncio
async def test_unknown_agent_is_explicit():
    app = create_app()
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://bff"
    ) as client:
        response = await client.get("/api/agents/not-real/health")

    assert response.status_code == 404
    assert response.json()["detail"] == "Unknown agent 'not-real'"


@pytest.mark.asyncio
async def test_auth_required_rejects_request_without_oauth_identity(monkeypatch):
    monkeypatch.setenv("AUTH_REQUIRED", "true")
    app = create_app()
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://bff"
    ) as client:
        response = await client.get("/api/agents/research/health")

    assert response.status_code == 401
    assert response.json()["detail"] == "Authenticated oauth2-proxy identity required"


@pytest.mark.asyncio
async def test_auth_required_accepts_trusted_oauth_identity(monkeypatch, downstream):
    monkeypatch.setenv("AUTH_REQUIRED", "true")
    monkeypatch.setenv("RESEARCH_AGENT_URL", "http://research")
    app = create_app()
    app.state.http_transport = httpx.ASGITransport(app=downstream)
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://bff"
    ) as client:
        response = await client.get(
            "/api/agents/research/health",
            headers={"x-auth-request-email": "developer@example.com"},
        )

    assert response.status_code == 200
    assert response.json()["status"] == "healthy"


@pytest.mark.asyncio
async def test_auth_required_accepts_oauth_proxy_forwarded_identity(
    monkeypatch, downstream
):
    monkeypatch.setenv("AUTH_REQUIRED", "true")
    monkeypatch.setenv("RESEARCH_AGENT_URL", "http://research")
    app = create_app()
    app.state.http_transport = httpx.ASGITransport(app=downstream)
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://bff"
    ) as client:
        response = await client.get(
            "/api/agents/research/health",
            headers={"x-forwarded-email": "developer@example.com"},
        )

    assert response.status_code == 200
    assert response.json()["status"] == "healthy"


@pytest.mark.asyncio
async def test_current_user_returns_authenticated_identity(monkeypatch):
    monkeypatch.setenv("AUTH_REQUIRED", "true")
    app = create_app()
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://bff"
    ) as client:
        response = await client.get(
            "/api/me",
            headers={
                "x-auth-request-user": "user-object-id",
                "x-auth-request-email": "developer@example.com",
            },
        )

    assert response.status_code == 200
    assert response.json() == {
        "user": "user-object-id",
        "email": "developer@example.com",
        "display_name": "developer@example.com",
    }


@pytest.mark.asyncio
async def test_current_user_requires_authenticated_identity(monkeypatch):
    monkeypatch.setenv("AUTH_REQUIRED", "true")
    app = create_app()
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://bff"
    ) as client:
        response = await client.get("/api/me")

    assert response.status_code == 401


@pytest.mark.asyncio
async def test_health_stays_public_when_auth_required(monkeypatch):
    monkeypatch.setenv("AUTH_REQUIRED", "true")
    app = create_app()
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://bff"
    ) as client:
        response = await client.get("/health")

    assert response.status_code == 200
    assert response.json()["status"] == "healthy"


@pytest.mark.asyncio
async def test_local_auth_disabled_remains_compatible(monkeypatch):
    monkeypatch.setenv("AUTH_REQUIRED", "false")
    app = create_app()
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://bff"
    ) as client:
        response = await client.get("/api/agents/not-real/health")

    assert response.status_code == 404
