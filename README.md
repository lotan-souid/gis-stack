# GIS Stack

Version: **8.0.0** · Repository: <https://github.com/lotan-souid/gis-stack>

A self-contained GIS platform delivered as a single Docker Compose stack. It
bundles a spatial database with OGC services, vector-tile and feature servers,
an administration UI, and a web map client — all wired together on one Docker
network so they can talk to each other by service name.

## Architecture

At the center of the stack is **PostGIS**, the spatial database. Almost every
other service is a consumer of that database. The tile and feature servers
connect with a **read-only role** (`gis_reader`); MapStore keeps its own
catalog in a **separate database** (`geostore`).

```
                         ┌──────────────┐
                         │   MapStore2  │  web map client (UI)
                         └──────┬───────┘
                                │
   ┌───────────┬────────────────┼───────────────┬──────────────┐
   │           │                │               │              │
┌──┴───────┐ ┌─┴───────────┐ ┌──┴──────────┐ ┌──┴──────┐ ┌─────┴──────┐
│GeoServer │ │ pg_tileserv │ │pg_feature-  │ │ Martin  │ │  pygeoapi  │
│(WMS/WFS/ │ │   (MVT)     │ │serv (OGC API│ │  (MVT)  │ │ (OGC API)  │
│ WCS/WMTS)│ │             │ │ Features)   │ │         │ │            │
└──┬───────┘ └─┬───────────┘ └──┬──────────┘ └──┬──────┘ └─────┬──────┘
   │ admin     └────────────────┴── gis_reader ─┴──────────────┘
   │                            │ (read-only)
   └────────────────────┐       │
                      ┌─┴───────┴────┐   postgis-init: one-shot job that
                      │   PostGIS    │   creates gis_reader + geostore DB
                      └──────┬───────┘
                      ┌──────┴───────┐
                      │   pgAdmin    │  database administration UI
                      └──────────────┘

   Optional profiles:  basemaps → TileServer-GL     search → Solr
```

