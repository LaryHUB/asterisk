#!/usr/bin/env bash
# Builds all Asterisk dependencies from source into /opt/asterisk-deps
# Works on any Linux (Debian, Ubuntu, RHEL, CentOS, AlmaLinux, etc.)
#
# Usage:
#   tar xf deps-src.tar.gz
#   cd deps-src
#   bash build-src-deps.sh
#
# After this, build Asterisk with:
#   ./configure --without-pjproject --disable-xmldoc \
#               PKG_CONFIG_PATH=/opt/asterisk-deps/lib/pkgconfig \
#               CFLAGS="-I/opt/asterisk-deps/include" \
#               LDFLAGS="-L/opt/asterisk-deps/lib -Wl,-rpath,/opt/asterisk-deps/lib"
set -euo pipefail

PREFIX=/opt/asterisk-deps
JOBS=$(nproc 2>/dev/null || echo 4)
DIR="$(cd "$(dirname "$0")" && pwd)"

export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export PATH="$PREFIX/bin:$PATH"
CFLAGS="-I$PREFIX/include"
LDFLAGS="-L$PREFIX/lib -Wl,-rpath,$PREFIX/lib"
export CFLAGS LDFLAGS

mkdir -p "$PREFIX"

# ---- minimal build tools check ----
for cmd in gcc make cmake curl; do
  if ! command -v $cmd &>/dev/null; then
    echo "ERR: $cmd not found — install base build tools first:
  Debian/Ubuntu : apt-get install -y build-essential cmake curl
  RHEL/Alma     : dnf groupinstall 'Development Tools' && dnf install -y cmake curl" >&2
    exit 1
  fi
done

build() {
  local name="$1"; shift
  echo "=== $name ==="
  "$@"
  echo "=== $name OK ==="
}

cd "$DIR"

# ncurses
build ncurses bash -c "
  tar xf ncurses-6.4.tar.gz && cd ncurses-6.4
  ./configure --prefix=$PREFIX --with-shared --without-debug --enable-widec
  make -j$JOBS && make install
  ln -sf libncursesw.so $PREFIX/lib/libncurses.so 2>/dev/null || true
"

# openssl
build openssl bash -c "
  tar xf openssl-3.3.1.tar.gz && cd openssl-3.3.1
  ./Configure --prefix=$PREFIX --openssldir=$PREFIX/ssl shared
  make -j$JOBS && make install_sw
"

# libedit
build libedit bash -c "
  tar xf libedit-20230828-3.1.tar.gz && cd libedit-20230828-3.1
  ./configure --prefix=$PREFIX
  make -j$JOBS && make install
"

# util-linux (for libuuid)
build libuuid bash -c "
  tar xf util-linux-2.40.tar.xz && cd util-linux-2.40
  ./configure --prefix=$PREFIX --disable-all-programs --enable-libuuid --enable-libblkid
  make -j$JOBS && make install
"

# libxml2
build libxml2 bash -c "
  tar xf libxml2-2.12.6.tar.xz && cd libxml2-2.12.6
  ./configure --prefix=$PREFIX --without-python
  make -j$JOBS && make install
"

# sqlite
build sqlite bash -c "
  tar xf sqlite-autoconf-3450200.tar.gz && cd sqlite-autoconf-3450200
  ./configure --prefix=$PREFIX
  make -j$JOBS && make install
"

# jansson
build jansson bash -c "
  tar xf jansson-2.14.tar.gz && cd jansson-2.14
  ./configure --prefix=$PREFIX
  make -j$JOBS && make install
"

# curl
build curl bash -c "
  tar xf curl-8.7.1.tar.gz && cd curl-8.7.1
  ./configure --prefix=$PREFIX --with-openssl=$PREFIX --without-libpsl
  make -j$JOBS && make install
"

# libsrtp2
build libsrtp2 bash -c "
  tar xf v2.6.0.tar.gz && cd libsrtp-2.6.0
  ./configure --prefix=$PREFIX --enable-openssl --with-openssl-dir=$PREFIX
  make -j$JOBS && make install
"

# newt (for menuselect UI)
build newt bash -c "
  tar xf newt-0.52.24.tar.gz && cd newt-0.52.24
  ./configure --prefix=$PREFIX
  make -j$JOBS && make install
"

# mariadb-connector-c (provides libmysqlclient-compatible libmariadb)
build mariadb-connector bash -c "
  tar xf mariadb-connector-c-3.3.10-src.tar.gz && cd mariadb-connector-c-3.3.10-src
  cmake -DCMAKE_INSTALL_PREFIX=$PREFIX \
        -DOPENSSL_ROOT_DIR=$PREFIX \
        -DWITH_SSL=OPENSSL \
        -DCMAKE_BUILD_TYPE=Release \
        -B build .
  cmake --build build -j$JOBS
  cmake --install build
  # compat symlink so Asterisk finds libmysqlclient
  ln -sf $PREFIX/lib/mariadb/libmariadb.so $PREFIX/lib/libmysqlclient.so 2>/dev/null || true
  ln -sf $PREFIX/lib/mariadb/libmariadb.so.3 $PREFIX/lib/libmysqlclient.so.21 2>/dev/null || true
"

echo ""
echo "All deps installed to $PREFIX"
echo ""
echo "Build Asterisk with:"
echo "  ./configure --without-pjproject --disable-xmldoc \\"
echo "    PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig \\"
echo "    CFLAGS=\"-I$PREFIX/include\" \\"
echo "    LDFLAGS=\"-L$PREFIX/lib -Wl,-rpath,$PREFIX/lib\""
