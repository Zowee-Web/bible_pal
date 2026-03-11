"""Dashboard view helpers — data fetching from ModelRouter and system stats."""

import shutil
from datetime import datetime, timezone

from fastapi import Request

from server.model_router.router import ModelRouter


def get_router(request: Request) -> ModelRouter:
    """FastAPI dependency: extract the ModelRouter from app.state."""
    return request.app.state.router


def get_mission_control_data(router: ModelRouter) -> dict:
    """Gather data for the Mission Control page."""
    availability = router.check_availability()

    disk_info = []
    for path in ("/Volumes/T9-AI", "/Volumes/T9-Archive"):
        try:
            usage = shutil.disk_usage(path)
            disk_info.append({
                "path": path,
                "total_gb": round(usage.total / (1024**3), 1),
                "used_gb": round(usage.used / (1024**3), 1),
                "free_gb": round(usage.free / (1024**3), 1),
                "percent_used": round(usage.used / usage.total * 100, 1),
            })
        except (FileNotFoundError, OSError):
            disk_info.append({
                "path": path,
                "error": "Volume not mounted",
            })

    return {
        "availability": availability,
        "model_count": len(availability.get("registered_models", [])),
        "task_count": len(availability.get("registered_tasks", [])),
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC"),
        "disks": disk_info,
    }


def get_models_data(router: ModelRouter) -> dict:
    """Gather data for the Models page."""
    return {"models": router.list_models()}


def get_router_data(router: ModelRouter) -> dict:
    """Gather data for the Router page."""
    return {"tasks": router.list_tasks()}
