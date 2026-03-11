"""Tests for dashboard routes."""

import os
from unittest.mock import patch, MagicMock

import pytest

try:
    from fastapi.testclient import TestClient
except ImportError:
    pytest.skip(
        "httpx required for FastAPI TestClient: pip3 install httpx",
        allow_module_level=True,
    )


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def client():
    """Test client with mocked router on app.state."""
    with patch.dict(os.environ, {"MODEL_ROUTER_API_KEY": ""}, clear=False):
        import server.model_router.api as api_module

        api_module._API_KEY = ""

        mock_router = MagicMock()
        mock_router.check_availability.return_value = {
            "ollama_running": True,
            "ollama_url": "http://localhost:11434",
            "installed_models": ["mistral-nemo:latest", "gemma:7b"],
            "registered_models": ["mistral-nemo", "gemma:7b", "gpt-4.1"],
            "registered_tasks": ["creative_story", "traditional_story_remote"],
        }
        mock_router.list_models.return_value = [
            {
                "model": "mistral-nemo",
                "provider": "ollama",
                "params": "12B",
                "local": True,
                "available": True,
            },
            {
                "model": "gpt-4.1",
                "provider": "openai",
                "params": "cloud",
                "local": False,
                "available": None,
            },
        ]
        mock_router.list_tasks.return_value = [
            {
                "task": "creative_story",
                "description": "Creative stories",
                "models": ["mistral-nemo"],
                "locked": False,
                "provider_constraint": "ollama",
            },
            {
                "task": "traditional_story_remote",
                "description": "Traditional stories",
                "models": ["gpt-4.1"],
                "locked": True,
                "provider_constraint": "openai",
            },
        ]

        api_module.app.state.router = mock_router
        yield TestClient(api_module.app)


# ---------------------------------------------------------------------------
# Dashboard endpoints return 200
# ---------------------------------------------------------------------------

class TestDashboardRoutes:
    def test_mission_control_returns_200(self, client):
        resp = client.get("/dashboard/")
        assert resp.status_code == 200
        assert "text/html" in resp.headers["content-type"]

    def test_models_page_returns_200(self, client):
        resp = client.get("/dashboard/models")
        assert resp.status_code == 200
        assert "text/html" in resp.headers["content-type"]

    def test_router_page_returns_200(self, client):
        resp = client.get("/dashboard/router")
        assert resp.status_code == 200
        assert "text/html" in resp.headers["content-type"]


# ---------------------------------------------------------------------------
# Mission Control content
# ---------------------------------------------------------------------------

class TestMissionControlContent:
    def test_shows_ollama_status(self, client):
        resp = client.get("/dashboard/")
        assert "Online" in resp.text

    def test_shows_model_count(self, client):
        resp = client.get("/dashboard/")
        # 3 registered models in mock data
        assert "3" in resp.text

    def test_shows_disk_section(self, client):
        """Disk usage section renders (may show error if volume not mounted)."""
        resp = client.get("/dashboard/")
        assert "/Volumes/T9-AI" in resp.text


# ---------------------------------------------------------------------------
# Models page content
# ---------------------------------------------------------------------------

class TestModelsContent:
    def test_shows_model_names(self, client):
        resp = client.get("/dashboard/models")
        assert "mistral-nemo" in resp.text
        assert "gpt-4.1" in resp.text

    def test_shows_provider(self, client):
        resp = client.get("/dashboard/models")
        assert "ollama" in resp.text
        assert "openai" in resp.text

    def test_shows_availability(self, client):
        resp = client.get("/dashboard/models")
        assert "Available" in resp.text
        assert "Remote" in resp.text


# ---------------------------------------------------------------------------
# Router page content
# ---------------------------------------------------------------------------

class TestRouterContent:
    def test_shows_task_names(self, client):
        resp = client.get("/dashboard/router")
        assert "creative_story" in resp.text
        assert "traditional_story_remote" in resp.text

    def test_shows_locked_badge(self, client):
        resp = client.get("/dashboard/router")
        assert "Locked" in resp.text


# ---------------------------------------------------------------------------
# Existing API endpoints still work
# ---------------------------------------------------------------------------

class TestExistingApiUnaffected:
    def test_health_still_works(self, client):
        resp = client.get("/health")
        assert resp.status_code == 200

    def test_models_api_still_works(self, client):
        resp = client.get("/models")
        assert resp.status_code == 200

    def test_tasks_api_still_works(self, client):
        resp = client.get("/tasks")
        assert resp.status_code == 200
