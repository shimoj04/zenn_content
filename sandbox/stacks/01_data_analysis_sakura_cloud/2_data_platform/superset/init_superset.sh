#!/bin/bash
set -e

superset db upgrade

superset fab create-admin \
  --username "${ADMIN_USERNAME:-admin}" \
  --password "${ADMIN_PASSWORD:-admin}" \
  --firstname "${ADMIN_FIRST_NAME:-Admin}" \
  --lastname "${ADMIN_LAST_NAME:-User}" \
  --email "${ADMIN_EMAIL:-admin@example.com}" || true

superset init

gunicorn \
  --bind 0.0.0.0:8088 \
  --workers 4 \
  "superset.app:create_app()"

