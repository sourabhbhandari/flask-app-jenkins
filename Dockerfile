FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=8080

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py ./

# Drop privileges
RUN addgroup --system app && adduser --system --ingroup app app
USER app

EXPOSE 8080

# Healthcheck (uses python rather than curl to avoid an extra package)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request, sys; \
sys.exit(0) if urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=2).status==200 else sys.exit(1)"

# Production-ish entry: gunicorn with 2 workers
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--access-logfile", "-", "app:app"]
