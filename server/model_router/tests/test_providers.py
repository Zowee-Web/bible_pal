"""Tests for the provider abstraction layer."""

import io
import json
import os
import sys
import urllib.error
from unittest.mock import patch, MagicMock

import pytest

from server.model_router.providers import (
    BaseProvider,
    GenerationResult,
    OllamaProvider,
    OpenAIProvider,
    ProviderError,
    get_provider,
)


# ---------------------------------------------------------------------------
# BaseProvider
# ---------------------------------------------------------------------------


class TestBaseProvider:
    def test_cannot_instantiate_directly(self):
        """BaseProvider is abstract and cannot be instantiated."""
        with pytest.raises(TypeError):
            BaseProvider()


# ---------------------------------------------------------------------------
# get_provider factory
# ---------------------------------------------------------------------------


class TestGetProvider:
    def test_returns_ollama_provider(self):
        provider = get_provider("ollama")
        assert isinstance(provider, OllamaProvider)
        assert provider.name() == "ollama"

    def test_returns_openai_provider(self):
        provider = get_provider("openai")
        assert isinstance(provider, OpenAIProvider)
        assert provider.name() == "openai"

    def test_unknown_provider_raises(self):
        with pytest.raises(ValueError, match="Unknown provider"):
            get_provider("anthropic")

    def test_passes_kwargs_to_ollama(self):
        provider = get_provider("ollama", base_url="http://custom:11434")
        assert provider._base_url == "http://custom:11434"

    def test_passes_kwargs_to_openai(self):
        provider = get_provider("openai", api_key="sk-test")
        assert provider._api_key == "sk-test"


# ---------------------------------------------------------------------------
# Helper: mock urllib response
# ---------------------------------------------------------------------------


def _mock_response(body: dict) -> MagicMock:
    """Create a mock urllib response with JSON body."""
    mock = MagicMock()
    mock.read.return_value = json.dumps(body).encode()
    mock.status = 200
    mock.__enter__ = lambda s: s
    mock.__exit__ = MagicMock(return_value=False)
    return mock


# ---------------------------------------------------------------------------
# OllamaProvider
# ---------------------------------------------------------------------------


class TestOllamaProvider:
    def test_generate_success(self):
        provider = OllamaProvider()
        mock_resp = _mock_response({
            "response": "Once upon a time...",
            "prompt_eval_count": 10,
            "eval_count": 50,
        })

        with patch("urllib.request.urlopen", return_value=mock_resp):
            result = provider.generate(
                model="mistral-nemo",
                prompt="Write a story",
                temperature=0.8,
            )

        assert result.text == "Once upon a time..."
        assert result.model == "mistral-nemo"
        assert result.provider == "ollama"
        assert result.usage["prompt_tokens"] == 10
        assert result.usage["completion_tokens"] == 50
        assert result.duration_ms > 0

    def test_generate_connection_error(self):
        provider = OllamaProvider()
        with patch(
            "urllib.request.urlopen",
            side_effect=OSError("Connection refused"),
        ):
            with pytest.raises(ProviderError, match="Cannot reach Ollama"):
                provider.generate(model="mistral-nemo", prompt="test")

    def test_generate_http_error(self):
        provider = OllamaProvider()
        error = urllib.error.HTTPError(
            url="http://localhost:11434/api/generate",
            code=500,
            msg="Internal Server Error",
            hdrs={},
            fp=io.BytesIO(b"Server error"),
        )
        with patch("urllib.request.urlopen", side_effect=error):
            with pytest.raises(ProviderError) as exc_info:
                provider.generate(model="mistral-nemo", prompt="test")
            assert exc_info.value.status_code == 500
            assert exc_info.value.provider == "ollama"

    def test_sends_system_prompt(self):
        """Verify system_prompt is sent as 'system' field in Ollama payload."""
        provider = OllamaProvider()
        mock_resp = _mock_response({"response": "ok"})

        with patch("urllib.request.urlopen", return_value=mock_resp) as mock_url:
            provider.generate(
                model="mistral-nemo",
                prompt="test prompt",
                system_prompt="You are a storyteller",
            )
            req = mock_url.call_args[0][0]
            body = json.loads(req.data)
            assert body["system"] == "You are a storyteller"
            assert body["prompt"] == "test prompt"

    def test_omits_system_when_none(self):
        """Verify system field is absent when system_prompt is None."""
        provider = OllamaProvider()
        mock_resp = _mock_response({"response": "ok"})

        with patch("urllib.request.urlopen", return_value=mock_resp) as mock_url:
            provider.generate(model="test", prompt="test")
            req = mock_url.call_args[0][0]
            body = json.loads(req.data)
            assert "system" not in body

    def test_stream_always_false(self):
        """Ollama requests must always set stream: false."""
        provider = OllamaProvider()
        mock_resp = _mock_response({"response": "ok"})

        with patch("urllib.request.urlopen", return_value=mock_resp) as mock_url:
            provider.generate(model="test", prompt="test")
            req = mock_url.call_args[0][0]
            body = json.loads(req.data)
            assert body["stream"] is False

    def test_sends_max_tokens_as_num_predict(self):
        """Ollama uses num_predict for max token control."""
        provider = OllamaProvider()
        mock_resp = _mock_response({"response": "ok"})

        with patch("urllib.request.urlopen", return_value=mock_resp) as mock_url:
            provider.generate(model="test", prompt="test", max_tokens=512)
            req = mock_url.call_args[0][0]
            body = json.loads(req.data)
            assert body["options"]["num_predict"] == 512


