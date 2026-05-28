#!/usr/bin/env bash
# Full Asterisk 20.19.0 install on a clean server (no pre-installed packages needed).
# Supports: Debian 11/12, Ubuntu 20.04/22.04/24.04, AlmaLinux/Rocky/CentOS 8/9, RHEL 8/9
#
# Usage (run as root):
#   curl -fsSL https://raw.githubusercontent.com/LaryHUB/asterisk/main/scripts/install-all.sh | bash
# or:
#   bash scripts/install-all.sh
#
# What it does:
#   1. Detects OS, installs build toolchain + deps via apt/dnf
#   2. Downloads Asterisk 20.19.0 source
#   3. Builds with chan_sip enabled, pjsip/iax disabled
#   4. Installs to /usr/local, sets up systemd service
#   5. Installs MySQL client library for generate-configs.sh
set -euo pipefail

AST_VER="20.19.0"
AST_URL="https://downloads.asterisk.org/pub/telephony/asterisk/asterisk-${AST_VER}.tar.gz"
JOBS=$(nproc 2>/dev/null || echo 2)
PREFIX=/usr/local

# ─── helpers ────────────────────────────────────────────────────────────────
err()  { echo "ERR: $*" >&2; exit 1; }
info() { echo "INFO: $*"; }

[[ $EUID -eq 0 ]] || err "Run as root"

# ─── detect OS ──────────────────────────────────────────────────────────────
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  OS_ID="${ID:-unknown}"
  OS_VER="${VERSION_ID:-0}"
else
  err "Cannot detect OS (no /etc/os-release)"
fi

info "Detected: $OS_ID $OS_VER"

# ─── install build deps ──────────────────────────────────────────────────────
case "$OS_ID" in
  debian|ubuntu|linuxmint)
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y \
      build-essential wget curl git pkg-config \
      libssl-dev libncurses5-dev libedit-dev \
      uuid-dev libxml2-dev libsqlite3-dev \
      libjansson-dev libsrtp2-dev \
      libnewt-dev libcurl4-openssl-dev \
      liblua5.2-dev libspandsp-dev \
      default-libmysqlclient-dev default-mysql-client \
      libpopt-dev libical-dev \
      libedit-dev libreadline-dev \
      bison flex autoconf automake libtool \
      xmlstarlet
    ;;
  centos|rhel|almalinux|rocky|ol)
    # enable extra repos
    if command -v dnf &>/dev/null; then
      PKG="dnf"
    else
      PKG="yum"
    fi
    $PKG groupinstall -y "Development Tools" || true
    $PKG install -y epel-release || true
    $PKG install -y \
      wget curl git pkgconfig \
      openssl-devel ncurses-devel libedit-devel \
      libuuid-devel libxml2-devel sqlite-devel \
      jansson-devel libsrtp-devel \
      newt-devel libcurl-devel \
      lua-devel spandsp-devel \
      mariadb-devel mariadb \
      popt-devel libical-devel \
      readline-devel bison flex autoconf automake libtool \
      libxslt
    ;;
  *)
    err "Unsupported OS: $OS_ID. Supported: Debian, Ubuntu, AlmaLinux, Rocky, CentOS, RHEL"
    ;;
esac

info "Build deps installed."

# ─── download Asterisk ───────────────────────────────────────────────────────
BUILD_DIR=$(mktemp -d /tmp/asterisk-build.XXXXX)
trap 'rm -rf "$BUILD_DIR"' EXIT

info "Downloading Asterisk $AST_VER ..."
cd "$BUILD_DIR"
wget -q --show-progress "$AST_URL"
tar xf "asterisk-${AST_VER}.tar.gz"
cd "asterisk-${AST_VER}"

# ─── configure ───────────────────────────────────────────────────────────────
info "Configuring ..."
./configure \
  --prefix="$PREFIX" \
  --without-pjproject \
  --disable-xmldoc \
  2>&1 | tail -5

# ─── menuselect: enable chan_sip, disable pjsip/iax ─────────────────────────
info "Applying menuselect ..."
make menuselect.makeopts

