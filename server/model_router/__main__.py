"""Allow running as: python3 -m server.model_router <command>"""
from .cli import main
import sys

sys.exit(main())
