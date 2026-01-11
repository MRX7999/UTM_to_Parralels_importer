#!/bin/sh
set -eu

ZIP_PATH="${1:-/Users/sig67/Downloads/Parrot-security-7.0_arm64.utm.zip}"

# ---- requirements ----
if [ ! -f "$ZIP_PATH" ]; then
  echo "UTM zip not found: $ZIP_PATH"
  exit 1
fi

if ! command -v prlctl >/dev/null 2>&1; then
  echo "prlctl not found. Install Parallels Desktop."
  exit 1
fi

if ! command -v qemu-img >/dev/null 2>&1; then
  echo "qemu-img not found. Install: brew install qemu"
  exit 1
fi

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

echo "[*] Unzipping -> $TMP_DIR"
ditto -x -k "$ZIP_PATH" "$TMP_DIR"

UTM_DIR="$(find "$TMP_DIR" -maxdepth 4 -type d -name "*.utm" -print -quit)"
if [ -z "${UTM_DIR:-}" ]; then
  echo "No .utm bundle found inside zip."
  exit 1
fi
echo "[*] Found UTM: $UTM_DIR"

SRC_DISK="$(find "$UTM_DIR" -type f \( -iname "*.qcow2" -o -iname "*.raw" -o -iname "*.img" -o -iname "*.bin" \) -print -quit)"
if [ -z "${SRC_DISK:-}" ]; then
  echo "No disk file found inside .utm (expected .qcow2/.raw/.img/.bin)."
  exit 1
fi
echo "[*] Found disk: $SRC_DISK"

RAW_SRC="$TMP_DIR/source.raw"
ext="$(echo "${SRC_DISK##*.}" | tr '[:upper:]' '[:lower:]')"

echo "[*] Converting source -> RAW (if needed)..."
if [ "$ext" = "raw" ]; then
  cp -f "$SRC_DISK" "$RAW_SRC"
else
  qemu-img convert -O raw "$SRC_DISK" "$RAW_SRC"
fi

# Get virtual-size via qemu-img info (parse without python)
# We rely on the "virtual size" line: "virtual size: 64G (68719476736 bytes)"
VIRT_BYTES="$(qemu-img info "$RAW_SRC" | awk -F'[()]' '/virtual size:/ {gsub(/[^0-9]/,"",$2); print $2; exit}')"
if [ -z "${VIRT_BYTES:-}" ]; then
  echo "Could not read virtual size from qemu-img info."
  qemu-img info "$RAW_SRC" || true
  exit 1
fi

# bytes -> MB (ceil)
SIZE_MB=$(( (VIRT_BYTES + 1048576 - 1) / 1048576 ))

BASE_NAME="$(basename "$UTM_DIR" .utm)"
STAMP="$(date +%Y%m%d_%H%M%S)"
VM_NAME="${BASE_NAME}-ARM64-${STAMP}"

DEST_DIR="$HOME/Parallels"
mkdir -p "$DEST_DIR"

echo "[*] Creating VM: $VM_NAME"
# --dst is supported; if ignored by your build, we still fallback to searching later
prlctl create "$VM_NAME" -o linux --no-hdd --dst "$DEST_DIR" >/dev/null 2>&1 || prlctl create "$VM_NAME" -o linux --no-hdd >/dev/null

echo "[*] Adding Parallels HDD (plain) size=${SIZE_MB}MB ..."
prlctl set "$VM_NAME" --device-add hdd --type plain --size "$SIZE_MB" --iface sata --position 0 >/dev/null

# Try to get .pvm path reliably:
# 1) via prlctl list -a -o uuid,name
UUID="$(prlctl list -a -o uuid,name 2>/dev/null | awk -v n="$VM_NAME" '$2==n{print $1; exit}')"
PVM_PATH=""

# 2) if we have UUID, try prlctl list -a -o uuid,home (some versions support "home")
if [ -n "${UUID:-}" ]; then
  PVM_PATH="$(prlctl list -a -o uuid,home 2>/dev/null | awk -v u="$UUID" '$1==u{print $2; exit}' || true)"
fi

# 3) fallback: search typical locations for the bundle by name
if [ -z "${PVM_PATH:-}" ]; then
  if [ -d "$DEST_DIR/$VM_NAME.pvm" ]; then
    PVM_PATH="$DEST_DIR/$VM_NAME.pvm"
  elif [ -d "$HOME/Documents/Parallels/$VM_NAME.pvm" ]; then
    PVM_PATH="$HOME/Documents/Parallels/$VM_NAME.pvm"
  else
    PVM_PATH="$(find "$HOME" -maxdepth 4 -type d -name "$VM_NAME.pvm" -print -quit 2>/dev/null || true)"
  fi
fi

if [ -z "${PVM_PATH:-}" ] || [ ! -d "$PVM_PATH" ]; then
  echo "Could not locate created .pvm bundle for VM: $VM_NAME"
  echo "Try finding it manually in Finder (~/Parallels or ~/Documents/Parallels)."
  exit 1
fi

echo "[*] VM bundle: $PVM_PATH"

# Find created HDS slice
HDS_TARGET="$(find "$PVM_PATH" -type f -name "*.hds" -print -quit)"
if [ -z "${HDS_TARGET:-}" ]; then
  echo "Could not find .hds inside: $PVM_PATH"
  exit 1
fi
echo "[*] Target HDS: $HDS_TARGET"

# Ensure VM is stopped
echo "[*] Stopping VM (if running)..."
prlctl stop "$VM_NAME" --kill >/dev/null 2>&1 || true

# Backup HDS
BACKUP_HDS="${HDS_TARGET}.bak.${STAMP}"
echo "[*] Backup HDS -> $BACKUP_HDS"
cp -f "$HDS_TARGET" "$BACKUP_HDS"

# Write RAW into HDS
echo "[*] Writing RAW into Parallels disk (can take a while)..."
qemu-img convert -O raw "$RAW_SRC" "$HDS_TARGET"

echo
echo "[+] DONE"
echo "    VM Name : $VM_NAME"
echo "    VM Path : $PVM_PATH"
echo "    Backup  : $BACKUP_HDS"
echo
echo "Start it:"
echo "    prlctl start \"$VM_NAME\""
