#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
FIRMWARE_DIR="${1:-${FIRMWARE:-}}"
EXPECTED_FACTORY_SQUASHFS_OFFSET=6291456

if [ -z "$FIRMWARE_DIR" ]; then
  echo "ERROR: firmware directory is required"
  exit 1
fi

ROOTFS_TMP=""
FACTORY_ROOTFS_TMP=""
FACTORY_HEADER_TMP=""

cleanup() {
  if [ -n "$ROOTFS_TMP" ] && [ -d "$ROOTFS_TMP" ]; then
    rm -rf "$ROOTFS_TMP"
  fi
  if [ -n "$FACTORY_ROOTFS_TMP" ] && [ -d "$FACTORY_ROOTFS_TMP" ]; then
    rm -rf "$FACTORY_ROOTFS_TMP"
  fi
  if [ -n "$FACTORY_HEADER_TMP" ] && [ -d "$FACTORY_HEADER_TMP" ]; then
    rm -rf "$FACTORY_HEADER_TMP"
  fi
}
trap cleanup EXIT

cd "$FIRMWARE_DIR"

echo "============================================"
echo "Verifying firmware files..."
echo "============================================"

SYSUPGRADE=$(find . -name "*squashfs-sysupgrade.bin" | head -1)
if [ -n "$SYSUPGRADE" ]; then
  SIZE=$(stat -c%s "$SYSUPGRADE" 2>/dev/null || stat -f%z "$SYSUPGRADE" 2>/dev/null)
  SIZE_MB=$((SIZE / 1024 / 1024))
  echo "✓ sysupgrade.bin found: $SYSUPGRADE ($SIZE_MB MB)"
  if [ "$SIZE_MB" -lt 10 ]; then
    echo "✗ ERROR: sysupgrade.bin is too small ($SIZE_MB MB), expected >10MB"
    exit 1
  fi
else
  echo "✗ ERROR: sysupgrade.bin not found!"
  exit 1
fi

FACTORY=$(find . -name "*squashfs-factory.bin" | head -1)
if [ -n "$FACTORY" ]; then
  SIZE=$(stat -c%s "$FACTORY" 2>/dev/null || stat -f%z "$FACTORY" 2>/dev/null)
  SIZE_MB=$((SIZE / 1024 / 1024))
  echo "✓ factory.bin found: $FACTORY ($SIZE_MB MB)"
  if [ "$SIZE_MB" -lt 10 ]; then
    echo "✗ ERROR: factory.bin is too small ($SIZE_MB MB), expected >10MB"
    exit 1
  fi
else
  echo "✗ ERROR: factory.bin not found!"
  echo "  Expected: immortalwrt-qualcommax-ipq60xx-jdcloud_re-ss-01-squashfs-factory.bin"
  exit 1
fi

INITRAMFS=$(find . -name "*initramfs-uImage.itb" | head -1)
if [ -n "$INITRAMFS" ]; then
  SIZE=$(stat -c%s "$INITRAMFS" 2>/dev/null || stat -f%z "$INITRAMFS" 2>/dev/null)
  SIZE_MB=$((SIZE / 1024 / 1024))
  echo "✓ initramfs found: $INITRAMFS ($SIZE_MB MB)"
else
  echo "⚠ WARNING: initramfs not found"
fi

MANIFEST=$(find . -name "*.manifest" | head -1)
CONFIG_BUILDINFO=$(find . -name "config.buildinfo" | head -1)
PROFILES_JSON=$(find . -name "profiles.json" | head -1)

for file in "$MANIFEST" "$CONFIG_BUILDINFO" "$PROFILES_JSON"; do
  if [ -z "$file" ] || [ ! -f "$file" ]; then
    echo "✗ ERROR: required metadata file missing"
    exit 1
  fi
done

require_build_config() {
  local pattern="$1"
  if grep -qx "$pattern" "$CONFIG_BUILDINFO"; then
    echo "✓ build config present: $pattern"
  else
    echo "✗ Missing build config: $pattern"
    exit 1
  fi
}

