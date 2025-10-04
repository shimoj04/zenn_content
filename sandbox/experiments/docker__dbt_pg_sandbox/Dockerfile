FROM python:3.13-slim

RUN apt-get update && \
    apt-get install -y jq git build-essential libpq-dev && \
    pip install --upgrade pip && \
    pip install --no-cache-dir dbt-postgres && \
    rm -rf /var/lib/apt/lists/*
