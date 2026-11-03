#!/bin/bash
# Remove the E3372 mode switcher and the E3372 Modem app. The stick and its network service are left alone.
set -euo pipefail
LABEL=com.huawei-e3372.switch
sudo launchctl bootout system/"$LABEL" 2>/dev/null || true
sudo rm -f /Library/LaunchDaemons/"$LABEL".plist /usr/local/libexec/e3372-switch \
	/usr/local/libexec/e3372-uninstall /var/log/e3372-switch.log
pkill -x E3372Modem 2>/dev/null || true
sudo rm -rf "/Applications/E3372 Modem.app"
sudo pkgutil --forget com.huawei-e3372.switch >/dev/null 2>&1 || true
echo "Removed. To also remove the stick's network service: System Settings > Network,"
echo "select the HUAWEI_MOBILE service, and click (-)."
