#!/bin/sh

set -eu

echo
echo Resetting database

psql <<SQL
SELECT 'CREATE DATABASE gleam_pog_test'
WHERE NOT EXISTS (
  SELECT FROM pg_database WHERE datname = 'gleam_pog_test'
)\\gexec
SQL

psql -v "ON_ERROR_STOP=1" -d gleam_pog_test <<SQL
DROP TABLE IF EXISTS cats;
CREATE TABLE cats (
  id SERIAL PRIMARY KEY,
  name VARCHAR(50) NOT NULL,
  is_cute boolean NOT NULL DEFAULT true,
  colors VARCHAR(50)[] NOT NULL,
  last_petted_at TIMESTAMP NOT NULL,
  birthday DATE NOT NULL
);
SQL

echo Done
echo
