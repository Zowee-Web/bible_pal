# Universal Model Router

Task-driven AI model selection and generation for Bible PAL. Resolves task names to the best available local or remote model using a config-driven registry with fallback chains, and executes generation through provider abstraction.

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

## API Server

```bash
# Install dependencies (only needed for API)
pip3 install -r server/model_router/requirements.txt

# Start the API (local-only, port 8181)
uvicorn server.model_router.api:app --host 127.0.0.1 --port 8181
```

### Endpoints

```bash
# Resolution endpoints
curl http://127.0.0.1:8181/health
curl http://127.0.0.1:8181/models
curl http://127.0.0.1:8181/tasks
curl http://127.0.0.1:8181/resolve/creative_story

# Generation endpoint
curl -X POST http://127.0.0.1:8181/generate \
  -H "Content-Type: application/json" \
  -d '{"task": "story_title", "prompt": "A shepherd who lost one sheep"}'
```

### Response Envelopes

All API responses use structured envelopes:

```json
// Success
{"ok": true, "data": { ... }}

// Error
{"ok": false, "error": {"code": "...", "message": "..."}}
```

Pydantic validation errors (e.g., missing fields, out-of-range values) return standard 422 responses.

### POST /generate

Resolve a task to a model AND execute generation in one call.

**Request:**
```json
{
  "task": "creative_story",
  "prompt": "Write a parable about patience...",
  "system_prompt": "You are a faith-based storyteller",
  "temperature": 0.8,
  "max_tokens": 2048
}
```

Required: `task`, `prompt` (1-32000 chars).
Optional: `system_prompt` (max 8000 chars), `temperature` (0.0-2.0, defaults to task default), `max_tokens` (1-4096).

**Response:**
```json
{
  "ok": true,
  "data": {
    "text": "Once upon a time...",
    "route": {
      "model": "mistral-nemo",
      "provider": "ollama",
      "task": "creative_story",
      "is_fallback": false,
      "fallback_depth": 0,
      "locked": false
    },
    "usage": {"prompt_tokens": 42, "completion_tokens": 512},
    "duration_ms": 3200.5
  }
}
```

**Error codes:**

| HTTP Status | Error Code | Meaning |
|-------------|------------|---------|
| 404 | `routing_failed` | Unknown task or routing error |
| 500 | `provider_unavailable` | Unrecognized provider name |
| 502 | `generation_failed` | Provider upstream returned HTTP error |
| 503 | `generation_failed` | Provider unreachable (timeout, connection refused) |

### API Authentication

Set `MODEL_ROUTER_API_KEY` environment variable to enable API key auth:

```bash
export MODEL_ROUTER_API_KEY="your-secret-key"
uvicorn server.model_router.api:app --host 127.0.0.1 --port 8181
```

- Localhost requests (127.0.0.1, ::1 via `request.client.host`) bypass auth
- Remote requests require `Authorization: Bearer <key>` header
- Does NOT trust `X-Forwarded-For` or any forwarded headers
- If `MODEL_ROUTER_API_KEY` is not set, auth is disabled (dev mode)

## Tests

```bash
# Unit tests (requires pytest; test_api.py also requires httpx)
python3 -m pytest server/model_router/tests/ -v

# Smoke tests
bash server/model_router/smoke_test.sh

# Health check
bash scripts/ai_health_check.sh
```

## Architecture

- `model_registry.json` — Config source of truth (models + tasks + fallback chains)
- `router.py` — Core resolution logic (task → model)
- `providers.py` — Provider abstraction (Ollama, OpenAI) — stdlib urllib only
- `availability.py` — Ollama availability checking (cached, graceful failure)
- `telemetry.py` — Privacy-safe structured logging to stderr (never logs prompts)
- `cli.py` — CLI entry point (JSON to stdout)
- `api.py` — FastAPI server (port 8181, auth, envelopes, /generate)

See [ADR-016](../../docs/DECISIONS.md) (initial router) and [ADR-017](../../docs/DECISIONS.md) (execution gateway) for design decisions.
