"""Privacy-safe telemetry for model routing decisions.

Logs structured JSON to stderr. Never logs prompt content,
user text, API keys, or PII.
"""

import json
import sys
import time
from datetime import datetime, timezone


def log_resolution(
    task: str,
    model: str,
    provider: str,
    is_fallback: bool,
    fallback_depth: int,
    reason: str,
    duration_ms: float | None = None,
) -> None:
    """Log a model resolution event to stderr."""
    event = {
        "event": "model_route_resolved",
        "ts": datetime.now(timezone.utc).isoformat(),
        "task": task,
        "model": model,
        "provider": provider,
        "is_fallback": is_fallback,
        "fallback_depth": fallback_depth,
        "reason": reason,
    }
    if duration_ms is not None:
        event["duration_ms"] = round(duration_ms, 1)
    _emit(event)


def log_generation(
    task: str,
    model: str,
    provider: str,
    duration_ms: float,
    prompt_tokens: int = 0,
    completion_tokens: int = 0,
) -> None:
    """Log a generation completion event to stderr.

    Never logs prompt content, system prompts, user text, or API keys.
    """
    event = {
        "event": "model_generation_completed",
        "ts": datetime.now(timezone.utc).isoformat(),
        "task": task,
        "model": model,
        "provider": provider,
        "duration_ms": round(duration_ms, 1),
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
    }
    _emit(event)


def log_error(task: str, error: str) -> None:
    """Log a routing error to stderr."""
    event = {
        "event": "model_route_failed",
        "ts": datetime.now(timezone.utc).isoformat(),
        "task": task,
        "error": error,
    }
    _emit(event)


def _emit(event: dict) -> None:
    """Write a single JSON log line to stderr."""
    try:
        print(json.dumps(event, separators=(",", ":")), file=sys.stderr)
    except Exception:
        pass  # Telemetry must never crash the application
