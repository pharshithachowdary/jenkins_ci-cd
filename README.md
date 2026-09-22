# Python CI/CD Automation Platform

A FastAPI service paired with a full Jenkins CI/CD pipeline that tests, containerizes,
and deploys it to AWS EC2 — with automated health validation and rollback.

## Stack
- **App:** Python 3.12, FastAPI, Uvicorn
- **Tests:** pytest, pytest-cov, flake8/black
- **CI/CD:** Jenkins (declarative pipeline, Groovy)
- **Packaging:** Docker (multi-stage build, non-root user, built-in HEALTHCHECK)
- **Registry/Deploy target:** AWS ECR + EC2
- **Source control:** GitHub (webhook-triggered builds)

## Project layout
```
app/               FastAPI application (main.py: routes, models, health checks)
tests/             pytest suite covering routes, validation, and health endpoints
scripts/
  deploy.sh          Runs on EC2: pulls image, blue/green swap, verifies health
  rollback.sh        Runs on EC2: restores previous container on failed deploy
  health_check.sh    Runs from Jenkins: polls /health with retries as a release gate
  provision_ec2.sh   One-time EC2 setup (Docker + AWS CLI)
Dockerfile         Multi-stage build -> slim runtime image
docker-compose.yml Local dev/test runner
Jenkinsfile        Full pipeline definition
```

## Run locally
```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
uvicorn app.main:app --reload
# -> http://localhost:8000/health
```

## Run tests
```bash
pytest tests/ --cov=app --cov-report=term
```

## Run in Docker
```bash
docker compose up --build
curl http://localhost:8000/health
```

## Pipeline overview (Jenkinsfile)
1. **Checkout** — pulls the triggering commit from GitHub.
2. **Setup Python Environment** — creates a venv, installs `requirements-dev.txt`.
3. **Lint** — `flake8` + `black --check`.
4. **Test** — `pytest` with JUnit XML + coverage, published to Jenkins.
5. **Build Docker Image** — tags the image `<build>-<git-sha>`.
6. **Push to ECR** — authenticates via `aws ecr get-login-password`, pushes the
   build tag and `latest` (main branch only).
7. **Deploy to AWS EC2** — SSHes to the target instance and runs `scripts/deploy.sh`,
   which does a blue/green swap: starts the new container on a staging port,
   confirms it's healthy, then swaps it onto the production port.
8. **Post-Deploy Health Validation** — `scripts/health_check.sh` polls the public
   `/health` endpoint with retries as an explicit release gate.

### Failure handling
If the deploy or health-validation stage fails, the `post { failure { ... } }`
block SSHes back into EC2 and runs `scripts/rollback.sh`, which restores the
previous container so a bad release never stays live. Every run also prunes
dangling Docker images and cleans the Jenkins workspace in `post { always { ... } }`.

## Jenkins setup checklist
- Credentials: `aws-credentials` (AWS keys or use an instance profile instead),
  `ec2-ssh-key` (SSH private key), `ec2-deploy-host` (secret text: `user@host`).
- Plugins: Pipeline, Docker Pipeline, SSH Agent, JUnit, Git.
- GitHub: add a webhook (`Settings > Webhooks`) pointing at your Jenkins
  `/github-webhook/` endpoint, or use the GitHub Branch Source plugin, so pushes
  trigger builds automatically.
- Update the placeholder `ECR_REPO` account ID/region in the `Jenkinsfile`.

## AWS EC2 target setup
Run once per instance (or via user-data at launch):
```bash
./scripts/provision_ec2.sh
```
This installs Docker and the AWS CLI, and prints the credential values to
register in Jenkins. Ensure the instance's security group allows inbound
traffic on port 8000 (and 22 for Jenkins' SSH deploy step).
# jenkins_ci-cd
