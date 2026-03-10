"""FastAPI prototype for the Universal Model Router.

Local-only API server for future Bible PAL app integration.
Runs on port 8181 (separate from TTS proxy on 8080).

Start:
    cd /Volumes/T9-AI/bible_pal
    uvicorn server.model_router.api:app --host 127.0.0.1 --port 8181

Endpoints:
    GET  /health              - System status + Ollama connectivity
    GET  /models              - All models with availability
    GET  /tasks               - All task types
    GET  /resolve/{task}      - Resolve task to model (JSON)
"""

try:
    from fastapi import FastAPI, HTTPException
    from fastapi.responses import JSONResponse
except ImportError:
    import sys
    print(
        "FastAPI not installed. Run: pip3 install fastapi uvicorn",
        file=sys.stderr,
    )
    raise

from .router import ModelRouter, RoutingError

app = FastAPI(
    title="Bible PAL Model Router",
    description="Local-only AI model routing prototype",
    version="1.0.0",
)

_router = ModelRouter()


@app.get("/health")
async def health():
    """System health check including Ollama connectivity."""
    status = _router.check_availability()
    return JSONResponse(content=status)


@app.get("/models")
async def list_models():
    """List all registered models with availability status."""
    return JSONResponse(content={"models": _router.list_models()})


@app.get("/tasks")
async def list_tasks():
    """List all defined task types."""
    return JSONResponse(content={"tasks": _router.list_tasks()})


@app.get("/resolve/{task}")
async def resolve_model(task: str):
    """Resolve a task to the best available model.

    Returns the selected model, provider, fallback info, and reason.
    """
    try:
        route = _router.resolve(task)
        return JSONResponse(content=route.to_dict())
    except RoutingError as e:
        raise HTTPException(status_code=404, detail=str(e))
