"""AI model provider abstraction layer.

Thin transport adapters for Ollama and OpenAI. Each provider handles
only HTTP transport and response parsing — no business logic, no
prompt construction, no model selection.

Uses stdlib urllib only (consistent with availability.py).
"""

import json
import os
import time
import urllib.request
import urllib.error
from abc import ABC, abstractmethod
from dataclasses import dataclass, asdict


@dataclass
class GenerationResult:
    """Result of a model generation call."""

    text: str
    model: str
    provider: str
    usage: dict  # {"prompt_tokens": N, "completion_tokens": N}
    duration_ms: float

    def to_dict(self) -> dict:
        return asdict(self)


class ProviderError(Exception):
    """Raised when a provider call fails."""

    def __init__(
        self,
        message: str,
        provider: str,
        status_code: int | None = None,
    ):
        super().__init__(message)
        self.provider = provider
        self.status_code = status_code


class BaseProvider(ABC):
    """Abstract base for AI model providers.

    Providers are thin transport adapters. They call an inference
    endpoint and parse the response. They do not select models,
    construct prompts, or embed application logic.
    """

    @abstractmethod
    def generate(
        self,
        model: str,
        prompt: str,
        temperature: float = 0.7,
        max_tokens: int | None = None,
        system_prompt: str | None = None,
    ) -> GenerationResult:
        """Generate text from the model. Synchronous, blocking."""
        ...

    @abstractmethod
    def name(self) -> str:
        """Provider identifier string."""
        ...


class OllamaProvider(BaseProvider):
    """Provider for local Ollama models via /api/generate."""

    def __init__(
        self,
        base_url: str = "http://localhost:11434",
        timeout: int = 120,
    ):
        self._base_url = base_url
        self._timeout = timeout

    def name(self) -> str:
        return "ollama"

    def generate(
        self,
        model: str,
        prompt: str,
        temperature: float = 0.7,
        max_tokens: int | None = None,
        system_prompt: str | None = None,
    ) -> GenerationResult:
        """Call Ollama /api/generate endpoint (non-streaming)."""
        body: dict = {
            "model": model,
            "prompt": prompt,
            "stream": False,
            "options": {"temperature": temperature},
        }
        if system_prompt:
            body["system"] = system_prompt
        if max_tokens is not None:
            body["options"]["num_predict"] = max_tokens

        data = json.dumps(body).encode("utf-8")
        req = urllib.request.Request(
            f"{self._base_url}/api/generate",
            data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )

        start = time.time()
        try:
            with urllib.request.urlopen(req, timeout=self._timeout) as resp:
                result = json.loads(resp.read().decode())
        except urllib.error.HTTPError as e:
            raise ProviderError(
                f"Ollama returned HTTP {e.code}: {e.read().decode()[:200]}",
                provider="ollama",
                status_code=e.code,
            )
        except (urllib.error.URLError, OSError) as e:
            raise ProviderError(
                f"Cannot reach Ollama at {self._base_url}: {e}",
                provider="ollama",
            )

        elapsed = (time.time() - start) * 1000

        return GenerationResult(
            text=result.get("response", ""),
            model=model,
            provider="ollama",
            usage={
                "prompt_tokens": result.get("prompt_eval_count", 0),
                "completion_tokens": result.get("eval_count", 0),
            },
            duration_ms=elapsed,
        )


class OpenAIProvider(BaseProvider):
    """Provider for OpenAI models via /v1/chat/completions.

    Uses the chat completions endpoint intentionally — this is the
    standard OpenAI interface for text generation in this phase.
    """

    def __init__(
        self,
        api_key: str | None = None,
        timeout: int = 180,
    ):
        self._api_key = api_key or os.environ.get("OPENAI_API_KEY", "")
        self._base_url = "https://api.openai.com"
        self._timeout = timeout

    def name(self) -> str:
        return "openai"

    def generate(
        self,
        model: str,
        prompt: str,
        temperature: float = 0.7,
        max_tokens: int | None = None,
        system_prompt: str | None = None,
    ) -> GenerationResult:
        """Call OpenAI /v1/chat/completions (non-streaming)."""
        if not self._api_key:
            raise ProviderError(
                "OPENAI_API_KEY not set. Required for OpenAI provider.",
                provider="openai",
            )

        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": prompt})

        body: dict = {
            "model": model,
            "messages": messages,
            "temperature": temperature,
            "stream": False,
        }
        if max_tokens is not None:
            body["max_tokens"] = max_tokens

        data = json.dumps(body).encode("utf-8")
        req = urllib.request.Request(
            f"{self._base_url}/v1/chat/completions",
            data=data,
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {self._api_key}",
            },
            method="POST",
        )

        start = time.time()
        try:
            with urllib.request.urlopen(req, timeout=self._timeout) as resp:
                result = json.loads(resp.read().decode())
        except urllib.error.HTTPError as e:
            raise ProviderError(
                f"OpenAI returned HTTP {e.code}: {e.read().decode()[:200]}",
                provider="openai",
                status_code=e.code,
            )
        except (urllib.error.URLError, OSError) as e:
            raise ProviderError(
                f"Cannot reach OpenAI API: {e}",
                provider="openai",
            )

        elapsed = (time.time() - start) * 1000
        choice = result.get("choices", [{}])[0]
        usage_data = result.get("usage", {})

        return GenerationResult(
            text=choice.get("message", {}).get("content", ""),
            model=model,
            provider="openai",
            usage={
                "prompt_tokens": usage_data.get("prompt_tokens", 0),
                "completion_tokens": usage_data.get("completion_tokens", 0),
            },
            duration_ms=elapsed,
        )


def get_provider(provider_name: str, **kwargs) -> BaseProvider:
    """Factory function to get a provider by name.

    Args:
        provider_name: "ollama" or "openai"
        **kwargs: Passed to provider constructor

    Returns:
        BaseProvider instance

    Raises:
        ValueError: Unknown provider name
    """
    providers = {
        "ollama": OllamaProvider,
        "openai": OpenAIProvider,
    }
    cls = providers.get(provider_name)
    if cls is None:
        raise ValueError(
            f"Unknown provider: '{provider_name}'. "
            f"Available: {list(providers.keys())}"
        )
    return cls(**kwargs)
