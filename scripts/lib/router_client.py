"""Tiny Python client for the Model Router POST /generate endpoint.

Usage:
    from router_client import router_generate, RouterError

    text = router_generate(
        task="creative_story",
        prompt="Write a parable...",
        system_prompt="You are a storyteller",
        temperature=0.7,
        max_tokens=200,
    )

Override endpoint via environment variable:
    MODEL_ROUTER_URL=http://localhost:8181/generate
"""

import json
import os
import urllib.error
import urllib.request


class RouterError(Exception):
    """Raised when the Model Router returns an error or is unreachable."""

    def __init__(self, message: str, code: str = "unknown"):
        self.code = code
        super().__init__(message)


def router_generate(
    task: str,
    prompt: str,
    system_prompt: str | None = None,
    temperature: float | None = None,
    max_tokens: int | None = None,
    timeout: int = 60,
) -> str:
    """Call POST /generate and return generated text.

    Raises RouterError on failure.
    """
    url = os.environ.get("MODEL_ROUTER_URL", "http://127.0.0.1:8181/generate")

    body: dict = {"task": task, "prompt": prompt}
    if system_prompt is not None:
        body["system_prompt"] = system_prompt
    if temperature is not None:
        body["temperature"] = temperature
    if max_tokens is not None:
        body["max_tokens"] = max_tokens

    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )

    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.loads(resp.read())
    except urllib.error.HTTPError as exc:
        # HTTPError before URLError (HTTPError is a subclass of URLError)
        try:
            err_data = json.loads(exc.read())
            code = err_data.get("error", {}).get("code", "unknown")
            msg = err_data.get("error", {}).get("message", str(exc))
            raise RouterError(f"{msg}", code=code) from exc
        except (json.JSONDecodeError, AttributeError):
            raise RouterError(f"HTTP {exc.code}: {exc.reason}", code="http_error") from exc
    except (urllib.error.URLError, OSError, TimeoutError) as exc:
        raise RouterError(f"Model Router API unreachable at {url}: {exc}") from exc

    if not data.get("ok"):
        code = data.get("error", {}).get("code", "unknown")
        msg = data.get("error", {}).get("message", "unknown error")
        raise RouterError(f"{msg}", code=code)

    # Log route diagnostic to stderr (matches bash helper convention)
    route = data.get("data", {}).get("route", {})
    if route:
        model = route.get("model", "unknown")
        provider = route.get("provider", "unknown")
        fallback = "yes" if route.get("is_fallback") else "no"
        import sys
        print(
            f"[router] {task} -> {model} (provider={provider}, fallback={fallback})",
            file=sys.stderr,
        )

    return data.get("data", {}).get("text", "")
