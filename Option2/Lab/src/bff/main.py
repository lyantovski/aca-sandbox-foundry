"""Browser-facing proxy for the Content Factory agents."""

from __future__ import annotations

import os

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, Response
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor


def _configure_telemetry() -> None:
    provider = TracerProvider(
        resource=Resource.create(
            {"service.name": os.getenv("OTEL_SERVICE_NAME", "content-factory-bff")}
        )
    )
    provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
    try:
        trace.set_tracer_provider(provider)
    except Exception:
        provider.shutdown()
    HTTPXClientInstrumentor().instrument()


def create_app() -> FastAPI:
    app = FastAPI(title="Content Factory BFF")
    app.state.auth_required = os.getenv("AUTH_REQUIRED", "false").strip().lower() in {
        "1",
        "true",
        "yes",
        "on",
    }
    app.state.agent_urls = {
        "research": os.getenv("RESEARCH_AGENT_URL", "http://agent-research:8001"),
        "creator": os.getenv("CREATOR_AGENT_URL", "http://agent-creator:8002"),
        "podcaster": os.getenv("PODCASTER_AGENT_URL", "http://agent-podcaster:8003"),
    }
    shared_token = os.getenv("A2A_AUTH_TOKEN", "")
    app.state.agent_tokens = {
        name: os.getenv(f"{name.upper()}_AGENT_TOKEN", shared_token)
        for name in app.state.agent_urls
    }
    app.state.http_transport = None

    @app.middleware("http")
    async def require_oauth_identity(request: Request, call_next):
        if request.url.path != "/health" and app.state.auth_required:
            user = request.headers.get("x-auth-request-user", "").strip()
            email = request.headers.get("x-auth-request-email", "").strip()
            if not user and not email:
                return JSONResponse(
                    status_code=401,
                    content={"detail": "Authenticated oauth2-proxy identity required"},
                )
        return await call_next(request)

    @app.get("/health")
    async def health() -> dict[str, str]:
        return {
            "status": "healthy",
            "service": os.getenv("OTEL_SERVICE_NAME", "content-factory-bff"),
        }

    @app.api_route(
        "/api/agents/{agent}/{path:path}",
        methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    )
    async def proxy_agent(agent: str, path: str, request: Request) -> Response:
        base_url = app.state.agent_urls.get(agent)
        if base_url is None:
            raise HTTPException(status_code=404, detail=f"Unknown agent '{agent}'")

        headers: dict[str, str] = {}
        for name in ("accept", "content-type", "traceparent", "tracestate", "baggage"):
            if value := request.headers.get(name):
                headers[name] = value
        if token := app.state.agent_tokens.get(agent):
            headers["authorization"] = f"Bearer {token}"

        target = f"{base_url.rstrip('/')}/{path}"
        try:
            async with httpx.AsyncClient(
                transport=app.state.http_transport,
                timeout=httpx.Timeout(600.0, connect=10.0),
                follow_redirects=False,
            ) as client:
                downstream = await client.request(
                    request.method,
                    target,
                    params=request.query_params,
                    content=await request.body(),
                    headers=headers,
                )
        except httpx.TimeoutException as exc:
            raise HTTPException(
                status_code=504, detail=f"{agent} agent request timed out"
            ) from exc
        except httpx.RequestError as exc:
            raise HTTPException(
                status_code=502, detail=f"{agent} agent is unavailable"
            ) from exc

        response_headers = {}
        if content_type := downstream.headers.get("content-type"):
            response_headers["content-type"] = content_type
        if location := downstream.headers.get("location"):
            response_headers["location"] = location.replace(
                base_url.rstrip("/"), f"/api/agents/{agent}"
            )
        return Response(
            content=downstream.content,
            status_code=downstream.status_code,
            headers=response_headers,
        )

    FastAPIInstrumentor.instrument_app(app)
    return app


_configure_telemetry()
app = create_app()
