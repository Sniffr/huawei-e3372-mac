#!/bin/bash
# Remove the E3372 mode switcher. The stick and its network service are left alone.
set -euo pipefail
LABEL=com.huawei-e3372.switch
sudo launchctl bootout system/"$LABEL" 2>/dev/null || true
sudo rm -f /Library/LaunchDaemons/"$LABEL".plist /usr/local/libexec/e3372-switch /var/log/e3372-switch.log
echo "Removed. To also remove the stick's network service: System Settings > Network,"
echo "select the HUAWEI_MOBILE service, and click (-)."