# ---------------------------------------------------------------------------
# OpenAIProvider
# ---------------------------------------------------------------------------


class TestOpenAIProvider:
    def test_generate_success(self):
        provider = OpenAIProvider(api_key="sk-test")
        mock_resp = _mock_response({
            "choices": [{"message": {"content": "A parable..."}}],
            "usage": {"prompt_tokens": 15, "completion_tokens": 100},
        })

        with patch("urllib.request.urlopen", return_value=mock_resp):
            result = provider.generate(
                model="gpt-4.1",
                prompt="Write a Bible retelling",
            )

        assert result.text == "A parable..."
        assert result.model == "gpt-4.1"
        assert result.provider == "openai"
        assert result.usage["prompt_tokens"] == 15
        assert result.usage["completion_tokens"] == 100
        assert result.duration_ms > 0

    def test_missing_api_key_raises(self):
        provider = OpenAIProvider(api_key="")
        with pytest.raises(ProviderError, match="OPENAI_API_KEY not set"):
            provider.generate(model="gpt-4.1", prompt="test")

    def test_sends_system_and_user_messages(self):
        """Verify system + user messages are structured correctly."""
        provider = OpenAIProvider(api_key="sk-test")
        mock_resp = _mock_response({
            "choices": [{"message": {"content": "ok"}}],
            "usage": {},
        })

        with patch("urllib.request.urlopen", return_value=mock_resp) as mock_url:
            provider.generate(
                model="gpt-4.1",
                prompt="user text",
                system_prompt="You are a biblical scholar",
            )
            req = mock_url.call_args[0][0]
            body = json.loads(req.data)
            assert len(body["messages"]) == 2
            assert body["messages"][0] == {
                "role": "system",
                "content": "You are a biblical scholar",
            }
            assert body["messages"][1] == {
                "role": "user",
                "content": "user text",
            }

    def test_omits_system_message_when_none(self):
        """Verify only user message when no system_prompt."""
        provider = OpenAIProvider(api_key="sk-test")
        mock_resp = _mock_response({
            "choices": [{"message": {"content": "ok"}}],
            "usage": {},
        })

        with patch("urllib.request.urlopen", return_value=mock_resp) as mock_url:
            provider.generate(model="gpt-4.1", prompt="test")
            req = mock_url.call_args[0][0]
            body = json.loads(req.data)
            assert len(body["messages"]) == 1
            assert body["messages"][0]["role"] == "user"

    def test_auth_header_included(self):
        provider = OpenAIProvider(api_key="sk-test-key")
        mock_resp = _mock_response({
            "choices": [{"message": {"content": "ok"}}],
            "usage": {},
        })

        with patch("urllib.request.urlopen", return_value=mock_resp) as mock_url:
            provider.generate(model="gpt-4.1", prompt="test")
            req = mock_url.call_args[0][0]
            assert req.get_header("Authorization") == "Bearer sk-test-key"

    def test_stream_always_false(self):
        """OpenAI requests must always set stream: false."""
        provider = OpenAIProvider(api_key="sk-test")
        mock_resp = _mock_response({
            "choices": [{"message": {"content": "ok"}}],
            "usage": {},
        })

        with patch("urllib.request.urlopen", return_value=mock_resp) as mock_url:
            provider.generate(model="gpt-4.1", prompt="test")
            req = mock_url.call_args[0][0]
            body = json.loads(req.data)
            assert body["stream"] is False

    def test_connection_error(self):
        provider = OpenAIProvider(api_key="sk-test")
        with patch(
            "urllib.request.urlopen",
            side_effect=OSError("Network unreachable"),
        ):
            with pytest.raises(ProviderError, match="Cannot reach OpenAI"):
                provider.generate(model="gpt-4.1", prompt="test")


