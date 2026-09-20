# Run Locally

## Recommended: Docker Compose

Docker Compose now starts the three agents, the ACA Sandbox broker compatibility service, the BFF, and DevUI with the same relative `/api/agents/*` routing used on AKS:

```powershell
Set-Location Option2\Lab
Copy-Item .env.example .env
docker compose up --build
```

Open `http://localhost:8080`.

Local Compose leaves BFF Entra enforcement disabled and preserves direct ACA Sandbox behavior when broker credentials are not configured. The AKS Helm deployment enables the authenticated BFF boundary.

The manual steps below are intended for agent development and endpoint testing. The static DevUI requires nginx/BFF routing and should not be served with `python -m http.server` after the BFF migration.

## Prerequisites

- Python 3.11+
- .NET 10 SDK
- Git

## Setup

```bash
cd Lab
cp .env.example .env
# Edit .env with your Azure OpenAI credentials (optional for basic demo)
```

## Start Agent 1 (Research)

```bash
cd Lab/src/agent-research
python -m venv .venv
.venv\Scripts\Activate.ps1   # Windows
# source .venv/bin/activate  # Linux/Mac
pip install -e ".[dev]"
uvicorn main:app --host 0.0.0.0 --port 8001
```

Runs on http://localhost:8001

## Start Agent 2 (Content Creator)

In a second terminal:

```bash
cd Lab/src/agent-creator/AgentCreator
dotnet run --no-launch-profile --urls "http://localhost:8002"
```

Runs on http://localhost:8002

## Start Agent 3 (Podcaster)

The podcaster agent converts research into a two-voice conversational podcast using TTS.

TTS backend is selected with `CONTENT_FACTORY_MODE` in `Lab/.env`:

- **`lab` (default)** — uses the **Azure OpenAI TTS** deployment (`tts-1`). No GPU or local TTS server needed.
- **`full`** — uses a self-hosted GPU XTTS-v2 server (see step below) with Azure OpenAI as fallback.

In a third terminal:

```bash
cd Lab/src/agent-podcaster
python -m venv .venv
.venv\Scripts\Activate.ps1   # Windows
# source .venv/bin/activate  # Linux/Mac
pip install -e ".[dev]"
uvicorn main:app --host 0.0.0.0 --port 8003
```

Runs on http://localhost:8003

## (Optional) Self-hosted GPU TTS Server

Only needed if you want to use XTTS-v2 instead of Azure OpenAI TTS. Requires a CUDA-capable GPU.

In a fourth terminal:

```bash
cd Lab/src/tts-server
python -m venv .venv
.venv\Scripts\Activate.ps1   # Windows
# source .venv/bin/activate  # Linux/Mac
pip install -e ".[dev]"
uvicorn main:app --host 0.0.0.0 --port 8004 --workers 1
```

Set these in `Lab/.env`:

```
CONTENT_FACTORY_MODE=full
TTS_SERVER_URL=http://localhost:8004
TTS_HOST_VOICE=host-female
TTS_GUEST_VOICE=guest-male
TTS_TIMEOUT_BUDGET_SECONDS=300
```

## Start Dev UI

Use Docker Compose for the integrated DevUI, BFF, and agent routing. For manual agent development, call the health and A2A endpoints directly.

## Verify

```bash
curl http://localhost:8001/health
curl http://localhost:8002/health
curl http://localhost:8003/health   # if podcaster enabled
```

All should return `{"status":"healthy"}`.

## Use

1. Open http://localhost:8080
2. Enter a topic (e.g. "Migrating Java 8 to Azure Container Apps")
3. Click "Run Pipeline"
4. Agent 1 researches real sources (Microsoft Learn, GitHub, Stack Overflow)
5. Agent 2 generates blog post, demo project, social content from those sources
6. Agent 3 (if enabled) creates a conversational podcast episode with TTS audio