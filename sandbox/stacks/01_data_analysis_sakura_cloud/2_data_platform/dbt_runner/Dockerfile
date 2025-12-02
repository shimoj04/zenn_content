FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    git \
  && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir \
    dbt-duckdb \
    duckdb

WORKDIR /app

RUN mkdir -p /root/.dbt

CMD ["bash"]