# ---------------------------------------------------------------------------
# Traditional Lock End-to-End
# ---------------------------------------------------------------------------


class TestTraditionalLockEnforcement:
    """Verify the lock is enforced across the router + provider boundary."""

    def test_traditional_always_routes_to_openai(self):
        """Router resolves traditional to gpt-4.1/openai; factory returns OpenAI."""
        from server.model_router.router import ModelRouter

        registry_path = os.path.join(
            os.path.dirname(__file__), "..", "model_registry.json"
        )

        with patch(
            "server.model_router.availability.OllamaAvailability"
        ) as MockAvail:
            instance = MockAvail.return_value
            instance.is_available.return_value = False
            instance.is_server_running.return_value = False
            instance.list_models.return_value = []

            router = ModelRouter(registry_path=registry_path, ollama_url="http://localhost:11434")
            # Override the ollama instance with our mock
            router._ollama = instance

            route = router.resolve("traditional_story_remote")
            assert route.model == "gpt-4.1"
            assert route.provider == "openai"
            assert route.locked is True

            # Provider factory MUST return OpenAIProvider
            provider = get_provider(route.provider)
            assert isinstance(provider, OpenAIProvider)
            assert provider.name() == "openai"


# ---------------------------------------------------------------------------
# Telemetry Privacy
# ---------------------------------------------------------------------------


class TestTelemetryPrivacy:
    """Verify that prompt content is NEVER logged by telemetry."""

    def test_log_generation_never_includes_prompt(self):
        """log_generation must not log prompt text."""
        from server.model_router import telemetry

        captured = io.StringIO()
        with patch("sys.stderr", captured):
            telemetry.log_generation(
                task="creative_story",
                model="mistral-nemo",
                provider="ollama",
                duration_ms=1234.5,
                prompt_tokens=42,
                completion_tokens=100,
            )

        output = captured.getvalue()
        # Should contain metadata fields
        assert "model_generation_completed" in output
        assert "creative_story" in output
        assert "mistral-nemo" in output
        # Parse JSON and verify no prompt-related fields
        event = json.loads(output.strip())
        assert "prompt" not in event
        assert "system_prompt" not in event
        assert "text" not in event
        assert "content" not in event

    def test_log_resolution_never_includes_prompt(self):
        """log_resolution must not log prompt text."""
        from server.model_router import telemetry

        captured = io.StringIO()
        with patch("sys.stderr", captured):
            telemetry.log_resolution(
                task="creative_story",
                model="mistral-nemo",
                provider="ollama",
                is_fallback=False,
                fallback_depth=0,
                reason="Primary model available",
                duration_ms=5.0,
            )

        output = captured.getvalue()
        event = json.loads(output.strip())
        assert "prompt" not in event
        assert "system_prompt" not in event
        assert "text" not in event
        assert "content" not in event
