"""Universal Model Router — core task-to-model resolution.

Resolves a task name to the best available AI model using the
config-driven model registry and Ollama availability checking.
"""

import json
import os
import time
from dataclasses import dataclass, asdict

from . import availability as avail
from . import telemetry


@dataclass
class ModelRoute:
    """Result of model resolution."""

    model: str
    provider: str
    task: str
    is_fallback: bool
    fallback_depth: int
    reason: str
    locked: bool = False
    default_temperature: float = 0.7

    def to_dict(self) -> dict:
        return asdict(self)


class RoutingError(Exception):
    """Raised when no model can be resolved for a task."""

    pass


class ModelRouter:
    """Task-driven model router with availability checking and fallback."""

    def __init__(
        self,
        registry_path: str | None = None,
        ollama_url: str = "http://localhost:11434",
    ):
        if registry_path is None:
            registry_path = os.path.join(
                os.path.dirname(__file__), "model_registry.json"
            )

        with open(registry_path, "r") as f:
            self._registry = json.load(f)

        self._models = self._registry.get("models", {})
        self._tasks = self._registry.get("tasks", {})
        self._ollama = avail.OllamaAvailability(ollama_url)

    def resolve(self, task: str) -> ModelRoute:
        """Resolve a task to the best available model.

        For locked tasks (e.g., traditional_story_remote), returns the
        locked model without checking local availability — or raises
        RoutingError if unavailable.

        For unlocked tasks, walks the fallback chain checking Ollama
        availability.
        """
        start = time.time()

        if task not in self._tasks:
            telemetry.log_error(task, "unknown_task")
            raise RoutingError(f"Unknown task: '{task}'. Available: {list(self._tasks.keys())}")

        task_def = self._tasks[task]
        model_chain = task_def.get("models", [])
        is_locked = task_def.get("locked", False)
        provider_constraint = task_def.get("provider_constraint")
        default_temp = task_def.get("default_temperature", 0.7)

        if not model_chain:
            telemetry.log_error(task, "empty_model_chain")
            raise RoutingError(f"Task '{task}' has no models defined in registry.")

        # Locked tasks: return the model without availability checking
        # (it's the caller's responsibility to have credentials/access)
        if is_locked:
            model_name = model_chain[0]
            model_def = self._models.get(model_name, {})
            provider = model_def.get("provider", provider_constraint or "unknown")

            route = ModelRoute(
                model=model_name,
                provider=provider,
                task=task,
                is_fallback=False,
                fallback_depth=0,
                reason=f"Locked task — model '{model_name}' required (no substitution allowed)",
                locked=True,
                default_temperature=default_temp,
            )

            elapsed = (time.time() - start) * 1000
            telemetry.log_resolution(
                task=task,
                model=model_name,
                provider=provider,
                is_fallback=False,
                fallback_depth=0,
                reason=route.reason,
                duration_ms=elapsed,
            )
            return route

        # Unlocked tasks: walk the fallback chain
        for depth, model_name in enumerate(model_chain):
            model_def = self._models.get(model_name, {})
            provider = model_def.get("provider", "ollama")

            # Only check availability for local (Ollama) models
            if provider == "ollama":
                if not self._ollama.is_available(model_name):
                    continue

            is_fb = depth > 0
            reason = (
                f"Primary model '{model_name}' available"
                if not is_fb
                else f"Fallback depth {depth}: '{model_chain[0]}' unavailable, using '{model_name}'"
            )

            route = ModelRoute(
                model=model_name,
                provider=provider,
                task=task,
                is_fallback=is_fb,
                fallback_depth=depth,
                reason=reason,
                locked=False,
                default_temperature=default_temp,
            )

            elapsed = (time.time() - start) * 1000
            telemetry.log_resolution(
                task=task,
                model=model_name,
                provider=provider,
                is_fallback=is_fb,
                fallback_depth=depth,
                reason=reason,
                duration_ms=elapsed,
            )
            return route

        # No model available in the chain
        telemetry.log_error(task, "no_models_available")
        raise RoutingError(
            f"No models available for task '{task}'. "
            f"Tried: {model_chain}. Is Ollama running?"
        )

    def list_tasks(self) -> list[dict]:
        """Return all defined task types with their descriptions."""
        result = []
        for name, defn in self._tasks.items():
            result.append({
                "task": name,
                "description": defn.get("description", ""),
                "models": defn.get("models", []),
                "locked": defn.get("locked", False),
                "provider_constraint": defn.get("provider_constraint"),
            })
        return result

    def list_models(self) -> list[dict]:
        """Return all registered models with availability status."""
        result = []
        for name, defn in self._models.items():
            entry = {
                "model": name,
                "provider": defn.get("provider", "unknown"),
                "params": defn.get("params", ""),
                "local": defn.get("local", False),
            }
            if defn.get("provider") == "ollama":
                entry["available"] = self._ollama.is_available(name)
            else:
                entry["available"] = None  # Can't check remote availability
            result.append(entry)
        return result

    def explain(self, task: str) -> str:
        """Return a human-readable explanation of routing for a task."""
        if task not in self._tasks:
            return f"Unknown task: '{task}'. Available: {', '.join(self._tasks.keys())}"

        task_def = self._tasks[task]
        lines = [
            f"Task: {task}",
            f"Description: {task_def.get('description', 'N/A')}",
            f"Provider constraint: {task_def.get('provider_constraint', 'none')}",
            f"Locked: {task_def.get('locked', False)}",
            f"Default temperature: {task_def.get('default_temperature', 0.7)}",
            f"Model chain ({len(task_def.get('models', []))} models):",
        ]

        for i, model_name in enumerate(task_def.get("models", [])):
            model_def = self._models.get(model_name, {})
            avail_str = ""
            if model_def.get("provider") == "ollama":
                avail_str = " [AVAILABLE]" if self._ollama.is_available(model_name) else " [NOT INSTALLED]"
            elif model_def.get("provider") == "openai":
                avail_str = " [REMOTE/OPENAI]"

            role = "primary" if i == 0 else f"fallback-{i}"
            lines.append(
                f"  {i + 1}. {model_name} ({model_def.get('params', '?')}) "
                f"— {role}{avail_str}"
            )

        if task_def.get("notes"):
            lines.append(f"Notes: {task_def['notes']}")

        return "\n".join(lines)

    def check_availability(self) -> dict:
        """Return system availability status."""
        ollama_running = self._ollama.is_server_running()
        installed = self._ollama.list_models() if ollama_running else []

        return {
            "ollama_running": ollama_running,
            "ollama_url": self._ollama.base_url,
            "installed_models": installed,
            "registered_models": list(self._models.keys()),
            "registered_tasks": list(self._tasks.keys()),
        }
