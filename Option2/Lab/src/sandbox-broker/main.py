"""Internal API adapter for the existing ACA Sandbox fetch implementation."""

from __future__ import annotations

import os
import secrets
from collections.abc import Awaitable, Callable

from fastapi import FastAPI, HTTPException, Request
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from pydantic import BaseModel, Field, HttpUrl
from tools.sandbox_fetch import fetch_with_sandboxes_direct


class FetchRequest(BaseModel):
    urls: list[HttpUrl] = Field(min_length=1, max_length=50)
    topic: str = Field(min_length=1, max_length=1000)


class FetchResponse(BaseModel):
    fetched_content: list[dict]
    egress_violations: list[dict]
    sandbox_statuses: list[dict]


Fetcher = Callable[..., Awaitable[tuple[list[dict], list[dict], list[dict]]]]


def create_app(fetcher: Fetcher = fetch_with_sandboxes_direct) -> FastAPI:
    app = FastAPI(title="ACA Sandbox Broker")
    app.state.fetcher = fetcher
    app.state.internal_token = os.getenv("ACA_SANDBOX_BROKER_TOKEN", "")

    @app.get("/health")
    async def health() -> dict[str, str]:
        return {
            "status": "healthy",
            "service": os.getenv("OTEL_SERVICE_NAME", "aca-sandbox-broker"),
        }

    @app.post("/fetch", response_model=FetchResponse)
    async def fetch(payload: FetchRequest, request: Request) -> FetchResponse:
        configured_token = request.app.state.internal_token
        supplied_token = request.headers.get("x-internal-token", "")
        if configured_token and not secrets.compare_digest(
            supplied_token.encode("utf-8"), configured_token.encode("utf-8")
        ):
            raise HTTPException(
                status_code=401, detail="Valid internal broker token required"
            )
        try:
            fetched, violations, statuses = await request.app.state.fetcher(
                urls=[str(url) for url in payload.urls],
                topic=payload.topic,
            )
        except ValueError as exc:
            raise HTTPException(status_code=503, detail=str(exc)) from exc
        except Exception as exc:
            raise HTTPException(
                status_code=502, detail=f"Sandbox execution failed: {exc}"
            ) from exc
        return FetchResponse(
            fetched_content=fetched,
            egress_violations=violations,
            sandbox_statuses=statuses,
        )

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
