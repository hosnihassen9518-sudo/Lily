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
COPY --chown=lily:lily migrations ./migrations
COPY --chown=lily:lily alembic.ini ./alembic.ini
USER lily
EXPOSE 6100

# A single worker owns the backend's fixed MQTT client ID.
CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "6100", "--workers", "1"]
