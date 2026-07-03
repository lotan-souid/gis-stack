# GIS Stack

Version: **6.1.0**

A self-contained GIS platform delivered as a single Docker Compose stack. It
bundles a spatial database with a broad set of OGC services, tile/feature
servers, an administration UI, and a web map client — all wired together on one
private Docker network so they can talk to each other by service name.

## Architecture

At the center of the stack is **PostGIS**, the spatial database. Almost every
other service is a consumer of that database: the tile and feature servers read
geometries from it, and the web client and admin tools connect back to it. The
services are grouped by role below.

```
                         ┌──────────────┐
                         │   MapStore2  │  web map client (UI)
                         └──────┬───────┘
                                │
   ┌───────────────┬───────────┼──────────────┬────────────────┐
   │               │           │              │                │
┌──┴───┐   ┌───────┴─────┐ ┌───┴─────┐ ┌──────┴─────┐  ┌────────┴────┐
│Geo-  │   │ pg_tileserv │ │ Martin  │ │  Tegola    │  │  pygeoapi   │
│server│   │ pg_feature- │ │         │ │            │  │  (OGC API)  │
│(OGC) │   │ serv        │ │ (MVT)   │ │  (MVT)     │  │             │
└──┬───┘   └──────┬──────┘ └────┬────┘ └─────┬──────┘  └──────┬──────┘
   │              │             │            │                │
   └──────────────┴─────────────┼────────────┴────────────────┘
                                │
                         ┌──────┴───────┐
                         │   PostGIS    │  spatial database (source of truth)
                         └──────┬───────┘
                                │
                         ┌──────┴───────┐
                         │   pgAdmin    │  database administration UI
                         └──────────────┘
```

All containers share a single bridge network, `gis-network`, defined at the
bottom of `docker-compose.yml`. Services reference each other by their compose
service name (e.g. the tile servers point their `DATABASE_URL` at the host
`postgis`), so no host-level networking is required between them.

## Services

### Data layer

| Service      | Role                                                                 |
| ------------ | -------------------------------------------------------------------- |
| **PostGIS**  | Spatial database — the source of truth for all geometry data.        |
| **pgAdmin**  | Web UI for administering the PostGIS database.                       |

### OGC / API services

| Service         | Role                                                                       |
| --------------- | -------------------------------------------------------------------------- |
| **GeoServer**   | Full OGC server (WMS/WFS/WCS/WMTS); publishes styled layers.               |
| **pygeoapi**    | OGC API — Features / Coverages / Tiles, driven by a YAML config.          |

### Tile & feature servers

| Service            | Role                                                              |
| ------------------ | ---------------------------------------------------------------- |
| **pg_tileserv**    | Serves Mapbox Vector Tiles straight from PostGIS tables.         |
| **pg_featureserv** | Serves GeoJSON features (OGC API — Features) from PostGIS.       |
| **Martin**         | High-performance vector-tile server for PostGIS.                 |
| **Tegola**         | Vector-tile server configured via `config/tegola/config.toml`.   |
| **TileServer-GL**  | Serves raster/vector basemaps and styles from local MBTiles.     |

### Client & utilities

| Service          | Role                                                                    |
| ---------------- | ----------------------------------------------------------------------- |
| **MapStore2**    | Web map client / portal for building and sharing maps.                  |
| **GeoLibre**     | Lightweight, browser-based GIS client for exploration and analysis.     |
| **Solr**         | Search index (e.g. Blacklight core) for catalog/metadata search.        |
| **MapFish Print**| Print/report generation service for producing PDF maps.                 |

#### GeoLibre

[GeoLibre](https://github.com/opengeos/GeoLibre) is a lightweight, cloud-native
GIS client that runs entirely in the browser. Unlike MapStore2 (a server-backed
portal tied to PostGIS/GeoServer), GeoLibre does **not** connect to the database
directly — it processes vector data client-side via DuckDB-WASM Spatial and
renders with MapLibre GL + deck.gl. It complements the stack in two ways:

- **As a client**, it consumes the stack's outputs: vector tiles from
  Martin / pg_tileserv / Tegola, OGC API — Features from pygeoapi /
  pg_featureserv, WMS/WFS from GeoServer, and PMTiles / COG files.
- **As a conversion utility**, its bundled Python sidecar (served under
  `/sidecar`) converts vectors to FlatGeobuf / PMTiles and rasters to COG, and
  runs Whitebox geoprocessing tools. The sidecar reads and writes inside the
  container's `/data` directory (`GEOLIBRE_CONVERSION_ROOTS`), bind-mounted from
  `./data/geolibre` — a convenient place to prepare tiles/COGs that
  TileServer-GL and the tile servers then serve.

The container serves a static nginx frontend on port 80; the sidecar starts
automatically alongside it. No database connection is required.

## Configuration

Runtime settings are supplied through environment variables and a set of
mounted config files.

- **`.env`** — copied from `.env.example`; holds ports, image versions, and
  credentials. Each service in `docker-compose.yml` reads its port, version,
  and secrets from here (`${...}` substitutions).
- **`config/`** — service-specific config files bind-mounted read-only into the
  containers:
  - `config/pygeoapi/config.yml` — pygeoapi server and resource definitions.
  - `config/tegola/config.toml` — Tegola providers, layers, and map definitions.
  - `config/mapfish/print-apps/` — MapFish Print layout/app definitions.
  - `config/geostore-datasource-ovr-postgres.properties` — MapStore's GeoStore
    datasource override, pointing it at PostGIS. Ships with example values that
    mirror `.env.example`; keep its credentials in sync with your `.env`.
- **`data/`** — bind-mounted persistent volumes (PostGIS data, GeoServer data
  dir, Solr, pgAdmin, TileServer-GL, GeoLibre conversion root, …). This
  directory is git-ignored.

## Ports

Host ports are defined in `.env` (defaults shown):

| Service        | Default host port |
| -------------- | ----------------- |
| GeoServer      | 8090              |
| MapStore2      | 8091              |
| PostGIS        | 5433              |
| pgAdmin        | 5050              |
| Solr           | 8983              |
| pg_tileserv    | 7800              |
| pg_featureserv | 9000              |
| TileServer-GL  | 8081              |
| pygeoapi       | 5000              |
| Martin         | 3000              |
| Tegola         | 8082              |
| MapFish Print  | 8084              |
| GeoLibre       | 8085              |

## Setup

1. Copy `.env.example` to `.env` and fill in the values (credentials, ports,
   image versions).
2. Start the stack:
   ```bash
   docker compose up -d
   ```
3. Check service health:
   ```bash
   docker compose ps
   ```

Several services define healthchecks (GeoServer, PostGIS, Solr) so their
container status reflects readiness.

## Deploying with Portainer (from GitHub)

The stack can be deployed as a Portainer **Git repository** stack:

1. In Portainer: **Stacks → Add stack → Repository**.
2. Repository URL: this repo; compose path: `docker-compose.yml`; reference the
   desired branch/tag (e.g. `main` or `6.1.0`).
3. **Environment variables:** `.env` is intentionally git-ignored (secrets stay
   out of the repo), so Portainer will not load it automatically. Add the
   variables from `.env.example` under the stack's **Environment variables**
   section — otherwise the `${...}` substitutions resolve to empty and the
   containers fail to start.
4. Deploy. Docker creates the bind-mounted `./data/*` directories on first run;
   the read-only `./config/*` files are served straight from the cloned repo.

If you connect MapStore's GeoStore to PostGIS, make sure the credentials in
`config/geostore-datasource-ovr-postgres.properties` match the values you set in
Portainer.
