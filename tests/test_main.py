"""
Automated test suite for the FastAPI service.
Run by Jenkins in the 'Test' stage: pytest --cov=app --cov-report=xml
"""

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_root():
    resp = client.get("/")
    assert resp.status_code == 200
    body = resp.json()
    assert body["service"] == "cicd-automation-platform"
    assert body["status"] == "running"


def test_health_check():
    resp = client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "healthy"
    assert "uptime_seconds" in body


def test_readiness_check():
    resp = client.get("/health/ready")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ready"


def test_create_and_get_task():
    create_resp = client.post(
        "/api/v1/tasks",
        json={"title": "Deploy pipeline", "description": "Ship it"},
    )
    assert create_resp.status_code == 201
    task = create_resp.json()
    assert task["title"] == "Deploy pipeline"
    assert task["completed"] is False

    get_resp = client.get(f"/api/v1/tasks/{task['id']}")
    assert get_resp.status_code == 200
    assert get_resp.json()["id"] == task["id"]


def test_get_nonexistent_task_returns_404():
    resp = client.get("/api/v1/tasks/does-not-exist")
    assert resp.status_code == 404


def test_create_task_requires_title():
    resp = client.post("/api/v1/tasks", json={"description": "missing title"})
    assert resp.status_code == 422


def test_list_tasks_returns_array():
    resp = client.get("/api/v1/tasks")
    assert resp.status_code == 200
    assert isinstance(resp.json(), list)
