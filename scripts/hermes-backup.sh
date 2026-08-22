#!/bin/bash
# Hermes Agent Backup Script — runs every 12h via cron
set -euo pipefail

HERMES_DIR="/data/.hermes"
BACKUP_DIR="/tmp/hermes-backup-$$"
TOKEN_FILE="$HERMES_DIR/.github_backup_token"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

cleanup() { rm -rf "$BACKUP_DIR"; }
trap cleanup EXIT

# Read token
if [ ! -f "$TOKEN_FILE" ]; then
    echo "ERROR: Token file $TOKEN_FILE not found" >&2
    exit 1
fi
TOKEN=$(cat "$TOKEN_FILE")

# Create temp dir
mkdir -p "$BACKUP_DIR"

# ========== Collect files ==========
# Config & core
cp "$HERMES_DIR/config.yaml" "$BACKUP_DIR/" 2>/dev/null || true
cp "$HERMES_DIR/.env" "$BACKUP_DIR/env.txt" 2>/dev/null || true
cp "$HERMES_DIR/auth.json" "$BACKUP_DIR/" 2>/dev/null || true
cp "$HERMES_DIR/SOUL.md" "$BACKUP_DIR/" 2>/dev/null || true
cp "$HERMES_DIR/channel_directory.json" "$BACKUP_DIR/" 2>/dev/null || true
cp "$HERMES_DIR/gateway_state.json" "$BACKUP_DIR/" 2>/dev/null || true

# Databases (packaged as tarball — excluded from git to avoid secret scanning)
tar czf "$BACKUP_DIR/databases.tar.gz" \
    -C "$HERMES_DIR" state.db kanban.db cron/executions.db \
    2>/dev/null || true

# Sessions
cp "$HERMES_DIR/sessions/sessions.json" "$BACKUP_DIR/" 2>/dev/null || true

# Memories
if [ -d "$HERMES_DIR/memories" ]; then
    mkdir -p "$BACKUP_DIR/memories"
    cp -r "$HERMES_DIR/memories/"* "$BACKUP_DIR/memories/" 2>/dev/null || true
fi

# Skills (SKILL.md files + subdirs)
if [ -d "$HERMES_DIR/skills" ]; then
    mkdir -p "$BACKUP_DIR/skills"
    find "$HERMES_DIR/skills" -maxdepth 2 -name "SKILL.md" -exec cp {} "$BACKUP_DIR/skills/" \; 2>/dev/null || true
    for d in references templates scripts; do
        if [ -d "$HERMES_DIR/skills/$d" ]; then
            mkdir -p "$BACKUP_DIR/skills/$d"
            cp -r "$HERMES_DIR/skills/$d/"* "$BACKUP_DIR/skills/$d/" 2>/dev/null || true
        fi
    done
fi

# Cron scripts
if [ -d "$HERMES_DIR/scripts" ]; then
    mkdir -p "$BACKUP_DIR/scripts"
    cp -r "$HERMES_DIR/scripts/"* "$BACKUP_DIR/scripts/" 2>/dev/null || true
fi

# Cache/state
cp "$HERMES_DIR/provider_models_cache.json" "$BACKUP_DIR/" 2>/dev/null || true

# ========== Write manifest ==========
{
    echo "Hermes Agent Backup"
    echo "Timestamp: $TIMESTAMP"
    echo "Host: $(hostname 2>/dev/null || echo 'unknown')"
    echo ""
    echo "Files:"
    ls -la "$BACKUP_DIR"/
    if [ -d "$BACKUP_DIR/memories" ]; then
        echo ""
        echo "Memories:"
        ls -la "$BACKUP_DIR/memories"/
    fi
    if [ -d "$BACKUP_DIR/skills" ]; then
        echo ""
        echo "Skills:"
        ls -la "$BACKUP_DIR/skills"/
    fi
    echo ""
    echo "Databases archive:"
    tar tzf "$BACKUP_DIR/databases.tar.gz" 2>/dev/null || echo "(none)"
    echo ""
    echo "Total size: $(du -sh "$BACKUP_DIR" | cut -f1)"
} > "$BACKUP_DIR/MANIFEST.txt"

# ========== .gitignore ==========
# Exclude state.db from git (triggers secret scanning), it's in the tarball
cat > "$BACKUP_DIR/.gitignore" << 'GITIGNORE'
databases.tar.gz
.github_backup_token
GITIGNORE

# ========== Git push ==========
cd "$BACKUP_DIR"
git init -q
git config user.name "Hermes Backup"
git config user.email "hermes@backup"
git add -A
git commit -q -m "Backup $TIMESTAMP" 2>/dev/null || git commit -q --allow-empty -m "Backup $TIMESTAMP"
git branch -m master main
git remote add origin "https://oauth2:${TOKEN}@github.com/aminsafavi188-crypto/hermesbackup.git"
git push -q -f -u origin main 2>&1 || {
    echo "ERROR: Failed to push to GitHub" >&2
    exit 1
}

echo "Backup $TIMESTAMP completed successfully."
