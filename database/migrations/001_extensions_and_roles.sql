-- Bioma bootstrap. This migration must run as the database administrator.
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS citext;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bio_owner') THEN
        CREATE ROLE bio_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS NOREPLICATION;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bio_app_user') THEN
        CREATE ROLE bio_app_user LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS NOREPLICATION;
    END IF;
END;
$$;

-- psql receives this value from BIO_APP_DB_PASSWORD; never commit the value itself.
ALTER ROLE bio_app_user PASSWORD :'bio_app_password';
GRANT USAGE, CREATE ON SCHEMA public TO bio_owner;
GRANT USAGE ON SCHEMA public TO bio_app_user;

