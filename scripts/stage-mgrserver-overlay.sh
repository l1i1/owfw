#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MGRSERVER_SRC="${1:-$WORKSPACE_ROOT/mgrserver-src}"
FILES_ROOT="${2:-$WORKSPACE_ROOT/files}"
CLEAR_SCRIPT="$WORKSPACE_ROOT/scripts/clear-mgrserver-runtime-overlay.sh"
MGR_DEST="$FILES_ROOT/root/mgrserver"
PXE_DEST="$FILES_ROOT/usr/share/mgrserver-defaults/pxe"
PXE_SRC="$MGRSERVER_SRC/pxe-server"

if [ ! -d "$MGRSERVER_SRC" ]; then
  echo "ERROR: MgrServer source directory not found: $MGRSERVER_SRC" >&2
  exit 1
fi

mkdir -p "$FILES_ROOT"
bash "$CLEAR_SCRIPT" "$FILES_ROOT"

cd "$MGRSERVER_SRC"

echo "Installing MgrServer dependencies..."
pnpm install --frozen-lockfile

echo "Building MgrServer..."
pnpm build

echo "Bundling MgrServer into single JS..."
pnpm --filter @mgr/server bundle:obf

echo "Staging MgrServer runtime..."
mkdir -p "$MGR_DEST"

# Copy bundled single JS
mkdir -p "$MGR_DEST/bundle"
cp packages/server/dist-bundle/index.cjs "$MGR_DEST/bundle/"

# Copy required non-bundled files
cp packages/server/commands.json "$MGR_DEST/"
[ -f packages/server/.mgrserver-first-start ] && cp packages/server/.mgrserver-first-start "$MGR_DEST/"

# Copy web dist
if [ -d packages/web/dist ]; then
  cp -r packages/web/dist "$MGR_DEST/web-dist"
else
  echo "WARNING: packages/web/dist not found" >&2
fi

cd "$MGR_DEST"

echo "MgrServer staged at: $MGR_DEST"
du -sh "$MGR_DEST"

if [ ! -d "$PXE_SRC/pxe" ]; then
  echo "ERROR: No PXE resources found at $PXE_SRC/pxe" >&2
  exit 1
fi

echo "Staging PXE resources..."
mkdir -p "$PXE_DEST"
cp -a "$PXE_SRC/pxe/." "$PXE_DEST/"

if [ -d "$PXE_SRC/util" ]; then
  mkdir -p "$PXE_DEST/util"
  find "$PXE_SRC/util" -maxdepth 1 -type f -name "*.sh" -exec cp {} "$PXE_DEST/util/" \;
fi

[ -f "$PXE_SRC/set_pxe.sh" ] && cp "$PXE_SRC/set_pxe.sh" "$PXE_DEST/"
[ -f "$PXE_SRC/up_pxe_res.sh" ] && cp "$PXE_SRC/up_pxe_res.sh" "$PXE_DEST/"

find "$PXE_DEST" -name "*.sh" -exec sed -i 's/\r$//' {} + 2>/dev/null || true
find "$PXE_DEST" -name "*.sh" -exec chmod +x {} + 2>/dev/null || true

echo "PXE resources staged at: $PXE_DEST"
du -sh "$PXE_DEST"
