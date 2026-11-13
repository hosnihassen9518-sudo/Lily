FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app
COPY backend/requirements.txt ./
RUN pip install -r requirements.txt \
    && apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && python -m venv /opt/platformio \
    && /opt/platformio/bin/pip install 'platformio==6.1.19' \
    && useradd --uid 10001 --create-home lily \
    && mkdir -p /data/music \
    && chown -R lily:lily /data

COPY --chown=lily:lily backend/app ./app
COPY --chown=lily:lily backend/migrations ./migrations
COPY --chown=lily:lily backend/alembic.ini ./alembic.ini
COPY firmware_shared /firmware/firmware_shared
COPY esp32_device /firmware/esp32_device
COPY esp32_test_light /firmware/esp32_test_light
USER lily
EXPOSE 6100

# A single worker owns the backend's fixed MQTT client ID.
CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "6100", "--workers", "1", "--no-proxy-headers"]
