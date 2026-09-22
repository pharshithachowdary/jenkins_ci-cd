"""
CI/CD Automation Platform - FastAPI Service
=============================================
A small, production-shaped FastAPI service used as the deployable
artifact for the Jenkins -> Docker -> AWS EC2 pipeline.

Endpoints:
  GET  /                 - service info
  GET  /health            - liveness probe (used by Docker HEALTHCHECK / Jenkins)
  GET  /health/ready       - readiness probe (checks dependencies)
  GET  /api/v1/tasks       - list tasks
  POST /api/v1/tasks       - create a task
  GET  /api/v1/tasks/{id}  - fetch a task
"""

from __future__ import annotations

import os
import time
import uuid
from datetime import datetime, timezone
from typing import Dict, List, Optional

from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel, Field

APP_NAME = "cicd-automation-platform"
APP_VERSION = os.getenv("APP_VERSION", "0.1.0")
START_TIME = time.time()

app = FastAPI(
    title=APP_NAME,
    version=APP_VERSION,
    description="Sample service deployed via Jenkins -> Docker -> AWS EC2 pipeline",
)

# ---------------------------------------------------------------------------
# In-memory "database" (swap for RDS/DynamoDB/etc. in a real deployment)
# ---------------------------------------------------------------------------
_TASKS: Dict[str, "Task"] = {}


class TaskCreate(BaseModel):
    title: str = Field(..., min_length=1, max_length=200)
    description: Optional[str] = Field(None, max_length=2000)


class Task(TaskCreate):
    id: str
    created_at: datetime
    completed: bool = False


class HealthStatus(BaseModel):
    status: str
    version: str
    uptime_seconds: float
    timestamp: datetime


# ---------------------------------------------------------------------------
# Meta / health endpoints
# ---------------------------------------------------------------------------
@app.get("/", tags=["meta"])
def root():
    return {
        "service": APP_NAME,
        "version": APP_VERSION,
        "status": "running",
    }


@app.get("/health", response_model=HealthStatus, tags=["meta"])
def health():
    """Liveness probe: process is up and responding."""
    return HealthStatus(
        status="healthy",
        version=APP_VERSION,
        uptime_seconds=round(time.time() - START_TIME, 2),
        timestamp=datetime.now(timezone.utc),
    )


@app.get("/health/ready", response_model=HealthStatus, tags=["meta"])
def readiness():
    """
    Readiness probe: in a real deployment this would check DB connectivity,
    downstream services, cache availability, etc. Kept dependency-free here
    so it works out of the box in CI and in the container.
    """
    checks_ok = True  # placeholder for real dependency checks
    if not checks_ok:
        raise HTTPException(status_code=503, detail="Service not ready")
    return HealthStatus(
        status="ready",
        version=APP_VERSION,
        uptime_seconds=round(time.time() - START_TIME, 2),
        timestamp=datetime.now(timezone.utc),
    )


# ---------------------------------------------------------------------------
# Example business API (stand-in for real application logic)
# ---------------------------------------------------------------------------
@app.get("/api/v1/tasks", response_model=List[Task], tags=["tasks"])
def list_tasks():
    return list(_TASKS.values())


@app.post(
    "/api/v1/tasks",
    response_model=Task,
    status_code=status.HTTP_201_CREATED,
    tags=["tasks"],
)
def create_task(payload: TaskCreate):
    task = Task(
        id=str(uuid.uuid4()),
        title=payload.title,
        description=payload.description,
        created_at=datetime.now(timezone.utc),
    )
    _TASKS[task.id] = task
    return task


@app.get("/api/v1/tasks/{task_id}", response_model=Task, tags=["tasks"])
def get_task(task_id: str):
    task = _TASKS.get(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    return task
