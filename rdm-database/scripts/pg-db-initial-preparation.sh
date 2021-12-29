#!/bin/bash
sudo -u postgres psql "postgresql://postgres@localhost:5432/postgres" --file=pg-db-initial-preparation.sql
