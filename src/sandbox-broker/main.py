"""Internal API adapter for the existing ACA Sandbox fetch implementation."""

from __future__ import annotations

import os
import secrets
from collections.abc import Awaitable, Callable
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from pydantic import BaseModel, Field, HttpUrl
from tools.sandbox_fetch import fetch_with_sandboxes_direct, wait_for_sandbox_cleanup


class FetchRequest(BaseModel):
    urls: list[HttpUrl] = Field(min_length=1, max_length=50)
    topic: str = Field(min_length=1, max_length=1000)
    request_id: str | None = Field(default=None, min_length=1, max_length=200)


class FetchResponse(BaseModel):
    fetched_content: list[dict]
    egress_violations: list[dict]
    sandbox_statuses: list[dict]


Fetcher = Callable[..., Awaitable[tuple[list[dict], list[dict], list[dict]]]]


def create_app(fetcher: Fetcher = fetch_with_sandboxes_direct) -> FastAPI:
    @asynccontextmanager
    async def lifespan(_: FastAPI):
        yield
        await wait_for_sandbox_cleanup()

    app = FastAPI(title="ACA Sandbox Broker", lifespan=lifespan)
    app.state.fetcher = fetcher
    app.state.internal_token = os.getenv("ACA_SANDBOX_BROKER_TOKEN", "")
    app.state.fetch_statuses = {}

    def require_internal_token(request: Request) -> None:
        configured_token = request.app.state.internal_token
        supplied_token = request.headers.get("x-internal-token", "")
        if configured_token and not secrets.compare_digest(
            supplied_token.encode("utf-8"), configured_token.encode("utf-8")
        ):
            raise HTTPException(
                status_code=401, detail="Valid internal broker token required"
            )

    @app.get("/health")
    async def health() -> dict[str, str]:
        return {
            "status": "healthy",
            "service": os.getenv("OTEL_SERVICE_NAME", "aca-sandbox-broker"),
        }

    @app.post("/fetch", response_model=FetchResponse)
    async def fetch(payload: FetchRequest, request: Request) -> FetchResponse:
        require_internal_token(request)
        request_id = payload.request_id
        if request_id:
            request.app.state.fetch_statuses[request_id] = {
                "phase": "creating_sandboxes",
                "sandbox_statuses": [],
                "egress_violations": [],
            }

        async def update_status(statuses: list[dict]) -> None:
            if request_id:
                request.app.state.fetch_statuses[request_id] = {
                    "phase": "running_sandboxes",
                    "sandbox_statuses": [dict(status) for status in statuses],
                    "egress_violations": [],
                }

        try:
            fetched, violations, statuses = await request.app.state.fetcher(
                urls=[str(url) for url in payload.urls],
                topic=payload.topic,
                status_callback=update_status,
            )
        except ValueError as exc:
            if request_id:
                request.app.state.fetch_statuses[request_id] = {
                    "phase": "failed",
                    "sandbox_statuses": [],
                    "egress_violations": [],
                    "error": str(exc),
                }
            raise HTTPException(status_code=503, detail=str(exc)) from exc
        except Exception as exc:
            if request_id:
                request.app.state.fetch_statuses[request_id] = {
                    "phase": "failed",
                    "sandbox_statuses": [],
                    "egress_violations": [],
                    "error": str(exc),
                }
            raise HTTPException(
                status_code=502, detail=f"Sandbox execution failed: {exc}"
            ) from exc
        if request_id:
            request.app.state.fetch_statuses[request_id] = {
                "phase": "sandboxes_complete",
                "sandbox_statuses": statuses,
                "egress_violations": violations,
            }
        return FetchResponse(
            fetched_content=fetched,
            egress_violations=violations,
            sandbox_statuses=statuses,
        )

    @app.get("/status/{request_id}")
    async def fetch_status(request_id: str, request: Request) -> dict:
        require_internal_token(request)
        status = request.app.state.fetch_statuses.get(request_id)
        if status is None:
            raise HTTPException(status_code=404, detail="Sandbox request not found")
        return status

    FastAPIInstrumentor.instrument_app(app)
    return app


provider = TracerProvider(
    resource=Resource.create(
        {"service.name": os.getenv("OTEL_SERVICE_NAME", "aca-sandbox-broker")}
    )
)
provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
try:
    trace.set_tracer_provider(provider)
except Exception:
    provider.shutdown()

app = create_app()
