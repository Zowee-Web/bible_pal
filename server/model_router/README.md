# Universal Model Router

Task-driven AI model selection for Bible PAL. Resolves task names to the best available local or remote model using a config-driven registry with fallback chains.

## Quick Start

```bash
# From project root
cd /Volumes/T9-AI/bible_pal

# Resolve a task to a model (JSON output)
python3 -m server.model_router.cli resolve creative_story

# Human-readable output
python3 -m server.model_router.cli resolve creative_story --human

# List all tasks
python3 -m server.model_router.cli list-tasks

# Explain routing for a task
python3 -m server.model_router.cli explain creative_story

# Check system availability
python3 -m server.model_router.cli check-availability
```

## Task Types

| Task | Primary Model | Description |
|------|--------------|-------------|
| `creative_story` | mistral-nemo | Creative mode stories |
| `traditional_story_remote` | gpt-4.1 (LOCKED) | Traditional Bible retellings |
| `story_title` | mistral-nemo | Story title generation |
| `coding_flutter` | deepseek-coder | Flutter/Dart assistance |
| `coding_general` | deepseek-coder | General coding assistance |
| `reasoning_fast` | phi3 | Quick reasoning tasks |
| `reasoning_balanced` | qwen2.5:7b | Balanced analysis |
| `longform_experimental` | mixtral | Long-form generation |

## Registry

The model registry is in `model_registry.json`. Edit this file to:
- Add new models
- Change fallback chains
- Adjust default temperatures
- Add new task types

## FastAPI Server

```bash
# Install dependencies (only needed for API)
pip3 install -r server/model_router/requirements.txt

# Start the API (local-only, port 8181)
uvicorn server.model_router.api:app --host 127.0.0.1 --port 8181

# Endpoints
curl http://127.0.0.1:8181/health
curl http://127.0.0.1:8181/models
curl http://127.0.0.1:8181/tasks
curl http://127.0.0.1:8181/resolve/creative_story
```

## Tests

```bash
# Unit tests (requires pytest)
python3 -m pytest server/model_router/tests/ -v

# Smoke tests
bash server/model_router/smoke_test.sh

# Health check
bash scripts/ai_health_check.sh
```

## Architecture

- `model_registry.json` — Config source of truth (models + tasks + fallback chains)
- `router.py` — Core resolution logic
- `availability.py` — Ollama availability checking (cached, graceful failure)
- `telemetry.py` — Privacy-safe structured logging to stderr
- `cli.py` — CLI entry point (JSON to stdout)
- `api.py` — FastAPI prototype (port 8181)

See [ADR-016](../../docs/DECISIONS.md) for the design decision.