require_manifest_pkg() {
  local pkg="$1"
  if grep -q "^${pkg} - " "$MANIFEST"; then
    echo "✓ manifest package present: $pkg"
  else
    echo "✗ Missing manifest package: $pkg"
    exit 1
  fi
}

compute_file_sha256() {
  python3 - "$1" <<'PY'
import hashlib
import sys

h = hashlib.sha256()
with open(sys.argv[1], "rb") as f:
    for chunk in iter(lambda: f.read(1024 * 1024), b""):
        h.update(chunk)
print(h.hexdigest())
PY
}

require_build_config "CONFIG_PACKAGE_node=y"
require_build_config "CONFIG_PACKAGE_node-npm=y"
require_build_config "CONFIG_PACKAGE_python3=y"
require_build_config "CONFIG_PACKAGE_kmod-tun=y"
require_build_config "CONFIG_PACKAGE_kmod-inet-diag=y"
require_build_config "CONFIG_PACKAGE_kmod-nft-queue=y"
require_build_config "CONFIG_PACKAGE_luci-compat=y"
require_build_config "CONFIG_PACKAGE_parted=y"
require_build_config "CONFIG_PACKAGE_f2fs-tools=y"
require_build_config "CONFIG_PACKAGE_kmod-fs-f2fs=y"
require_build_config "CONFIG_PACKAGE_hostapd-utils=y"
require_build_config "CONFIG_PACKAGE_miniupnpd-nftables=y"

require_manifest_pkg "node127"
require_manifest_pkg "node-npm"
require_manifest_pkg "python3"
require_manifest_pkg "luci"
require_manifest_pkg "kmod-tun"
require_manifest_pkg "kmod-inet-diag"
require_manifest_pkg "kmod-nft-queue"
require_manifest_pkg "luci-compat"
require_manifest_pkg "parted"
require_manifest_pkg "f2fs-tools"
require_manifest_pkg "kmod-fs-f2fs"
require_manifest_pkg "hostapd-utils"
require_manifest_pkg "miniupnpd-nftables"
require_manifest_pkg "wimlib"

if grep -q '^kmod-qca-nss-dp - ' "$MANIFEST"; then
  if [ -n "${GITHUB_ENV:-}" ]; then
    echo "HAS_QCA_NSS_DP=true" >> "$GITHUB_ENV"
  fi
  echo "✓ manifest package present: kmod-qca-nss-dp"
else
  if [ -n "${GITHUB_ENV:-}" ]; then
    echo "HAS_QCA_NSS_DP=false" >> "$GITHUB_ENV"
  fi
  echo "⚠ qca-nss-dp not present in manifest; release notes will omit acceleration claim"
fi

