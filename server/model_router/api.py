"""FastAPI server for the Universal Model Router.

Internal API gateway for task-driven AI model resolution and generation.
Runs on port 8181 (separate from TTS proxy on 8080).

Start:
    cd /Volumes/T9-AI/bible_pal
    uvicorn server.model_router.api:app --host 127.0.0.1 --port 8181

Endpoints:
    GET   /health              - System status + Ollama connectivity
    GET   /models              - All models with availability
    GET   /tasks               - All task types
    GET   /resolve/{task}      - Resolve task to model (JSON)
    POST  /generate            - Resolve + execute generation

Auth:
    Set MODEL_ROUTER_API_KEY env var to enable API key auth.
    Localhost (127.0.0.1, ::1) bypasses auth.
    If not set, auth is disabled (dev mode).

Response format:
    All endpoints return {"ok": true/false, ...} envelopes.
    Pydantic validation errors return standard 422 responses.
"""

import os

try:
    from fastapi import FastAPI, Request
    from fastapi.responses import JSONResponse
    from pydantic import BaseModel, Field
except ImportError:
    import sys
    print(
        "FastAPI not installed. Run: pip3 install fastapi uvicorn",
        file=sys.stderr,
    )
    raise

from .router import ModelRouter, RoutingError
from .providers import get_provider, ProviderError
from . import telemetry

# ---------------------------------------------------------------------------
# Input validation limits
# ---------------------------------------------------------------------------
MAX_PROMPT_LENGTH = 32_000
MAX_SYSTEM_PROMPT_LENGTH = 8_000
MAX_TOKENS_LIMIT = 4_096

# ---------------------------------------------------------------------------
# Auth configuration
# ---------------------------------------------------------------------------
_API_KEY = os.environ.get("MODEL_ROUTER_API_KEY", "")

# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------
app = FastAPI(
    title="Bible PAL Model Router",
    description="Internal AI model routing and generation gateway",
    version="2.0.0",
)

_router = ModelRouter()
app.state.router = _router


# ---------------------------------------------------------------------------
# Auth middleware
# ---------------------------------------------------------------------------
@app.middleware("http")
async def auth_middleware(request: Request, call_next):
    """API key auth with strict localhost bypass.

    - If MODEL_ROUTER_API_KEY is not set, all requests pass (dev mode).
    - If set, only 127.0.0.1 and ::1 bypass auth (via request.client.host).
    - All other requests require Authorization: Bearer <key> header.
    - Does NOT trust X-Forwarded-For or any forwarded headers.
    """
    if _API_KEY:
        client_host = request.client.host if request.client else ""
        is_localhost = client_host in ("127.0.0.1", "::1")

        if not is_localhost:
            auth_header = request.headers.get("authorization", "")
            if auth_header != f"Bearer {_API_KEY}":
                return JSONResponse(
                    status_code=401,
                    content={
                        "ok": False,
                        "error": {
                            "code": "unauthorized",
                            "message": "Invalid or missing API key",
                        },
                    },
                )

    return await call_next(request)


# ---------------------------------------------------------------------------
# Request model
# ---------------------------------------------------------------------------
class GenerateRequest(BaseModel):
    """Request body for POST /generate."""

    task: str = Field(..., description="Task name (e.g., creative_story)")
    prompt: str = Field(
        ..., min_length=1, max_length=MAX_PROMPT_LENGTH,
        description="Prompt text for generation",
    )
    system_prompt: str | None = Field(
        None, max_length=MAX_SYSTEM_PROMPT_LENGTH,
        description="Optional system prompt",
    )
    temperature: float | None = Field(
        None, ge=0.0, le=2.0,
        description="Sampling temperature (defaults to task default)",
    )
    max_tokens: int | None = Field(
        None, ge=1, le=MAX_TOKENS_LIMIT,
        description="Max output tokens",
    )


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------
@app.get("/health")
async def health():
    """System health check including Ollama connectivity."""
    status = _router.check_availability()
    return JSONResponse(content={"ok": True, "data": status})


@app.get("/models")
async def list_models():
    """List all registered models with availability status."""
    return JSONResponse(
        content={"ok": True, "data": {"models": _router.list_models()}}
    )


@app.get("/tasks")
async def list_tasks():
    """List all defined task types."""
    return JSONResponse(
        content={"ok": True, "data": {"tasks": _router.list_tasks()}}
    )


@app.get("/resolve/{task}")
async def resolve_model(task: str):
    """Resolve a task to the best available model.

    Returns the selected model, provider, fallback info, and reason.
    """
    try:
        route = _router.resolve(task)
        return JSONResponse(
            content={"ok": True, "data": route.to_dict()}
        )
    except RoutingError as e:
        return JSONResponse(
            status_code=404,
            content={
                "ok": False,
                "error": {"code": "unknown_task", "message": str(e)},
            },
        )


@app.post("/generate")
async def generate(request: GenerateRequest):
    """Route a task and generate text via the resolved provider.

    1. Resolves task -> model via the router
    2. Calls the appropriate provider (Ollama or OpenAI)
    3. Returns generated text with routing metadata

    Provider error mapping:
        - Unknown task / routing fails:           404  routing_failed
        - Provider name not recognized:           500  provider_unavailable
        - Provider upstream returned 5xx:          502  generation_failed
        - Provider unreachable (timeout/refused):  503  generation_failed
        - Provider returned 4xx:                   502  generation_failed
    """
    # 1. Resolve task to model
    try:
        route = _router.resolve(request.task)
    except RoutingError as e:
        return JSONResponse(
            status_code=404,
            content={
                "ok": False,
                "error": {"code": "routing_failed", "message": str(e)},
            },
        )

    # 2. Get provider
    try:
        provider = get_provider(route.provider)
    except ValueError as e:
        return JSONResponse(
            status_code=500,
            content={
                "ok": False,
                "error": {
                    "code": "provider_unavailable",
                    "message": str(e),
                },
            },
        )

    # 3. Generate
    temp = (
        request.temperature
        if request.temperature is not None
        else route.default_temperature
    )

    try:
        result = provider.generate(
            model=route.model,
            prompt=request.prompt,
            temperature=temp,
            max_tokens=request.max_tokens,
            system_prompt=request.system_prompt,
        )
    except ProviderError as e:
        # 502 if upstream returned an HTTP error, 503 if unreachable
        if e.status_code is not None:
            status = 502
        else:
            status = 503
        return JSONResponse(
            status_code=status,
            content={
                "ok": False,
                "error": {
                    "code": "generation_failed",
                    "message": str(e),
                    "provider": e.provider,
                },
            },
        )

    # 4. Log (no prompt content)
    telemetry.log_generation(
        task=request.task,
        model=route.model,
        provider=route.provider,
        duration_ms=result.duration_ms,
        prompt_tokens=result.usage.get("prompt_tokens", 0),
        completion_tokens=result.usage.get("completion_tokens", 0),
    )

    # 5. Return result
    return JSONResponse(content={
        "ok": True,
        "data": {
            "text": result.text,
            "route": {
                "model": route.model,
                "provider": route.provider,
                "task": route.task,
                "is_fallback": route.is_fallback,
                "fallback_depth": route.fallback_depth,
                "locked": route.locked,
            },
            "usage": result.usage,
            "duration_ms": round(result.duration_ms, 1),
        },
    })


# ---------------------------------------------------------------------------
# Dashboard (dev tooling)
# ---------------------------------------------------------------------------
from server.dashboard.routes import router as dashboard_router  # noqa: E402

app.include_router(dashboard_router)
