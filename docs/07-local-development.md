# 7. Local Development

![Agent frameworks and local runtimes](media/architecture.png)

The local stack preserves the same polyglot boundaries as AKS: LangGraph with
Python for research, Microsoft Agent Framework with C#/.NET for content
creation, and GitHub Copilot SDK with Python for podcast generation.

## Integrated Docker Compose

Copy the environment template and start the stack:

```powershell
Copy-Item .env.example .env
docker compose up --build
```

Open `http://localhost:8080`.

Compose starts the three agents, sandbox broker compatibility service, BFF, and
DevUI with the same relative `/api/agents/*` paths used in AKS. Entra enforcement
is disabled locally.

## Prerequisites for direct development

- Python 3.11 or later
- .NET 10 SDK
- Git

## Research agent

```powershell
Set-Location .\src\agent-research
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -e ".[dev]"
uvicorn main:app --host 0.0.0.0 --port 8001
```

## Creator agent

```powershell
Set-Location .\src\agent-creator\AgentCreator
dotnet run --no-launch-profile --urls "http://localhost:8002"
```

## Podcaster agent

```powershell
Set-Location .\src\agent-podcaster
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -e ".[dev]"
uvicorn main:app --host 0.0.0.0 --port 8003
```

The podcaster sends text-to-speech requests through the configured APIM model
gateway to the Foundry TTS deployment.

## Health checks

```powershell
Invoke-RestMethod http://localhost:8001/health
Invoke-RestMethod http://localhost:8002/health
Invoke-RestMethod http://localhost:8003/health
```

## Tests

Run all repository validation:

```powershell
.\deploy\validate.ps1
```

Or run a targeted suite from its service directory.
