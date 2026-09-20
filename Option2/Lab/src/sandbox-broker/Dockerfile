FROM python:3.11-slim

WORKDIR /app
COPY src/sandbox-broker/pyproject.toml src/sandbox-broker/main.py ./
COPY src/agent-research/tools/ tools/
RUN pip install --no-cache-dir .

EXPOSE 8010
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8010"]