find_rootfs_stage() {
  local candidate
  for candidate in $(find "$WORKSPACE_ROOT/openwrt/build_dir" -mindepth 2 -maxdepth 3 -type d -name "root-*" ! -name "root.orig-*" 2>/dev/null); do
    if [ -f "$candidate/etc/openwrt_release" ]; then
      echo "$candidate"
      return 0
    fi
  done
  for candidate in $(find "$WORKSPACE_ROOT/openwrt/build_dir" -mindepth 2 -maxdepth 3 -type d -name "root.orig-*" 2>/dev/null); do
    if [ -f "$candidate/etc/openwrt_release" ]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

extract_rootfs_image() {
  local image_path="$1"
  local workdir="$2"
  local normalized_image="$image_path"
  local list_file="$workdir/rootfs.list"
  local squashfs_meta=""
  local squashfs_magic=""
  local squashfs_bytes_used=""
  local squashfs_file_size=""

  squashfs_meta=$(python3 -c 'import os, struct, sys; p=sys.argv[1]; f=open(p, "rb"); hdr=f.read(48); f.close(); magic=hdr[:4].hex() if len(hdr) >= 4 else ""; bytes_used=struct.unpack_from("<Q", hdr, 40)[0] if len(hdr) >= 48 else 0; print(magic, bytes_used, os.path.getsize(p))' "$image_path" 2>/dev/null) || squashfs_meta=""
  set -- $squashfs_meta
  squashfs_magic="$1"
  squashfs_bytes_used="$2"
  squashfs_file_size="$3"

  if [ "$squashfs_magic" != "68737173" ] || [ -z "$squashfs_bytes_used" ] || [ -z "$squashfs_file_size" ]; then
    echo "✗ ERROR: rootfs image is not a readable squashfs payload: $image_path" >&2
    return 1
  fi

  if [ "$squashfs_file_size" -lt "$squashfs_bytes_used" ]; then
    echo "✗ ERROR: squashfs payload is truncated ($squashfs_file_size < $squashfs_bytes_used): $image_path" >&2
    return 1
  fi

  if [ "$squashfs_file_size" -gt "$squashfs_bytes_used" ]; then
    normalized_image="$workdir/rootfs.normalized.squashfs"
    echo "Trimming squashfs payload from $squashfs_file_size to $squashfs_bytes_used bytes before verification..."
    if ! head -c "$squashfs_bytes_used" "$image_path" > "$normalized_image"; then
      echo "✗ ERROR: failed to normalize squashfs payload: $image_path" >&2
      return 1
    fi
  fi

  if ! unsquashfs -ll "$normalized_image" > "$list_file" 2>/dev/null; then
    echo "✗ ERROR: failed to enumerate squashfs rootfs image: $image_path" >&2
    return 1
  fi
  ROOTFS_VIEW="$normalized_image"
  ROOTFS_LIST_FILE="$list_file"
  ROOTFS_SHA256=$(compute_file_sha256 "$normalized_image")
  ROOTFS_VIEW_DESC="squashfs rootfs image"
  return 0
}

extract_sysupgrade_rootfs() {
  local sysupgrade_path="$1"
  local workdir="$2"
  local sysupgrade_dir="$workdir/sysupgrade"
  local root_candidate=""
  local root_member=""
  local magic=""

  mkdir -p "$sysupgrade_dir"

  echo "Attempting tar extraction for sysupgrade rootfs payload..."
  if ! tar -tf "$sysupgrade_path" >/dev/null 2>&1; then
    echo "✗ ERROR: failed to read sysupgrade archive: $sysupgrade_path" >&2
    return 1
  fi

  root_member=$(tar -tf "$sysupgrade_path" | grep -E '(^|/)(root|.*rootfs.*|.*\.squashfs)$' | head -1)
  if [ -z "$root_member" ]; then
    echo "✗ ERROR: unable to find rootfs payload inside sysupgrade archive" >&2
    tar -tf "$sysupgrade_path" | sed 's#^#  archive: #' >&2
    return 1
  fi

  root_candidate="$sysupgrade_dir/rootfs.bin"
  if ! tar -xOf "$sysupgrade_path" "$root_member" > "$root_candidate"; then
    echo "✗ ERROR: failed to stream rootfs payload from sysupgrade archive: $root_member" >&2
    return 1
  fi

  magic=$(dd if="$root_candidate" bs=4 count=1 2>/dev/null | od -An -t x1 | tr -d ' \n')
  if [ "$magic" != "68737173" ]; then
    echo "✗ ERROR: sysupgrade rootfs payload is not squashfs (magic=$magic): $root_member" >&2
    return 1
  fi

  if ! extract_rootfs_image "$root_candidate" "$workdir"; then
    echo "✗ ERROR: extracted sysupgrade rootfs could not be unsquashed: $root_member" >&2
    return 1
  fi

  ROOTFS_VIEW_DESC="sysupgrade squashfs rootfs"
  return 0
}

extract_sysupgrade_kernel() {
  local sysupgrade_path="$1"
  local out_path="$2"
  local kernel_member=""

  if ! tar -tf "$sysupgrade_path" >/dev/null 2>&1; then
    echo "✗ ERROR: failed to read sysupgrade archive while extracting kernel: $sysupgrade_path" >&2
    return 1
  fi

  kernel_member=$(tar -tf "$sysupgrade_path" | grep -E '(^|/)(kernel|.*kernel.*|.*\.itb)$' | head -1)
  if [ -z "$kernel_member" ]; then
    echo "✗ ERROR: unable to find kernel payload inside sysupgrade archive" >&2
    tar -tf "$sysupgrade_path" | sed 's#^#  archive: #' >&2
    return 1
  fi

  if ! tar -xOf "$sysupgrade_path" "$kernel_member" > "$out_path"; then
    echo "✗ ERROR: failed to stream kernel payload from sysupgrade archive: $kernel_member" >&2
    return 1
  fi

  if [ ! -s "$out_path" ]; then
    echo "✗ ERROR: extracted sysupgrade kernel payload is empty: $kernel_member" >&2
    return 1
  fi

  return 0
}

extract_factory_rootfs() {
  local factory_path="$1"
  local workdir="$2"
  local root_candidate="$workdir/rootfs.bin"
  local squashfs_offset=""

  squashfs_offset=$(python3 -c 'import pathlib, sys; data = pathlib.Path(sys.argv[1]).read_bytes(); print(data.find(b"hsqs"))' "$factory_path" 2>/dev/null) || squashfs_offset=""
  if [ -z "$squashfs_offset" ] || [ "$squashfs_offset" -lt 0 ]; then
    echo "✗ ERROR: unable to locate embedded squashfs payload inside factory image: $factory_path" >&2
    return 1
  fi

  echo "Attempting factory rootfs extraction from squashfs offset ${squashfs_offset}..."
  if ! tail -c "+$((squashfs_offset + 1))" "$factory_path" > "$root_candidate"; then
    echo "✗ ERROR: failed to extract factory rootfs payload from factory image" >&2
    return 1
  fi

  if ! extract_rootfs_image "$root_candidate" "$workdir"; then
    echo "✗ ERROR: extracted factory rootfs could not be inspected" >&2
    return 1
  fi

  ROOTFS_VIEW_DESC="factory squashfs rootfs"
  return 0
}

get_fdt_magic() {
  python3 -c 'import pathlib, sys; data = pathlib.Path(sys.argv[1]).read_bytes(); print(data[:4].hex() if len(data) >= 4 else "")' "$1"
}

get_fdt_totalsize() {
  python3 -c 'import pathlib, struct, sys; data = pathlib.Path(sys.argv[1]).read_bytes(); print(struct.unpack(">I", data[4:8])[0] if len(data) >= 8 else 0)' "$1"
}

verify_factory_header() {
  local factory_path="$1"
  local sysupgrade_path="$2"
  local workdir="$3"
  local squashfs_offset=""
  local header_path="$workdir/factory-header.bin"
  local header_fit_path="$workdir/factory-fit.bin"
  local sysupgrade_kernel_path="$workdir/sysupgrade-kernel.bin"
  local sysupgrade_fit_path="$workdir/sysupgrade-fit.bin"
  local factory_magic=""
  local sysupgrade_magic=""
  local factory_totalsize=""
  local sysupgrade_totalsize=""
  local sysupgrade_kernel_size=""
  local factory_padding_report=""
  local factory_padding_size=""
  local factory_padding_all_zero=""
  local factory_padding_first_offset=""
  local factory_padding_first_byte=""
  local factory_sha256=""
  local sysupgrade_sha256=""

  if ! command -v dumpimage >/dev/null 2>&1; then
    echo "✗ ERROR: dumpimage is required for factory header verification but is not installed"
    exit 1
  fi

  squashfs_offset=$(python3 -c 'import pathlib, sys; data = pathlib.Path(sys.argv[1]).read_bytes(); print(data.find(b"hsqs"))' "$factory_path" 2>/dev/null) || squashfs_offset=""
  if [ -z "$squashfs_offset" ] || [ "$squashfs_offset" -le 0 ]; then
    echo "✗ ERROR: factory image is missing a non-empty header before squashfs payload: $factory_path"
    exit 1
  fi
  if [ "$squashfs_offset" -ne "$EXPECTED_FACTORY_SQUASHFS_OFFSET" ]; then
    echo "✗ ERROR: factory squashfs payload starts at an unexpected offset"
    echo "  expected: $EXPECTED_FACTORY_SQUASHFS_OFFSET (0x$(printf '%x' "$EXPECTED_FACTORY_SQUASHFS_OFFSET"))"
    echo "  actual:   $squashfs_offset (0x$(printf '%x' "$squashfs_offset"))"
    exit 1
  fi

  if ! head -c "$squashfs_offset" "$factory_path" > "$header_path"; then
    echo "✗ ERROR: failed to extract factory header region: $factory_path"
    exit 1
  fi

  if [ ! -s "$header_path" ]; then
    echo "✗ ERROR: extracted factory header region is empty"
    exit 1
  fi

  factory_magic=$(get_fdt_magic "$header_path")
  if [ "$factory_magic" != "d00dfeed" ]; then
    echo "✗ ERROR: factory header does not start with FIT/DTB magic (got $factory_magic)"
    exit 1
  fi

  factory_totalsize=$(get_fdt_totalsize "$header_path")
  if [ -z "$factory_totalsize" ] || [ "$factory_totalsize" -le 0 ] || [ "$factory_totalsize" -gt "$squashfs_offset" ]; then
    echo "✗ ERROR: invalid factory FIT totalsize: $factory_totalsize"
    exit 1
  fi

  if ! head -c "$factory_totalsize" "$header_path" > "$header_fit_path"; then
    echo "✗ ERROR: failed to trim factory FIT payload to DTB totalsize"
    exit 1
  fi

  if ! dumpimage -l "$header_fit_path" >/dev/null 2>&1; then
    echo "✗ ERROR: factory header FIT metadata is not readable via dumpimage"
    exit 1
  fi

  if ! extract_sysupgrade_kernel "$sysupgrade_path" "$sysupgrade_kernel_path"; then
    exit 1
  fi

  sysupgrade_magic=$(get_fdt_magic "$sysupgrade_kernel_path")
  if [ "$sysupgrade_magic" != "d00dfeed" ]; then
    echo "✗ ERROR: sysupgrade kernel payload is not a FIT/DTB image (got $sysupgrade_magic)"
    exit 1
  fi

  sysupgrade_totalsize=$(get_fdt_totalsize "$sysupgrade_kernel_path")
  sysupgrade_kernel_size=$(stat -c%s "$sysupgrade_kernel_path" 2>/dev/null || stat -f%z "$sysupgrade_kernel_path" 2>/dev/null)
  if [ -z "$sysupgrade_totalsize" ] || [ "$sysupgrade_totalsize" -le 0 ] || [ "$sysupgrade_totalsize" -gt "$sysupgrade_kernel_size" ]; then
    echo "✗ ERROR: invalid sysupgrade kernel FIT totalsize: $sysupgrade_totalsize"
    exit 1
  fi

  if [ "$sysupgrade_totalsize" -ne "$factory_totalsize" ]; then
    echo "✗ ERROR: factory FIT totalsize does not match sysupgrade kernel payload"
    echo "  factory totalsize:   $factory_totalsize"
    echo "  sysupgrade totalsize: $sysupgrade_totalsize"
    exit 1
  fi

  if ! head -c "$sysupgrade_totalsize" "$sysupgrade_kernel_path" > "$sysupgrade_fit_path"; then
    echo "✗ ERROR: failed to trim sysupgrade kernel FIT payload to DTB totalsize"
    exit 1
  fi

  if ! dumpimage -l "$sysupgrade_fit_path" >/dev/null 2>&1; then
    echo "✗ ERROR: sysupgrade kernel FIT metadata is not readable via dumpimage"
    exit 1
  fi

  factory_sha256=$(compute_file_sha256 "$header_fit_path")
  sysupgrade_sha256=$(compute_file_sha256 "$sysupgrade_fit_path")
  if [ "$factory_sha256" != "$sysupgrade_sha256" ]; then
    echo "✗ ERROR: factory FIT header/kernel payload does not match sysupgrade kernel payload"
    echo "  factory fit sha256:    $factory_sha256"
    echo "  sysupgrade kernel sha256: $sysupgrade_sha256"
    exit 1
  fi

  echo "✓ factory FIT header/kernel matches sysupgrade kernel payload: $factory_sha256"

  factory_padding_report=$(python3 - "$factory_path" "$factory_totalsize" "$squashfs_offset" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
start = int(sys.argv[2])
end = int(sys.argv[3])
data = path.read_bytes()

if start < 0 or end < start or end > len(data):
    raise SystemExit(2)

region = data[start:end]
if not region:
    print("0\t1\t\t")
    raise SystemExit(0)

for index, value in enumerate(region):
    if value != 0:
        print(f"{len(region)}\t0\t{index}\t{value:02x}")
        raise SystemExit(0)

print(f"{len(region)}\t1\t\t")
PY
  ) || {
    echo "✗ ERROR: failed to inspect factory padding region between FIT payload and squashfs"
    exit 1
  }
  IFS=$'\t' read -r factory_padding_size factory_padding_all_zero factory_padding_first_offset factory_padding_first_byte <<< "$factory_padding_report"

  if [ "$factory_padding_all_zero" != "1" ]; then
    echo "✗ ERROR: factory padding/trailer region before squashfs is not zero-filled"
    echo "  padding size: $factory_padding_size bytes"
    echo "  first unexpected byte offset: $((factory_totalsize + factory_padding_first_offset))"
    echo "  first unexpected byte value: 0x$factory_padding_first_byte"
    exit 1
  fi

  echo "✓ factory padding/trailer before squashfs is zero-filled: $factory_padding_size bytes"
  echo "✓ factory squashfs payload starts at expected offset: $squashfs_offset"
}

rootfs_has_entry() {
  local rel="$1"
  [ -n "$ROOTFS_LIST_FILE" ] || return 1
  python3 - "$ROOTFS_LIST_FILE" "$rel" <<'PY'
import sys

list_file = sys.argv[1]
target = f"squashfs-root/{sys.argv[2]}"

with open(list_file, "r", encoding="utf-8", errors="replace") as fh:
    for raw_line in fh:
        line = raw_line.rstrip("\n")
        if not line:
            continue
        if " -> " in line:
            path = line.split(" -> ", 1)[0].rsplit(None, 1)[-1]
        else:
            path = line.rsplit(None, 1)[-1]
        if path == target:
            sys.exit(0)

sys.exit(1)
PY
}

extract_rootfs_member() {
  local rel="$1"
  local dest="$2"
  if ! unsquashfs -cat "$ROOTFS_VIEW" "$rel" > "$dest" 2>/dev/null; then
    return 1
  fi
  [ -s "$dest" ]
}

require_rootfs_entry() {
  local rel="$1"
  if rootfs_has_entry "$rel"; then
    echo "✓ rootfs entry present: /$rel"
  else
    echo "✗ Missing rootfs entry: /$rel"
    exit 1
  fi
}

require_rootfs_any() {
  local description="$1"
  shift
  local rel
  for rel in "$@"; do
    if rootfs_has_entry "$rel"; then
      echo "✓ rootfs entry present for ${description}: /$rel"
      return 0
    fi
  done
  echo "✗ Missing rootfs entry for ${description}"
  printf '  tried: /%s\n' "$@"
  exit 1
}

require_rootfs_elf_runtime() {
  local rel="$1"
  local file_path=""
  local interpreter=""
  local soname=""
  local needed_libs=""

  if ! rootfs_has_entry "$rel"; then
    echo "✗ Missing ELF binary for runtime validation: /$rel"
    exit 1
  fi

  if ! command -v readelf >/dev/null 2>&1; then
    echo "✗ ERROR: readelf is required for ELF runtime verification"
    exit 1
  fi

  file_path=$(mktemp /tmp/rootfs-elf.XXXXXX)
  if ! extract_rootfs_member "$rel" "$file_path"; then
    rm -f "$file_path"
    echo "✗ ERROR: failed to extract ELF binary for runtime validation: /$rel"
    exit 1
  fi

  interpreter=$(readelf -l "$file_path" 2>/dev/null | sed -n 's#.*Requesting program interpreter: \(.*\)\]#\1#p' | head -1)
  if [ -n "$interpreter" ]; then
    if rootfs_has_entry "${interpreter#/}"; then
      echo "✓ ELF interpreter present for /$rel: $interpreter"
    else
      rm -f "$file_path"
      echo "✗ Missing ELF interpreter for /$rel: $interpreter"
      exit 1
    fi
  fi

  needed_libs=$(readelf -d "$file_path" 2>/dev/null | sed -n 's#.*Shared library: \[\(.*\)\]#\1#p')
  for soname in $needed_libs; do
    [ -n "$soname" ] || continue
    if rootfs_has_entry "lib/$soname" || rootfs_has_entry "usr/lib/$soname"; then
      echo "✓ ELF dependency present for /$rel: $soname"
    else
      rm -f "$file_path"
      echo "✗ Missing ELF dependency for /$rel: $soname"
      exit 1
    fi
  done

  rm -f "$file_path"
}

normalize_dep_name() {
  local raw="$1"
  local dep
  dep=$(echo "$raw" | sed 's/([^)]*)//g' | cut -d'|' -f1 | xargs)
  dep=${dep%%:*}
  echo "$dep"
}

require_prebuilt_manifest_dependencies() {
  local metadata_file="$1"
  local pkg=""
  local arch=""
  local deps=""
  local dep=""
  local normalized=""
  local prebuilt_packages=""

  [ -f "$metadata_file" ] || return 0

  while IFS=$'\t' read -r pkg arch deps; do
    normalized=$(normalize_dep_name "$pkg")
    [ -n "$normalized" ] || continue
    prebuilt_packages="${prebuilt_packages}${normalized}"$'\n'
  done < "$metadata_file"

  while IFS=$'\t' read -r pkg arch deps; do
    [ -n "$pkg" ] || continue
    echo "Checking prebuilt package metadata: $pkg ($arch)"
    IFS=',' read -ra dep_list <<< "$deps"
    for dep in "${dep_list[@]}"; do
      normalized=$(normalize_dep_name "$dep")
      case "$normalized" in
        ""|libc|kernel|base-files|busybox)
          continue
          ;;
        @*)
          continue
          ;;
      esac
      if printf '%s' "$prebuilt_packages" | grep -Fxq "$normalized"; then
        echo "✓ prebuilt overlay dependency present: $normalized"
        continue
      fi
      require_manifest_pkg "$normalized"
    done
  done < "$metadata_file"
}

