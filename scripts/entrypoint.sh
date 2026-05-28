#!/usr/bin/env bash
set -euo pipefail

echo "INFO: generating Asterisk configs from MySQL..."
/usr/local/bin/generate-configs.sh || { echo "ERR: config generation failed" >&2; exit 1; }

echo "INFO: starting Asterisk..."
exec asterisk -f -C /etc/asterisk/asterisk.conf
