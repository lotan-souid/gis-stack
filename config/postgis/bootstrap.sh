#!/bin/sh
# Idempotent PostGIS bootstrap — run by the postgis-init service on every
# `docker compose up`. Creates/updates the read-only role used by the tile and
# feature servers, and the separate database used by MapStore's GeoStore.
set -eu

for v in GIS_READER_USER GEOSTORE_USER; do
  eval "val=\$$v"
  if [ "$val" = "$POSTGRES_USER" ]; then
    echo "bootstrap: $v must differ from POSTGRES_USER ($POSTGRES_USER)" >&2
    exit 1
  fi
done

export PGHOST=postgis PGUSER="$POSTGRES_USER" PGPASSWORD="$POSTGRES_PASSWORD"

i=0
until pg_isready -q -d "$POSTGRES_DB"; do
  i=$((i + 1))
  if [ "$i" -ge 30 ]; then
    echo "bootstrap: postgis not reachable" >&2
    exit 1
  fi
  sleep 2
done

psql -v ON_ERROR_STOP=1 -d "$POSTGRES_DB" \
  -v db="$POSTGRES_DB" \
  -v owner="$POSTGRES_USER" \
  -v reader="$GIS_READER_USER" \
  -v reader_pw="$GIS_READER_PASSWORD" \
  -v geostore_db="$GEOSTORE_DB" \
  -v geostore_user="$GEOSTORE_USER" \
  -v geostore_pw="$GEOSTORE_PASSWORD" \
  -f /bootstrap/bootstrap.sql

echo "bootstrap: done"
