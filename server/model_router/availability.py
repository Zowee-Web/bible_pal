"""Ollama model availability checking.

Queries the local Ollama API to determine which models are installed
and ready for use.
"""

import json
import time
import urllib.request
import urllib.error


class OllamaAvailability:
    """Check which Ollama models are installed and running."""

    def __init__(self, base_url: str = "http://localhost:11434"):
        self.base_url = base_url
        self._cache: list[str] | None = None
        self._cache_time: float = 0
        self._cache_ttl: float = 30.0  # seconds

    def list_models(self) -> list[str]:
        """Return list of installed model names.

        Results are cached for 30 seconds to avoid hammering the API.
        """
        now = time.time()
        if self._cache is not None and (now - self._cache_time) < self._cache_ttl:
            return self._cache

        try:
            req = urllib.request.Request(
                f"{self.base_url}/api/tags",
                method="GET",
            )
            with urllib.request.urlopen(req, timeout=5) as resp:
                data = json.loads(resp.read().decode())
                models = [m["name"] for m in data.get("models", [])]
                self._cache = models
                self._cache_time = now
                return models
        except (urllib.error.URLError, json.JSONDecodeError, KeyError, OSError):
            self._cache = []
            self._cache_time = now
            return []

    def is_available(self, model_name: str) -> bool:
        """Check if a model is installed.

        Uses startswith matching to handle tag suffixes
        (e.g., 'mistral-nemo' matches 'mistral-nemo:latest').
        """
        models = self.list_models()
        for m in models:
            # Match by base name (before colon) or exact match
            base = m.split(":")[0]
            if base == model_name or m == model_name:
                return True
        return False

    def is_server_running(self) -> bool:
        """Quick connectivity check to Ollama server."""
        try:
            req = urllib.request.Request(
                f"{self.base_url}/api/tags",
                method="GET",
            )
            with urllib.request.urlopen(req, timeout=3) as resp:
                return resp.status == 200
        except (urllib.error.URLError, OSError):
            return False

    def invalidate_cache(self) -> None:
        """Force next list_models() call to re-query the API."""
        self._cache = None
        self._cache_time = 0
