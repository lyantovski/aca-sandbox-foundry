FROM python:3.11-slim

WORKDIR /app
COPY pyproject.toml main.py ./
RUN pip install --no-cache-dir .

RUN groupadd --gid 10001 app && useradd --uid 10001 --gid app --create-home app
USER 10001

EXPOSE 8081
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8081"]
