# GIS Stack

Version: **7.0.0** · Repository: <https://github.com/lotan-souid/gis-stack>

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
| **Solr**         | Search index (e.g. Blacklight core) for catalog/metadata search.        |
| **MapFish Print**| Print/report generation service for producing PDF maps.                 |

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
  dir, Solr, pgAdmin, TileServer-GL, …). This directory is git-ignored.

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
2. Repository URL: `https://github.com/lotan-souid/gis-stack`; compose path:
   `docker-compose.yml`. Reference either `refs/heads/main` (latest) or a
   release tag such as `refs/tags/7.0.0` (pinned, recommended for production).
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

## Versioning

The project follows [Semantic Versioning](https://semver.org/)
(`MAJOR.MINOR.PATCH`):

- **MAJOR** — breaking changes: a service is removed or renamed, a port or
  environment variable changes meaning, or data/config layout changes.
- **MINOR** — backwards-compatible additions (a new service, new options).
- **PATCH** — fixes (image tags, healthchecks, config corrections).

The current version is recorded in three places, which must always match:

| Location                              | Form                              |
| ------------------------------------- | --------------------------------- |
| `VERSION`                             | `7.0.0`                           |
| `docker-compose.yml` (header comment and `x-gis-stack-version`) | `7.0.0` |
| `README.md` (top of file)             | `7.0.0`                           |

`x-gis-stack-version` is a Compose extension field: Docker Compose ignores it,
but it lets you see which stack version a deployment came from (e.g. in
Portainer's stack editor or `docker compose config`).

### Branches and tags

- **`main`** — the single long-lived branch; always holds the latest version.
- **Tags** (`6.0.0`, `6.1.2`, `7.0.0`, …) — one annotated tag per release.
  Deploy from a tag to pin a version.

### Releasing a new version

1. Update the version in `VERSION`, `docker-compose.yml` and `README.md`, and
   add an entry to the changelog below.
2. Commit on `main`, then tag and push:
   ```bash
   git tag -a X.Y.Z -m "GIS Stack X.Y.Z — <summary>"
   git push origin main X.Y.Z
   ```

## Changelog

### 7.0.0
- **Breaking:** GeoLibre service removed (it was added in 6.1.0). Its port and
  environment variables are no longer used; `data/geolibre/` can be deleted.
- Stack version is now tracked inside `docker-compose.yml`
  (`x-gis-stack-version`).
- Repository consolidated: `main` is the only branch, releases are tags.

### 6.1.2
- Fix GeoLibre image tag (ghcr uses a `v` prefix).

### 6.1.1
- Harden the stack for Portainer Git deployment.

### 6.1.0
- Add GeoLibre service; expand README with architecture.

### 6.0.1
- Add `.gitignore` and README.

### 6.0.0
- Initial Compose stack: PostGIS, GeoServer, MapStore2, pgAdmin, Solr,
  pg_tileserv, pg_featureserv, TileServer-GL, pygeoapi, Martin, Tegola,
  MapFish Print.
