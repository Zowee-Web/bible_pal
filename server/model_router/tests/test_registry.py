"""Tests for model_registry.json validity."""

import json
import os
import pytest

REGISTRY_PATH = os.path.join(
    os.path.dirname(__file__), "..", "model_registry.json"
)


@pytest.fixture
def registry():
    with open(REGISTRY_PATH, "r") as f:
        return json.load(f)


def test_registry_is_valid_json(registry):
    """Registry file must be valid JSON."""
    assert isinstance(registry, dict)


def test_registry_has_models_and_tasks(registry):
    """Registry must have both models and tasks sections."""
    assert "models" in registry
    assert "tasks" in registry
    assert len(registry["models"]) > 0
    assert len(registry["tasks"]) > 0


def test_all_task_models_exist_in_registry(registry):
    """Every model referenced in a task must exist in the models section."""
    models = registry["models"]
    for task_name, task_def in registry["tasks"].items():
        for model in task_def.get("models", []):
            assert model in models, (
                f"Task '{task_name}' references model '{model}' "
                f"which is not in the models section"
            )


def test_traditional_story_is_locked(registry):
    """traditional_story_remote must be locked with openai constraint."""
    task = registry["tasks"].get("traditional_story_remote")
    assert task is not None, "traditional_story_remote task missing"
    assert task.get("locked") is True, "traditional_story_remote must be locked"
    assert task.get("provider_constraint") == "openai", (
        "traditional_story_remote must have provider_constraint 'openai'"
    )
    assert task.get("models") == ["gpt-4.1"], (
        "traditional_story_remote must only have gpt-4.1"
    )


def test_no_ollama_models_in_traditional_task(registry):
    """traditional_story_remote must not reference any Ollama model."""
    task = registry["tasks"]["traditional_story_remote"]
    models = registry["models"]
    for model_name in task.get("models", []):
        model_def = models.get(model_name, {})
        assert model_def.get("provider") != "ollama", (
            f"Traditional task references Ollama model '{model_name}'"
        )


def test_all_tasks_have_at_least_one_model(registry):
    """Every task must have at least one model in its chain."""
    for task_name, task_def in registry["tasks"].items():
        models = task_def.get("models", [])
        assert len(models) > 0, f"Task '{task_name}' has no models"


def test_no_duplicate_task_names(registry):
    """Task names must be unique (JSON keys are unique by spec, but verify)."""
    task_names = list(registry["tasks"].keys())
    assert len(task_names) == len(set(task_names))


def test_creative_story_chain_matches_batch_script(registry):
    """Creative story fallback chain should match generate_v2_batch.sh."""
    task = registry["tasks"]["creative_story"]
    expected = ["mistral-nemo", "llama3.1:8b", "qwen2.5:7b", "gemma:7b"]
    assert task["models"] == expected


def test_all_models_have_provider(registry):
    """Every model must declare a provider."""
    for name, defn in registry["models"].items():
        assert "provider" in defn, f"Model '{name}' missing provider"
        assert defn["provider"] in ("ollama", "openai"), (
            f"Model '{name}' has unknown provider '{defn['provider']}'"
        )
