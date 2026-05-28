#!/usr/bin/env bash
# Downloads dependency source tarballs and creates deps-src.tar.gz
# Run this on any machine with internet access.
# Output: deps-src.tar.gz  (~50MB)
set -euo pipefail

OUT="$(cd "$(dirname "$0")/.." && pwd)/deps-src"
ARCHIVE="$(cd "$(dirname "$0")/.." && pwd)/deps-src.tar.gz"

mkdir -p "$OUT"
cd "$OUT"

fetch() {
  local url="$1"
  local file
  file="$(basename "$url")"
  if [[ -f "$file" ]]; then
    echo "SKIP $file"
  else
    echo "GET  $file"
    curl -fsSL -o "$file" "$url"
  fi
}

# --- build tools (source stubs — installed via system pkg mgr) ---
# These are C libraries that Asterisk needs; we download their sources.

fetch "https://github.com/akheron/jansson/releases/download/v2.14/jansson-2.14.tar.gz"
fetch "https://download.gnome.org/sources/libxml2/2.12/libxml2-2.12.6.tar.xz"
fetch "https://www.sqlite.org/2024/sqlite-autoconf-3450200.tar.gz"
fetch "https://github.com/cisco/libsrtp/archive/refs/tags/v2.6.0.tar.gz"
fetch "https://curl.se/download/curl-8.7.1.tar.gz"
fetch "https://thrysoee.dk/editline/libedit-20230828-3.1.tar.gz"
fetch "https://kernel.org/pub/linux/utils/util-linux/v2.40/util-linux-2.40.tar.xz"
fetch "https://releases.pagure.org/newt/newt-0.52.24.tar.gz"
fetch "https://downloads.mariadb.com/Connectors/c/connector-c-3.3.10/mariadb-connector-c-3.3.10-src.tar.gz"
fetch "https://github.com/openssl/openssl/releases/download/openssl-3.3.1/openssl-3.3.1.tar.gz"
fetch "https://ftp.gnu.org/pub/gnu/ncurses/ncurses-6.4.tar.gz"

# copy the build script itself
cp "$(dirname "$0")/build-src-deps.sh" "$OUT/"

cd "$(dirname "$OUT")"
echo "Creating $ARCHIVE ..."
tar czf "$ARCHIVE" deps-src/
echo "Done: $ARCHIVE ($(du -sh "$ARCHIVE" | cut -f1))"
rm -rf "$OUT"
