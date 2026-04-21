#!/bin/bash
#
# Local development setup — gets you running in 60 seconds.
#
# Usage:
#   ./scripts/local_setup.sh
#
set -euo pipefail

echo "============================================"
echo "WoundOS Backend — Local Setup"
echo "============================================"

# 1. Copy env file
if [ ! -f .env ]; then
    cp .env.example .env
    echo "[1/4] Created .env from .env.example"
else
    echo "[1/4] .env already exists"
fi

# 2. Start PostgreSQL
echo "[2/4] Starting PostgreSQL via Docker..."
docker-compose up -d db
echo "  Waiting for PostgreSQL to be ready..."
sleep 3

# 3. Install Python dependencies
echo "[3/4] Installing Python dependencies..."
python3 -m pip install -r requirements.txt --quiet

# 4. Run migrations
echo "[4/4] Running database migrations..."
alembic upgrade head

echo ""
echo "============================================"
echo "Setup complete! Start the API with:"
echo ""
echo "  uvicorn app.main:app --reload --port 8080"
echo ""
echo "Or with Docker:"
echo ""
echo "  docker-compose up"
echo ""
echo "API docs: http://localhost:8080/docs"
echo "============================================"
