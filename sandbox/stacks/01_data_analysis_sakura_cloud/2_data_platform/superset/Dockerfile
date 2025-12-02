FROM apache/superset:latest

USER root
RUN pip install --no-cache-dir \
    duckdb \
    duckdb-engine
USER superset

COPY --chown=superset:superset init_superset.sh /app/init_superset.sh
RUN chmod +x /app/init_superset.sh

ENTRYPOINT ["/app/init_superset.sh"]
