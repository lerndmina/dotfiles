#!/bin/bash
# Install the Tailscale + Windscribe route hook as a systemd service.
# Re-run after editing the scripts; it overwrites the installed copies.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)

sudo install -m 755 "$here/ts-windscribe-routes" "$here/ts-windscribe-watch" /usr/local/sbin/
sudo install -m 644 "$here/ts-windscribe-routes.service" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable ts-windscribe-routes.service
sudo systemctl restart ts-windscribe-routes.service
systemctl --no-pager status ts-windscribe-routes.service | head -5