ROOTFS_STAGE=$(find_rootfs_stage || true)
ROOTFS_IMAGE=$(find "$WORKSPACE_ROOT/openwrt/bin/targets" -type f \( -name "*squashfs-rootfs*" -o -name "*rootfs.squashfs" -o -name "*rootfs.img" -o -name "*rootfs.bin" \) ! -name "*sysupgrade*" ! -name "*factory*" 2>/dev/null | head -1)
ROOTFS_VIEW=""
ROOTFS_LIST_FILE=""
ROOTFS_SHA256=""
ROOTFS_VIEW_DESC=""
PRIMARY_ROOTFS_SHA256=""

if ! command -v unsquashfs >/dev/null 2>&1; then
  echo "✗ ERROR: unsquashfs is required for release verification but is not installed"
  exit 1
fi

if [ -n "$ROOTFS_IMAGE" ]; then
  ROOTFS_TMP=$(mktemp -d /tmp/openwrt-rootfs-check.XXXXXX)
  if ! extract_rootfs_image "$ROOTFS_IMAGE" "$ROOTFS_TMP"; then
    rm -rf "$ROOTFS_TMP"
    ROOTFS_TMP=""
  fi
fi

if [ -z "$ROOTFS_VIEW" ] && [ -n "$SYSUPGRADE" ]; then
  ROOTFS_TMP=$(mktemp -d /tmp/openwrt-rootfs-check.XXXXXX)
  if ! extract_sysupgrade_rootfs "$SYSUPGRADE" "$ROOTFS_TMP"; then
    rm -rf "$ROOTFS_TMP"
    ROOTFS_TMP=""
  fi
