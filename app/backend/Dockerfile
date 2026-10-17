# ---- build stage: install dependencies into a virtualenv ----
FROM python:3.12-slim AS build
WORKDIR /app
RUN python -m venv /venv
COPY requirements.txt .
RUN /venv/bin/pip install --no-cache-dir -r requirements.txt

# ---- runtime stage: small image, non-root user ----
FROM python:3.12-slim
LABEL org.opencontainers.image.title="bagtrace-backend" \
      org.opencontainers.image.description="BagTrace API: IATA BSM ingestion and bag tracking"
ENV PATH="/venv/bin:$PATH" PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PORT=8080
RUN useradd --system --uid 10001 --home /app bagtrace
WORKDIR /app
COPY --from=build /venv /venv
COPY --chown=bagtrace:bagtrace app.py bsm.py storage.py wsgi.py ./
USER 10001
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=15s \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/health/live').status==200 else 1)"
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--access-logfile", "-", "wsgi:app"]
