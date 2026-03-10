"""Tests for OllamaAvailability."""

import json
import pytest
from unittest.mock import patch, MagicMock

from server.model_router.availability import OllamaAvailability


class TestIsAvailable:
    def test_matches_base_name(self):
        """'mistral-nemo' should match 'mistral-nemo:latest'."""
        avail = OllamaAvailability()
        with patch.object(avail, "list_models", return_value=["mistral-nemo:latest"]):
            assert avail.is_available("mistral-nemo") is True

    def test_matches_exact_tag(self):
        """'qwen2.5:7b' should match 'qwen2.5:7b'."""
        avail = OllamaAvailability()
        with patch.object(avail, "list_models", return_value=["qwen2.5:7b"]):
            assert avail.is_available("qwen2.5:7b") is True

    def test_no_match_returns_false(self):
        avail = OllamaAvailability()
        with patch.object(avail, "list_models", return_value=["mistral-nemo:latest"]):
            assert avail.is_available("phi3") is False

    def test_empty_list_returns_false(self):
        avail = OllamaAvailability()
        with patch.object(avail, "list_models", return_value=[]):
            assert avail.is_available("mistral-nemo") is False


class TestCaching:
    def test_cache_prevents_repeated_calls(self):
        avail = OllamaAvailability()
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({
            "models": [{"name": "mistral-nemo:latest"}]
        }).encode()
        mock_response.status = 200
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)

        with patch("urllib.request.urlopen", return_value=mock_response) as mock_url:
            result1 = avail.list_models()
            result2 = avail.list_models()

            # Should only call urlopen once due to caching
            assert mock_url.call_count == 1
            assert result1 == result2

    def test_invalidate_cache_forces_refresh(self):
        avail = OllamaAvailability()
        avail._cache = ["old-model:latest"]
        avail._cache_time = 999999999999  # far future

        avail.invalidate_cache()
        assert avail._cache is None


class TestServerDown:
    def test_list_models_returns_empty_on_error(self):
        avail = OllamaAvailability()
        with patch("urllib.request.urlopen", side_effect=OSError("Connection refused")):
            result = avail.list_models()
            assert result == []

    def test_is_server_running_returns_false_on_error(self):
        avail = OllamaAvailability()
        with patch("urllib.request.urlopen", side_effect=OSError("Connection refused")):
            assert avail.is_server_running() is False
