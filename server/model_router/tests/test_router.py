"""Tests for the ModelRouter resolution logic."""

import json
import os
import pytest
from unittest.mock import patch

from server.model_router.router import ModelRouter, ModelRoute, RoutingError


REGISTRY_PATH = os.path.join(
    os.path.dirname(__file__), "..", "model_registry.json"
)


@pytest.fixture
def router_all_available():
    """Router where all Ollama models appear available."""
    with patch("server.model_router.availability.OllamaAvailability") as MockAvail:
        instance = MockAvail.return_value
        instance.list_models.return_value = [
            "mistral-nemo:latest",
            "llama3.1:8b",
            "qwen2.5:7b",
            "mixtral:latest",
            "gemma:7b",
            "deepseek-coder:latest",
            "codellama:latest",
            "phi3:latest",
        ]
        instance.is_available.return_value = True
        instance.is_server_running.return_value = True
        router = ModelRouter.__new__(ModelRouter)
        with open(REGISTRY_PATH, "r") as f:
            router._registry = json.load(f)
        router._models = router._registry["models"]
        router._tasks = router._registry["tasks"]
        router._ollama = instance
        yield router


@pytest.fixture
def router_no_models():
    """Router where no Ollama models are available."""
    with patch("server.model_router.availability.OllamaAvailability") as MockAvail:
        instance = MockAvail.return_value
        instance.list_models.return_value = []
        instance.is_available.return_value = False
        instance.is_server_running.return_value = True
        router = ModelRouter.__new__(ModelRouter)
        with open(REGISTRY_PATH, "r") as f:
            router._registry = json.load(f)
        router._models = router._registry["models"]
        router._tasks = router._registry["tasks"]
        router._ollama = instance
        yield router


@pytest.fixture
def router_partial():
    """Router where only some models are available."""
    with patch("server.model_router.availability.OllamaAvailability") as MockAvail:
        instance = MockAvail.return_value
        instance.list_models.return_value = [
            "qwen2.5:7b",
            "gemma:7b",
        ]

        def _is_available(name):
            return name in ("qwen2.5:7b", "gemma:7b")

        instance.is_available.side_effect = _is_available
        instance.is_server_running.return_value = True
        router = ModelRouter.__new__(ModelRouter)
        with open(REGISTRY_PATH, "r") as f:
            router._registry = json.load(f)
        router._models = router._registry["models"]
        router._tasks = router._registry["tasks"]
        router._ollama = instance
        yield router


class TestResolve:
    def test_resolves_primary_when_available(self, router_all_available):
        route = router_all_available.resolve("creative_story")
        assert route.model == "mistral-nemo"
        assert route.is_fallback is False
        assert route.fallback_depth == 0

    def test_fallback_when_primary_unavailable(self, router_partial):
        route = router_partial.resolve("creative_story")
        assert route.model == "qwen2.5:7b"
        assert route.is_fallback is True
        assert route.fallback_depth == 2

    def test_locked_task_returns_without_checking(self, router_no_models):
        """Locked tasks should return the model even if Ollama is empty."""
        route = router_no_models.resolve("traditional_story_remote")
        assert route.model == "gpt-4.1"
        assert route.locked is True
        assert route.is_fallback is False

    def test_no_models_raises_error(self, router_no_models):
        with pytest.raises(RoutingError, match="No models available"):
            router_no_models.resolve("creative_story")

    def test_unknown_task_raises_error(self, router_all_available):
        with pytest.raises(RoutingError, match="Unknown task"):
            router_all_available.resolve("nonexistent_task")

    def test_route_has_correct_provider(self, router_all_available):
        route = router_all_available.resolve("creative_story")
        assert route.provider == "ollama"

        route = router_all_available.resolve("traditional_story_remote")
        assert route.provider == "openai"

    def test_route_includes_temperature(self, router_all_available):
        route = router_all_available.resolve("creative_story")
        assert route.default_temperature == 0.8

        route = router_all_available.resolve("coding_flutter")
        assert route.default_temperature == 0.3

    def test_longform_uses_mixtral(self, router_all_available):
        route = router_all_available.resolve("longform_experimental")
        assert route.model == "mixtral"

    def test_coding_uses_deepseek(self, router_all_available):
        route = router_all_available.resolve("coding_flutter")
        assert route.model == "deepseek-coder"

    def test_reasoning_fast_uses_phi3(self, router_all_available):
        route = router_all_available.resolve("reasoning_fast")
        assert route.model == "phi3"


class TestListTasks:
    def test_returns_all_tasks(self, router_all_available):
        tasks = router_all_available.list_tasks()
        task_names = [t["task"] for t in tasks]
        assert "creative_story" in task_names
        assert "traditional_story_remote" in task_names
        assert "coding_flutter" in task_names
        assert len(tasks) == 8


class TestExplain:
    def test_explain_returns_text(self, router_all_available):
        text = router_all_available.explain("creative_story")
        assert "creative_story" in text
        assert "mistral-nemo" in text

    def test_explain_unknown_task(self, router_all_available):
        text = router_all_available.explain("nonexistent")
        assert "Unknown task" in text


class TestToDict:
    def test_route_serializes(self, router_all_available):
        route = router_all_available.resolve("creative_story")
        d = route.to_dict()
        assert d["model"] == "mistral-nemo"
        assert d["task"] == "creative_story"
        assert isinstance(d, dict)