fi

if [ -z "$ROOTFS_VIEW" ]; then
  echo "✗ ERROR: unable to inspect rootfs from releasable firmware artifacts"
  echo "  standalone rootfs image: ${ROOTFS_IMAGE:-<missing>}"
  echo "  sysupgrade image: ${SYSUPGRADE:-<missing>}"
  if [ -n "$ROOTFS_STAGE" ] && [ -d "$ROOTFS_STAGE" ]; then
    echo "  note: build_dir staging exists at $ROOTFS_STAGE but is not accepted for release verification"
  fi
  exit 1
fi

echo "Using rootfs verification source: $ROOTFS_VIEW_DESC -> $ROOTFS_VIEW"
PRIMARY_ROOTFS_SHA256="$ROOTFS_SHA256"
echo "Primary rootfs squashfs sha256: $PRIMARY_ROOTFS_SHA256"

require_rootfs_entry "etc/init.d/mgrserver"
require_rootfs_entry "usr/bin/health-check"
require_rootfs_entry "usr/bin/service-watchdog"
require_rootfs_entry "etc/uci-defaults/98-home-partition"
require_rootfs_entry "etc/uci-defaults/99-service-watchdog-cron"
require_rootfs_entry "usr/bin/sing-box"
require_rootfs_entry "etc/init.d/sing-box"
require_rootfs_entry "etc/config/sing-box"
require_rootfs_entry "usr/bin/easytier-core"
require_rootfs_entry "usr/bin/easytier-cli"
require_rootfs_entry "usr/bin/easytier-web"
require_rootfs_entry "usr/bin/wimlib-imagex"
require_rootfs_entry "usr/sbin/mkfs.f2fs"
require_rootfs_entry "etc/init.d/easytier"
require_rootfs_entry "etc/config/easytier"
require_rootfs_entry "usr/lib/lua/luci/controller/easytier.lua"
require_rootfs_entry "usr/share/rpcd/acl.d/luci-app-easytier.json"
require_rootfs_entry "usr/share/mgrserver-defaults/pxe/config.ini"
require_rootfs_entry "usr/share/mgrserver-defaults/pxe/up_pxe_res.sh"
require_rootfs_entry "usr/share/mgrserver-defaults/pxe/tftpboot"
require_rootfs_entry "root/mgrserver/commands.json"
require_rootfs_entry "root/mgrserver/web-dist/index.html"
require_rootfs_entry "usr/bin/node"
require_rootfs_entry "usr/bin/npm"
require_rootfs_any "MgrServer server entry" "root/mgrserver/dist/index.js" "root/mgrserver/bundle/index.cjs"
require_rootfs_any "wimlib shared library" "usr/lib/libwim.so" "usr/lib/libwim.so.15"

