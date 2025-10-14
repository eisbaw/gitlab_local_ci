"""
Example unit tests for API
"""
import pytest
from src.main import app


def test_basic():
    assert 1 + 1 == 2


def test_app_exists():
    assert app is not None
    assert app.title == "Monorepo Platform API"
