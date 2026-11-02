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

echo "==> Switching any stick that is plugged in now"
sudo "$BIN" || true

echo
echo "Done. Plug the E3372 in; within ~15 seconds it shows up as a network"
echo "adapter and gets an address from the stick (192.168.8.x)."
echo "Stick settings (SIM PIN, APN, data): http://192.168.8.1"