require_prebuilt_manifest_dependencies "$WORKSPACE_ROOT/prebuilt-ipk-metadata.txt"
require_rootfs_elf_runtime "usr/bin/sing-box"
require_rootfs_elf_runtime "usr/bin/easytier-core"
require_rootfs_elf_runtime "usr/bin/easytier-cli"
require_rootfs_elf_runtime "usr/bin/easytier-web"
require_rootfs_elf_runtime "usr/bin/wimlib-imagex"

FACTORY_HEADER_TMP=$(mktemp -d /tmp/openwrt-factory-header-check.XXXXXX)
verify_factory_header "$FACTORY" "$SYSUPGRADE" "$FACTORY_HEADER_TMP"

FACTORY_ROOTFS_TMP=$(mktemp -d /tmp/openwrt-factory-rootfs-check.XXXXXX)
if ! extract_factory_rootfs "$FACTORY" "$FACTORY_ROOTFS_TMP"; then
  rm -rf "$FACTORY_ROOTFS_TMP"
  FACTORY_ROOTFS_TMP=""
  exit 1
fi

if [ "$ROOTFS_SHA256" != "$PRIMARY_ROOTFS_SHA256" ]; then
  echo "✗ ERROR: factory rootfs payload does not match verified release rootfs"
  echo "  primary rootfs sha256: $PRIMARY_ROOTFS_SHA256"
  echo "  factory rootfs sha256: $ROOTFS_SHA256"
  exit 1
fi
echo "✓ factory rootfs payload matches verified release rootfs: $ROOTFS_SHA256"

echo ""
echo "============================================"
echo "Firmware verification complete"
echo "============================================"