All containers share one bridge network named `gis-network` (a fixed name, so
an external reverse-proxy container can join it — see
[Reverse proxy](#reverse-proxy)).

### Startup order

1. **postgis** starts; its healthcheck passes once it accepts TCP connections.
2. **postgis-init** runs [`config/postgis/bootstrap.sh`](config/postgis/bootstrap.sh)
   and exits. It is idempotent and runs on every `up`, so it works for new
   *and* existing databases:
   - creates/updates the read-only role `GIS_READER_USER` and grants it
     `SELECT` on all user schemas (plus default privileges for future tables);
   - creates the `GEOSTORE_DB` database owned by `GEOSTORE_USER`.
3. Services that use the database (pg_tileserv, pg_featureserv, Martin,
   pygeoapi, MapStore) start only after postgis-init **completed successfully**.

In Portainer/`docker compose ps`, postgis-init shows as *Exited (0)* — that is
expected.

## Services

### Data layer

| Service          | Role                                                                    |
| ---------------- | ----------------------------------------------------------------------- |
| **PostGIS**      | Spatial database — the source of truth for all geometry data.           |
| **postgis-init** | One-shot bootstrap job (roles, GeoStore database). Exits when done.     |
| **pgAdmin**      | Web UI for administering the PostGIS database.                          |

### OGC / API services

| Service         | Role                                                                  |
| --------------- | --------------------------------------------------------------------- |
| **GeoServer**   | Full OGC server (WMS/WFS/WCS/WMTS); publishes styled layers.          |
| **pygeoapi**    | OGC API — Features / Coverages / Tiles, driven by a YAML config.      |

### Tile & feature servers

| Service            | Role                                                          |
| ------------------ | ------------------------------------------------------------- |
| **pg_tileserv**    | Mapbox Vector Tiles straight from PostGIS tables/functions.   |
| **pg_featureserv** | GeoJSON features (OGC API — Features) from PostGIS.           |
| **Martin**         | High-performance vector-tile server for PostGIS.              |

### Client

| Service       | Role                                                    |
| ------------- | ------------------------------------------------------- |
| **MapStore2** | Web map client / portal for building and sharing maps.  |

### Optional services (Compose profiles)

Not started by default. Enable with `COMPOSE_PROFILES` (comma-separated) in
`.env` or in Portainer's environment variables, e.g.
`COMPOSE_PROFILES=basemaps,search`.

| Profile    | Service           | Role                                                        |
| ---------- | ----------------- | ----------------------------------------------------------- |
| `basemaps` | **TileServer-GL** | Raster/vector basemaps and styles from local MBTiles.       |
| `search`   | **Solr**          | Search index (`blacklight-core`, built-in `_default` configset). |

## Configuration

- **`.env`** — copied from [`.env.example`](.env.example); holds ports, image
  versions, credentials and the general settings below. Passwords are required:
  Compose refuses to start with a clear error if one is missing.
- **`config/`** — files mounted read-only into the containers:
  - `config/postgis/` — `bootstrap.sh` + `bootstrap.sql` run by postgis-init.
  - `config/pygeoapi/config.yml` — pygeoapi server and resources. `${VAR}`
    values come from the container environment; a commented example shows how
    to publish a PostGIS table with the read-only role.
- **MapStore GeoStore datasource** — generated at container start from
  `GEOSTORE_DB` / `GEOSTORE_USER` / `GEOSTORE_PASSWORD`; there is no
  credentials file to keep in sync.

### General settings

| Variable           | Default    | Purpose                                                                  |
| ------------------ | ---------- | ------------------------------------------------------------------------ |
| `COMPOSE_PROFILES` | *(empty)*  | Optional services to start (`basemaps`, `search`).                       |
| `BIND_ADDR`        | `0.0.0.0`  | Host interface for all published ports (`127.0.0.1` = this host only).   |
| `DATA_DIR`         | `./data`   | Root of persistent data. **Use an absolute path for Portainer stacks.**  |

### Memory

| Variable                                         | Default     |
| ------------------------------------------------ | ----------- |
| `GEOSERVER_INITIAL_MEMORY` / `GEOSERVER_MAX_MEMORY` | `1G` / `2G` |
| `MAPSTORE_MAX_MEMORY`                            | `1g`        |
| `SOLR_HEAP`                                      | `512m`      |

Container logs are rotated (json-file, 3 × 10 MB per service).

### Persistent data

| Path / volume                    | Contents                       |
| -------------------------------- | ------------------------------ |
| `${DATA_DIR}/postgis`            | PostgreSQL data directory      |
| `${DATA_DIR}/geoserver`          | GeoServer data dir             |
| `${DATA_DIR}/pgadmin`            | pgAdmin settings               |
| `${DATA_DIR}/tileserver-gl`      | MBTiles, styles, fonts         |
| `${DATA_DIR}/solr`               | Solr cores                     |
| volume `gis-stack-mapstore-datadir` | MapStore data dir |

Everything except MapStore is a **bind mount** under `DATA_DIR`, so the data
is a plain directory on the host, easy to back up and inspect. MapStore uses a
**named volume** because its image runs as UID 20000 and a named volume is
created with the right ownership automatically. The volume has a fixed name
(`gis-stack-mapstore-datadir`), so it does not depend on the Compose project or
Portainer stack name.

`data/` is git-ignored.

## Ports

All published on `BIND_ADDR` (defaults shown):

| Service        | Default host port |
| -------------- | ----------------- |
| GeoServer      | 8090              |
| MapStore2      | 8091              |
| PostGIS        | 5433              |
| pgAdmin        | 5050              |
| pg_tileserv    | 7800              |
| pg_featureserv | 9000              |
| pygeoapi       | 5000              |
| Martin         | 3000              |
| TileServer-GL  | 8081 *(profile `basemaps`)* |
| Solr           | 8983 *(profile `search`)*   |

## Setup

1. Copy `.env.example` to `.env` and set real passwords.
2. Start the stack:
   ```bash
   docker compose up -d
   ```
3. Check status:
   ```bash
   docker compose ps
   docker compose logs postgis-init   # should end with "bootstrap: done"
   ```

Healthchecks: PostGIS, GeoServer, pygeoapi, MapStore and Solr (defined here);
Martin and TileServer-GL (built into their images). pg_tileserv and
pg_featureserv ship minimal images without a shell, so they have none.

### MapStore admin

The first admin account is taken from `MAPSTORE_ADMIN_USER` /
`MAPSTORE_ADMIN_PASSWORD` (the built-in `admin`/`admin` and `user`/`user`
accounts are not created). GeoStore creates it **only on the first start**, while
its user table is empty. Changing these variables later has no effect: change
the password in MapStore (*Manage Accounts*) instead. To re-create the account
from `.env`, drop and recreate the `geostore` database (this deletes all
MapStore maps and users).

## Reverse proxy

The stack does **not** include its own reverse proxy: put it behind the
reverse proxy you already run, with TLS terminated there. Two ways to connect:

- **Proxy on another host** (the usual home-lab setup): proxy to
  `http://<docker-host-ip>:<port>` for each service, using the host ports in the
  [Ports](#ports) table. Keep `BIND_ADDR=0.0.0.0` (or the Docker host's LAN IP).
  Recommended: allow the web ports only from the proxy's IP in the Docker
  host's firewall, so clients must go through the proxy. Note that Docker's
  published ports bypass `ufw`'s default rules; filter them in the
  `DOCKER-USER` iptables chain (or the router/VLAN firewall) instead.
- **Proxy as a container on the same Docker host:** attach the proxy container
  to the external network `gis-network` and proxy to `http://<service>:<container-port>`
  (e.g. `http://geoserver:8080`, `http://martin:3000`). Then set
  `BIND_ADDR=127.0.0.1` so nothing is exposed on the LAN.

Behind a proxy, set `PYGEOAPI_SERVER_URL` to pygeoapi's public URL, and
configure GeoServer's *Proxy Base URL* (Global settings) — otherwise both return
links with internal addresses.

Do not publish PostGIS (5433) or Solr (8983) through the proxy: they have no
web authentication of their own.

## Deploying with Portainer (from GitHub)

1. In Portainer: **Stacks → Add stack → Repository**.
2. Repository URL: `https://github.com/lotan-souid/gis-stack`; compose path:
   `docker-compose.yml`. Reference either `refs/heads/main` (latest) or a
   release tag such as `refs/tags/8.0.0` (pinned, recommended for production).
3. **Environment variables:** `.env` is git-ignored, so Portainer does not load
   it. Add the variables from `.env.example` under the stack's **Environment
   variables** section, and set `DATA_DIR` to an absolute host path
   (e.g. `/srv/gis-stack/data`) so data does not live inside Portainer's clone
   of the repository.
4. Deploy. The `./config/*` files are served from the cloned repo.

## Upgrading from 7.x to 8.0.0

1. **Add the new variables** (see `.env.example`): `GIS_READER_USER`,
   `GIS_READER_PASSWORD`, `GEOSTORE_DB`, `GEOSTORE_USER`, `GEOSTORE_PASSWORD`,
   `MAPSTORE_ADMIN_USER`, `MAPSTORE_ADMIN_PASSWORD`, and optionally `DATA_DIR`, `BIND_ADDR`, `COMPOSE_PROFILES`, memory settings.
   Remove `TEGOLA_*` and `MAPFISH_*`.
2. **Keep your data path.** For Portainer, point `DATA_DIR` at the directory
   that currently holds `postgis/`, `geoserver/`, … (or move it there first).
3. **TileServer-GL / Solr** now start only with their profile — set
   `COMPOSE_PROFILES=basemaps,search` if you use them.
4. **MapStore maps** from 7.x (if MapStore used PostGIS) are in `gisdb`, tables
   `gs_*`. 8.0.0 uses the new `geostore` database, so MapStore would start
   empty. To keep existing maps, copy the tables **before MapStore's first
   8.0.0 start**:
   ```bash
   docker compose up -d postgis postgis-init
   docker compose exec postgis sh -c \
     'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t "gs_*" -t hibernate_sequence \
        --no-owner --no-privileges | psql -U geostore -d geostore'
   docker compose up -d
   ```
   (Use your `GEOSTORE_USER`/`GEOSTORE_DB` if you changed them.) Once MapStore
   shows your maps, drop the `gs_*` tables from `gisdb`.
5. **TileServer-GL port** fix: the container listens on 8080 (7.x mapped to 80,
   which did not reach it).

## Versioning

The project follows [Semantic Versioning](https://semver.org/)
(`MAJOR.MINOR.PATCH`):

- **MAJOR** — breaking changes: a service is removed or renamed, a port or
  environment variable changes meaning, or data/config layout changes.
- **MINOR** — backwards-compatible additions (a new service, new options).
- **PATCH** — fixes (image tags, healthchecks, config corrections).

The current version is recorded in three places, which must always match
(checked by CI):

| Location                                                        | Form    |
| --------------------------------------------------------------- | ------- |
| `VERSION`                                                       | `8.0.0` |
| `docker-compose.yml` (header comment and `x-gis-stack-version`) | `8.0.0` |
| `README.md` (top of file)                                       | `8.0.0` |

`x-gis-stack-version` is a Compose extension field: Docker Compose ignores it,
but it shows which stack version a deployment came from (e.g. in Portainer's
stack editor or `docker compose config`).

### Branches and tags

- **`main`** — the single long-lived branch; always holds the latest version.
- **Tags** (`6.0.0`, `6.1.2`, `7.0.0`, `8.0.0`, …) — one annotated tag per
  release. Deploy from a tag to pin a version.

### Automation

- **CI** ([`.github/workflows/validate.yml`](.github/workflows/validate.yml)) —
  on every push: validates the compose file with all profiles, checks the
  three version strings match, and syntax-checks the bootstrap script.
- **Renovate** ([`renovate.json`](renovate.json)) — opens PRs for new image
  versions in `.env.example` (each `*_VERSION` line is annotated with a
  `# renovate:` comment). Major upgrades wait for approval in the dependency
  dashboard. Requires the [Renovate GitHub App](https://github.com/apps/renovate)
  to be installed on the repository.

### Releasing a new version

1. Update the version in `VERSION`, `docker-compose.yml` and `README.md`, and
   add an entry to the changelog below.
2. Commit on `main`, then tag and push:
   ```bash
   git tag -a X.Y.Z -m "GIS Stack X.Y.Z — <summary>"
   git push origin main X.Y.Z
   ```

## Changelog

### 8.0.0
- **Breaking:** removed **Tegola** (overlaps pg_tileserv/Martin) and
  **MapFish Print** (unused; MapStore has its own printing).
- **Breaking:** TileServer-GL and Solr moved to optional profiles
  (`basemaps`, `search`).
- **Breaking:** new required variables for the read-only role and the
  GeoStore database (see [Upgrading](#upgrading-from-7x-to-800)).
- Security: tile/feature servers connect as read-only `gis_reader`; MapStore's
  GeoStore uses its own database and role; initial MapStore admin from `.env`
  (no default `admin`/`admin`); no credentials in committed files;
  `BIND_ADDR` to limit published ports.
- Reliability: `postgis-init` bootstrap job; services wait for a healthy
  database; new healthchecks (pygeoapi, MapStore); start periods; memory
  settings for GeoServer, MapStore and Solr; log rotation.
- Fixes: pygeoapi config completed (was missing required sections); Solr uses
  the built-in configset (the mounted `solr_conf/` was empty); MapStore keeps
  its default data dir (was dropped by the `JAVA_OPTS` override);
  TileServer-GL container port corrected (80 → 8080).
- `DATA_DIR` for the data location; fixed names for the network
  (`gis-network`) and the MapStore volume (`gis-stack-mapstore-datadir`).
- Compose file uses shared YAML anchors (`x-common`, …).
- CI workflow, Renovate config, `.gitattributes` (LF line endings).

### 7.0.0
- **Breaking:** GeoLibre service removed (it was added in 6.1.0). Its port and
  environment variables are no longer used; `data/geolibre/` can be deleted.
- Stack version is now tracked inside `docker-compose.yml`
  (`x-gis-stack-version`).
- Repository consolidated: `main` is the main branch, releases are tags.

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
