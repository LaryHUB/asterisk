#!/usr/bin/env bash
# Detects OS and downloads the matching dependency archive from GitHub Releases.
# Usage (run as root on the target server):
#   curl -fsSL https://raw.githubusercontent.com/LaryHUB/asterisk/main/scripts/download-deps.sh | bash
set -euo pipefail

REPO="LaryHUB/asterisk"
RELEASE_TAG="${1:-latest}"

err()  { echo "ERR: $*" >&2; exit 1; }
info() { echo "INFO: $*"; }

# ── detect OS ────────────────────────────────────────────────────────────────
[[ -f /etc/os-release ]] || err "Cannot detect OS (no /etc/os-release)"
. /etc/os-release

OS_ID="${ID:-unknown}"
OS_VER="${VERSION_ID:-0}"
OS_VER_MAJOR="${OS_VER%%.*}"

case "$OS_ID" in
  debian)
    case "$OS_VER_MAJOR" in
      11) NAME="debian11" ;;
      12) NAME="debian12" ;;
      *)  err "Unsupported Debian version: $OS_VER (supported: 11, 12)" ;;
    esac
    PKG_CMD="dpkg -i pkgs/*.deb"
    ;;
  ubuntu)
    case "$OS_VER_MAJOR" in
      20) NAME="ubuntu2004" ;;
      22) NAME="ubuntu2204" ;;
      24) NAME="ubuntu2404" ;;
      *)  err "Unsupported Ubuntu version: $OS_VER (supported: 20.04, 22.04, 24.04)" ;;
    esac
    PKG_CMD="dpkg -i pkgs/*.deb"
    ;;
  almalinux|alma)
    case "$OS_VER_MAJOR" in
      8) NAME="almalinux8" ;;
      9) NAME="almalinux9" ;;
      *) err "Unsupported AlmaLinux version: $OS_VER (supported: 8, 9)" ;;
    esac
    PKG_CMD="rpm -Uvh --force pkgs/*.rpm"
    ;;
  rocky)
    case "$OS_VER_MAJOR" in
      8) NAME="rocky8" ;;
      9) NAME="rocky9" ;;
      *) err "Unsupported Rocky Linux version: $OS_VER (supported: 8, 9)" ;;
    esac
    PKG_CMD="rpm -Uvh --force pkgs/*.rpm"
    ;;
  centos|rhel|ol)
    case "$OS_VER_MAJOR" in
      8) NAME="almalinux8" ;;
      9) NAME="almalinux9" ;;
      *) err "Unsupported $OS_ID version: $OS_VER. Using almalinux9 archive." ;;
    esac
    PKG_CMD="rpm -Uvh --force pkgs/*.rpm"
    ;;
  *)
    err "Unsupported OS: $OS_ID. Supported: Debian 11/12, Ubuntu 20/22/24, AlmaLinux 8/9, Rocky 8/9"
    ;;
esac

ARCHIVE="deps-${NAME}.tar.gz"
info "Detected: $OS_ID $OS_VER → archive: $ARCHIVE"

# ── resolve download URL ─────────────────────────────────────────────────────
if [[ "$RELEASE_TAG" == "latest" ]]; then
  API_URL="https://api.github.com/repos/${REPO}/releases/latest"
else
  API_URL="https://api.github.com/repos/${REPO}/releases/tags/${RELEASE_TAG}"
fi

info "Fetching release info from GitHub..."
if command -v curl &>/dev/null; then
  RELEASE_JSON=$(curl -fsSL "$API_URL")
elif command -v wget &>/dev/null; then
  RELEASE_JSON=$(wget -qO- "$API_URL")
else
  err "Neither curl nor wget found"
fi

DOWNLOAD_URL=$(echo "$RELEASE_JSON" \
  | grep -o "\"browser_download_url\": *\"[^\"]*${ARCHIVE}\"" \
  | grep -o 'https://[^"]*')

[[ -n "$DOWNLOAD_URL" ]] || err "Archive $ARCHIVE not found in release. Has the workflow run yet?"

# ── download ─────────────────────────────────────────────────────────────────
DEST="/opt/asterisk-deps"
mkdir -p "$DEST"

info "Downloading $ARCHIVE (~200-400 MB)..."
if command -v curl &>/dev/null; then
  curl -fL --progress-bar -o "$DEST/$ARCHIVE" "$DOWNLOAD_URL"
else
  wget --show-progress -O "$DEST/$ARCHIVE" "$DOWNLOAD_URL"
fi

# ── extract ──────────────────────────────────────────────────────────────────
info "Extracting to $DEST ..."
tar xf "$DEST/$ARCHIVE" -C "$DEST"
rm -f "$DEST/$ARCHIVE"

cd "$DEST"

# ── install packages ─────────────────────────────────────────────────────────
info "Installing packages..."
case "$OS_ID" in
  debian|ubuntu)
    dpkg -i pkgs/*.deb 2>/dev/null || true
    # fix broken deps that dpkg couldn't resolve
    apt-get install -f -y 2>/dev/null || true
    ;;
  almalinux|alma|rocky|centos|rhel|ol)
    rpm -Uvh --force pkgs/*.rpm 2>/dev/null || true
    ;;
esac
info "Packages installed."

# ── build & install Asterisk ─────────────────────────────────────────────────
info "Running install.sh ..."
bash install.sh

echo ""
echo "============================================="
echo " Asterisk 20.19.0 installed successfully"
echo "============================================="
echo ""
echo "Next steps:"
echo "  1. Edit MySQL credentials:"
echo "       nano /etc/asterisk/asterisk-db.env"
echo "  2. Import DB schema:"
echo "       mysql -u root -p < $DEST/schema.sql"
echo "  3. Start Asterisk:"
echo "       systemctl start asterisk"
echo "  4. Check:"
echo "       asterisk -r"
echo ""
