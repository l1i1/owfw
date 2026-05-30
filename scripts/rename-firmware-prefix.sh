#!/usr/bin/env bash
set -euo pipefail

FIRMWARE_DIR="${1:-}"
FROM_PREFIX="${2:-immortalwrt}"
TO_PREFIX="${3:-yushu_router}"

if [ -z "$FIRMWARE_DIR" ]; then
  echo "ERROR: firmware directory is required" >&2
  exit 1
fi

if [ ! -d "$FIRMWARE_DIR" ]; then
  echo "ERROR: firmware directory does not exist: $FIRMWARE_DIR" >&2
  exit 1
fi

cd "$FIRMWARE_DIR"

renamed=0
while IFS= read -r -d '' path; do
  name="${path#./}"
  new_name="${TO_PREFIX}${name#"$FROM_PREFIX"}"

  if [ "$name" = "$new_name" ]; then
    continue
  fi

  if [ -e "$new_name" ]; then
    echo "ERROR: refusing to overwrite existing firmware artifact: $new_name" >&2
    exit 1
  fi

  mv -- "$name" "$new_name"
  echo "Renamed firmware artifact: $name -> $new_name"
  renamed=$((renamed + 1))
done < <(find . -maxdepth 1 -type f -name "${FROM_PREFIX}-*" -print0 | sort -z)

if [ "$renamed" -eq 0 ]; then
  echo "No firmware artifacts with prefix '$FROM_PREFIX-' found in $FIRMWARE_DIR"
fi

while IFS= read -r -d '' metadata; do
  if grep -q "$FROM_PREFIX-" "$metadata"; then
    sed -i "s/${FROM_PREFIX}-/${TO_PREFIX}-/g" "$metadata"
    echo "Updated firmware metadata references: ${metadata#./}"
  fi
done < <(find . -maxdepth 1 -type f \( -name '*.json' -o -name '*.txt' -o -name '*.sha256sums' \) -print0)
