#!/usr/bin/env bash
# router_client.sh — Shared helper for Model Router POST /generate calls.
#
# Usage:
#   source scripts/lib/router_client.sh
#   text=$(router_generate "story_title" "$prompt" 0.8 64 30)
#
# Override endpoint:
#   export MODEL_ROUTER_URL=http://localhost:8181/generate

# shellcheck disable=SC2155

router_generate() {
    local task="$1"
    local prompt="$2"
    local temperature="${3:-}"
    local max_tokens="${4:-}"
    local max_time="${5:-60}"

    local url="${MODEL_ROUTER_URL:-http://127.0.0.1:8181/generate}"

    # Build JSON body — include optional fields only when provided
    local body
    body=$(jq -n --arg task "$task" --arg prompt "$prompt" \
        '{task: $task, prompt: $prompt}')
    if [[ -n "$temperature" ]]; then
        body=$(echo "$body" | jq --argjson t "$temperature" '. + {temperature: $t}')
    fi
    if [[ -n "$max_tokens" ]]; then
        body=$(echo "$body" | jq --argjson mt "$max_tokens" '. + {max_tokens: $mt}')
    fi

    # Call the router
    local response
    response=$(curl -s --connect-timeout 5 --max-time "$max_time" \
        -X POST "$url" \
        -H "Content-Type: application/json" \
        -d "$body" 2>/dev/null)

    if [[ $? -ne 0 ]] || [[ -z "$response" ]]; then
        echo "Router generation failed: API unreachable at $url" >&2
        return 1
    fi

    # Parse envelope
    local ok
    ok=$(echo "$response" | jq -r '.ok // empty' 2>/dev/null)

    if [[ "$ok" != "true" ]]; then
        local err_code err_msg
        err_code=$(echo "$response" | jq -r '.error.code // "unknown"' 2>/dev/null)
        err_msg=$(echo "$response" | jq -r '.error.message // "unknown error"' 2>/dev/null)
        echo "Router generation failed [$err_code]: $err_msg" >&2
        return 1
    fi

    # Emit route diagnostic to stderr
    local r_model r_provider r_fallback
    r_model=$(echo "$response" | jq -r '.data.route.model // "unknown"' 2>/dev/null)
    r_provider=$(echo "$response" | jq -r '.data.route.provider // "unknown"' 2>/dev/null)
    r_fallback=$(echo "$response" | jq -r 'if .data.route.is_fallback then "yes" else "no" end' 2>/dev/null)
    echo "[router] $task -> $r_model (provider=$r_provider, fallback=${r_fallback:-unknown})" >&2

    # Return generated text to stdout
    echo "$response" | jq -r '.data.text // empty' 2>/dev/null
}
