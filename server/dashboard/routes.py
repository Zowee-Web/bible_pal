"""Dashboard routes — read-only developer dashboard for the Model Router."""

import os

from fastapi import APIRouter, Depends, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

from server.model_router.router import ModelRouter
from .views import get_router, get_mission_control_data, get_models_data, get_router_data

router = APIRouter(prefix="/dashboard", tags=["dashboard"])

_template_dir = os.path.join(os.path.dirname(__file__), "templates")
templates = Jinja2Templates(directory=_template_dir)


@router.get("/", response_class=HTMLResponse)
async def mission_control(
    request: Request, model_router: ModelRouter = Depends(get_router),
):
    """Mission Control — system status overview."""
    data = get_mission_control_data(model_router)
    return templates.TemplateResponse(request, "dashboard.html", data)


@router.get("/models", response_class=HTMLResponse)
async def models_page(
    request: Request, model_router: ModelRouter = Depends(get_router),
):
    """Models — table of all registered models."""
    data = get_models_data(model_router)
    return templates.TemplateResponse(request, "models.html", data)


@router.get("/router", response_class=HTMLResponse)
async def router_page(
    request: Request, model_router: ModelRouter = Depends(get_router),
):
    """Router — interactive task resolution explorer."""
    data = get_router_data(model_router)
    return templates.TemplateResponse(request, "router.html", data)
