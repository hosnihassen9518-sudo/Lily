FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app
COPY requirements.txt ./
RUN pip install -r requirements.txt \
    && useradd --uid 10001 --create-home lily \
    && mkdir -p /data/music \
    && chown -R lily:lily /data

COPY --chown=lily:lily app ./app
USER lily
EXPOSE 8000

# A single worker owns the backend's fixed MQTT client ID.
CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
