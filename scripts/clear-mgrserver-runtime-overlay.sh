#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
FILES_ROOT="${1:-$WORKSPACE_ROOT/files}"
MGR_DEST="$FILES_ROOT/root/mgrserver"
PXE_DEST="$FILES_ROOT/usr/share/mgrserver-defaults/pxe"

rm -rf "$MGR_DEST" "$PXE_DEST"

echo "Cleared MgrServer runtime overlay paths:"
echo "  $MGR_DEST"
echo "  $PXE_DEST"
