"""CLI entry point for the Universal Model Router.

Usage:
    python3 -m server.model_router.cli resolve creative_story
    python3 -m server.model_router.cli list-tasks
    python3 -m server.model_router.cli list-models
    python3 -m server.model_router.cli explain creative_story
    python3 -m server.model_router.cli check-availability

JSON output goes to stdout. Human-readable messages go to stderr.
"""

import argparse
import json
import sys

from .router import ModelRouter, RoutingError


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="model-router",
        description="Universal Model Router — task-driven AI model selection",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # resolve
    resolve_p = subparsers.add_parser("resolve", help="Resolve a task to a model")
    resolve_p.add_argument("task", help="Task name (e.g., creative_story)")
    resolve_p.add_argument("--human", action="store_true", help="Human-readable output")

    # list-tasks
    subparsers.add_parser("list-tasks", help="List all defined task types")

    # list-models
    subparsers.add_parser("list-models", help="List all registered models with availability")

    # explain
    explain_p = subparsers.add_parser("explain", help="Explain routing for a task")
    explain_p.add_argument("task", help="Task name")

    # check-availability
    subparsers.add_parser("check-availability", help="Check system availability")

    args = parser.parse_args()
    router = ModelRouter()

    try:
        if args.command == "resolve":
            return _cmd_resolve(router, args)
        elif args.command == "list-tasks":
            return _cmd_list_tasks(router)
        elif args.command == "list-models":
            return _cmd_list_models(router)
        elif args.command == "explain":
            return _cmd_explain(router, args)
        elif args.command == "check-availability":
            return _cmd_check_availability(router)
    except RoutingError as e:
        _json_out({"error": str(e)})
        return 1
    except Exception as e:
        _json_out({"error": f"Unexpected error: {e}"})
        return 2

    return 0


def _cmd_resolve(router: ModelRouter, args) -> int:
    route = router.resolve(args.task)
    if args.human:
        print(
            f"Task: {route.task}\n"
            f"Model: {route.model}\n"
            f"Provider: {route.provider}\n"
            f"Fallback: {'yes (depth ' + str(route.fallback_depth) + ')' if route.is_fallback else 'no (primary)'}\n"
            f"Locked: {route.locked}\n"
            f"Reason: {route.reason}",
            file=sys.stderr,
        )
        # Still output model name to stdout for piping
        print(route.model)
    else:
        _json_out(route.to_dict())
    return 0


def _cmd_list_tasks(router: ModelRouter) -> int:
    _json_out({"tasks": router.list_tasks()})
    return 0


def _cmd_list_models(router: ModelRouter) -> int:
    _json_out({"models": router.list_models()})
    return 0


def _cmd_explain(router: ModelRouter, args) -> int:
    explanation = router.explain(args.task)
    print(explanation)
    return 0


def _cmd_check_availability(router: ModelRouter) -> int:
    status = router.check_availability()
    _json_out(status)
    return 0


def _json_out(data: dict) -> None:
    """Write JSON to stdout."""
    print(json.dumps(data, indent=2))


if __name__ == "__main__":
    sys.exit(main())
