#!/bin/bash
# Install the E3372 mode switcher and the LaunchDaemon that runs it on plug-in.
set -euo pipefail
cd "$(dirname "$0")"

BIN=/usr/local/libexec/e3372-switch
PLIST=/Library/LaunchDaemons/com.huawei-e3372.switch.plist
LABEL=com.huawei-e3372.switch

[ "$(uname -m)" = arm64 ] || echo "note: built for arm64; this Mac is $(uname -m)"
xcode-select -p >/dev/null 2>&1 || { echo "Install the Command Line Tools first: xcode-select --install"; exit 1; }

BREW=$(command -v brew || echo /opt/homebrew/bin/brew)
if [ ! -f "$("$BREW" --prefix libusb 2>/dev/null)/lib/libusb-1.0.a" ]; then
	echo "==> Installing libusb (build-time only; it is linked in statically)"
	"$BREW" install libusb
fi

echo "==> Building"
make LIBUSB_PREFIX="$("$BREW" --prefix libusb)" >/dev/null 2>&1 || make LIBUSB_PREFIX="$("$BREW" --prefix libusb)"

echo "==> Installing (needs your password)"
sudo mkdir -p /usr/local/libexec
sudo install -m 755 -o root -g wheel build/e3372-switch "$BIN"
sudo install -m 644 -o root -g wheel com.huawei-e3372.switch.plist "$PLIST"
sudo launchctl bootout system/"$LABEL" 2>/dev/null || true
sudo launchctl bootstrap system "$PLIST"

# launchd starts the switch itself for a stick that is already plugged in.
echo "==> Waiting for a plugged-in stick to switch"
for i in $(seq 25); do
	ioreg -p IOUSB -l | grep -q '"idProduct" = 7937' || break
	sleep 1
done
if ioreg -p IOUSB -l | grep -q '"idProduct" = 7937'; then
	echo "The stick is still in CD mode; see /var/log/e3372-switch.log"
fi

echo
echo "Done. Plug the E3372 in; within ~15 seconds it shows up as a"
echo "network adapter (HUAWEI_MOBILE) and gets an address from the stick."
echo "Stick settings (SIM PIN, APN, data): http://192.168.8.1 or http://192.168.106.1"
