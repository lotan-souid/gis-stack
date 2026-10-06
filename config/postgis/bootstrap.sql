-- Executed by bootstrap.sh with psql variables:
--   db, owner, reader, reader_pw, geostore_db, geostore_user, geostore_pw
-- Every statement is idempotent.

CREATE EXTENSION IF NOT EXISTS postgis;

-- ------------------------------------------------------------------------
-- Read-only role for pg_tileserv / pg_featureserv / Martin / pygeoapi
-- ------------------------------------------------------------------------
SELECT format('CREATE ROLE %I LOGIN', :'reader')
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'reader') \gexec
ALTER ROLE :"reader" WITH LOGIN PASSWORD :'reader_pw';

GRANT CONNECT ON DATABASE :"db" TO :"reader";

-- Existing user schemas: read access to everything already there.
-- Extension schemas (TIGER geocoder, topology) are not published.
SELECT format('GRANT USAGE ON SCHEMA %I TO %I', nspname, :'reader'),
       format('GRANT SELECT ON ALL TABLES IN SCHEMA %I TO %I', nspname, :'reader')
  FROM pg_namespace
 WHERE nspname NOT LIKE 'pg\_%'
   AND nspname NOT IN ('information_schema', 'tiger', 'tiger_data', 'topology') \gexec
SELECT format('REVOKE ALL ON ALL TABLES IN SCHEMA %I FROM %I', nspname, :'reader'),
       format('REVOKE USAGE ON SCHEMA %I FROM %I', nspname, :'reader')
  FROM pg_namespace
 WHERE nspname IN ('tiger', 'tiger_data', 'topology') \gexec

-- Tables the owner creates later are readable too. (A schema created later
-- gets USAGE on the next `up`, when this script runs again.)
ALTER DEFAULT PRIVILEGES FOR ROLE :"owner" GRANT SELECT ON TABLES TO :"reader";

-- ------------------------------------------------------------------------
-- MapStore GeoStore: own role + own database, kept apart from GIS data
-- ------------------------------------------------------------------------
SELECT format('CREATE ROLE %I LOGIN', :'geostore_user')
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'geostore_user') \gexec
ALTER ROLE :"geostore_user" WITH LOGIN PASSWORD :'geostore_pw';

SELECT format('CREATE DATABASE %I OWNER %I', :'geostore_db', :'geostore_user')
 WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'geostore_db') \gexec
REVOKE CONNECT ON DATABASE :"geostore_db" FROM PUBLIC;
GRANT CONNECT ON DATABASE :"geostore_db" TO :"geostore_user";
