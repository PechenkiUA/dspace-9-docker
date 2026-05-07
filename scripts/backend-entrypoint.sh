#!/bin/bash
set -euo pipefail

DSPACE_HOME="${DSPACE_DIR:-/dspace}"
INSTALLER_DIR="/dspace-installer"
# Marker lives in the persistent assetstore volume — survives restarts
MARKER="${DSPACE_HOME}/assetstore/.initialized"

# ─── Helpers ──────────────────────────────────────────────────────────────────
generate_local_cfg() {
    local dest="${1}"
    cat > "${dest}" << EOF
dspace.dir         = ${DSPACE_HOME}
dspace.server.url  = ${DSPACE_SERVER_URL:-http://localhost:8080/server}
dspace.ui.url      = ${DSPACE_UI_URL:-http://localhost:4000}
dspace.name        = ${DSPACE_NAME:-DSpace Repository}

db.url             = jdbc:postgresql://${DB_HOST:-db}:${DB_PORT:-5432}/${DB_NAME:-dspace}
db.username        = ${DB_USER:-dspace}
db.password        = ${DB_PASS:-dspace}
db.maxConnections  = 30

solr.server        = http://${SOLR_HOST:-solr}:${SOLR_PORT:-8983}/solr

rest.cors.allowed-origins = ${DSPACE_UI_URL:-http://localhost}, http://localhost:${FRONTEND_PORT:-80}
EOF
}

# ─── First-time install (needs live DB + Solr) ────────────────────────────────
if [ ! -f "${MARKER}" ]; then
    echo "[entrypoint] First startup — running ant fresh_install (DB + Solr must be ready)..."

    mkdir -p "${DSPACE_HOME}"

    # Write real connection settings into installer so Ant can migrate the DB
    generate_local_cfg "${INSTALLER_DIR}/config/local.cfg"

    ant -f "${INSTALLER_DIR}/build.xml" fresh_install

    # Hand ownership of the installed tree to the app user
    chown -R dspace:dspace "${DSPACE_HOME}"

    echo "[entrypoint] ant fresh_install complete."
fi

# ─── Always (re)write local.cfg — env vars may change between restarts ─────────
mkdir -p "${DSPACE_HOME}/config"
generate_local_cfg "${DSPACE_HOME}/config/local.cfg"
chown dspace:dspace "${DSPACE_HOME}/config/local.cfg"

# ─── Database migration (idempotent; also covers schema updates) ───────────────
echo "[entrypoint] Running database migration..."
gosu dspace "${DSPACE_HOME}/bin/dspace" database migrate
echo "[entrypoint] Database migration complete."

# ─── Create administrator (once, after fresh install) ─────────────────────────
if [ ! -f "${MARKER}" ]; then
    if [ -n "${DSPACE_ADMIN_EMAIL:-}" ] && [ -n "${DSPACE_ADMIN_PASS:-}" ]; then
        echo "[entrypoint] Creating administrator: ${DSPACE_ADMIN_EMAIL}"
        gosu dspace "${DSPACE_HOME}/bin/dspace" create-administrator \
            -e "${DSPACE_ADMIN_EMAIL}" \
            -f "${DSPACE_ADMIN_FIRSTNAME:-DSpace}" \
            -l "${DSPACE_ADMIN_LASTNAME:-Admin}" \
            -p "${DSPACE_ADMIN_PASS}" \
            -c en \
            || echo "[entrypoint] Admin already exists — skipping."
    fi
    # Mark as initialized only after everything succeeded
    mkdir -p "$(dirname "${MARKER}")"
    touch "${MARKER}"
fi

# ─── Start DSpace REST API ─────────────────────────────────────────────────────
echo "[entrypoint] Starting DSpace REST API on :8080..."
exec gosu dspace java ${JAVA_OPTS:--Xmx2g -Xms512m -Dfile.encoding=UTF-8} \
    -jar "${DSPACE_HOME}/webapps/server-boot.jar" \
    --dspace.dir="${DSPACE_HOME}"
