# GIS Stack

Version: **6.0.1**

Docker Compose stack for a GIS platform, including:

- GeoServer
- MapStore2
- PostGIS
- Solr
- pg_tileserv
- pg_featureserv
- pgAdmin
- TileServer-GL
- pygeoapi
- Martin
- Tegola
- MapFish Print

## Setup

1. Copy `.env.example` to `.env` and fill in the values.
2. Run `docker compose up -d`.

Service configuration files live under [config/](config/).