# disable pjsip & iax
menuselect/menuselect --disable chan_pjsip     menuselect.makeopts 2>/dev/null || true
menuselect/menuselect --disable res_pjsip      menuselect.makeopts 2>/dev/null || true
menuselect/menuselect --disable chan_iax2       menuselect.makeopts 2>/dev/null || true
menuselect/menuselect --disable chan_dahdi      menuselect.makeopts 2>/dev/null || true

# enable chan_sip
menuselect/menuselect --enable chan_sip         menuselect.makeopts 2>/dev/null || true

# enable all dialplan apps/functions/codecs
for mod in \
  app_dial app_hangup app_set app_goto app_gotoif app_gotoiftime \
  app_playback app_record app_voicemail app_queue app_transfer \
  app_authenticate app_disa app_echo app_exec app_milliwatt \
  app_read app_sayunixtime app_sendtext app_stack app_system \
  app_verbose app_waitforsilence app_chanspy \
  func_strings func_math func_cdr func_callerid func_logic \
  func_env func_timeout func_channel func_uri func_dialplan \
  codec_alaw codec_ulaw codec_g729 codec_g723_1 codec_gsm \
  pbx_config pbx_loopback \
  res_musiconhold res_rtp_asterisk res_rtp_multicast \
  cdr_csv cdr_manager; do
  menuselect/menuselect --enable "$mod" menuselect.makeopts 2>/dev/null || true
done

# ─── build & install ─────────────────────────────────────────────────────────
info "Building (this takes 5-15 minutes) ..."
make -j"$JOBS"

info "Installing ..."
make install
make samples
make config    # installs /etc/init.d/asterisk + /etc/default/asterisk

# ─── copy project configs ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [[ -f "$PROJECT_DIR/sip.conf" ]]; then
  info "Copying project configs to /etc/asterisk/ ..."
  cp "$PROJECT_DIR/sip.conf"        /etc/asterisk/sip.conf
  cp "$PROJECT_DIR/extensions.conf" /etc/asterisk/extensions.conf 2>/dev/null || true
  [[ -f "$PROJECT_DIR/clients.conf" ]] && cp "$PROJECT_DIR/clients.conf" /etc/asterisk/clients.conf
  [[ -f "$PROJECT_DIR/gws.conf"     ]] && cp "$PROJECT_DIR/gws.conf"     /etc/asterisk/gws.conf
fi

# copy generate-configs.sh
install -m 755 "$PROJECT_DIR/scripts/generate-configs.sh" /usr/local/bin/generate-configs.sh

# ─── systemd service ─────────────────────────────────────────────────────────
cat > /etc/systemd/system/asterisk.service <<'SERVICE'
[Unit]
Description=Asterisk PBX
After=network.target mysql.service mariadb.service
Wants=mysql.service mariadb.service

[Service]
Type=simple
User=root
EnvironmentFile=-/etc/asterisk/asterisk-db.env
ExecStartPre=/usr/local/bin/generate-configs.sh
ExecStart=/usr/local/sbin/asterisk -f -C /etc/asterisk/asterisk.conf
ExecReload=/usr/local/sbin/asterisk -rx "core reload"
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable asterisk

# ─── env file template ───────────────────────────────────────────────────────
if [[ ! -f /etc/asterisk/asterisk-db.env ]]; then
  cat > /etc/asterisk/asterisk-db.env <<'ENV'
# MySQL connection for generate-configs.sh
MYSQL_HOST=127.0.0.1
MYSQL_USER=asterisk
MYSQL_PASSWORD=changeme
MYSQL_DATABASE=asterisk
ENV
  info "Created /etc/asterisk/asterisk-db.env — edit it with your MySQL credentials"
fi

# ─── done ────────────────────────────────────────────────────────────────────
echo ""
echo "============================================="
echo " Asterisk ${AST_VER} installed successfully"
echo "============================================="
echo ""
echo "Next steps:"
echo "  1. Edit /etc/asterisk/asterisk-db.env  (set MySQL credentials)"
echo "  2. Import DB schema:"
echo "       mysql -u root -p < $PROJECT_DIR/sql/schema.sql"
echo "  3. Start:"
echo "       systemctl start asterisk"
echo "  4. Check:"
echo "       asterisk -r"
echo ""
