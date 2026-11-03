# Huawei E3372 on Apple-silicon Macs

This gets a Huawei E3372 LTE USB stick with **HiLink** firmware online on an
Apple-silicon Mac. It needs no kernel extension and no Huawei software.

**Install:** download [Huawei-E3372-1.1.0.pkg](https://github.com/Sniffr/huawei-e3372-mac/releases/latest/download/Huawei-E3372-1.1.0.pkg)
from the [latest release](https://github.com/Sniffr/huawei-e3372-mac/releases/latest),
open it, and plug the stick in. It also installs **E3372 Modem**, an app for
USSD codes and text messages.

## Why it doesn't work out of the box

When you plug it in, the E3372 pretends to be a CD drive (`HiLink` volume,
USB ID `12d1:1f01`) that holds Huawei's installer. That installer only has
Intel kexts. On Windows/Linux a "mode switch" message tells the stick to
reboot as a USB Ethernet adapter (`12d1:14dc`, CDC-ECM). macOS has a
built-in driver for CDC-ECM, so the only missing piece is that switch.

This repo provides:

- `e3372-switch`: a small native arm64 tool that sends Huawei's switch
  message (the same one `usb_modeswitch` uses). libusb is linked in
  statically, so the installed binary has no dependencies.
- A LaunchDaemon that launchd starts whenever a `12d1:1f01` device appears.
  It switches the stick, waits for the network adapter, and runs
  `networksetup -detectnewhardware` so macOS adds a network service for it.

The switch needs root because it takes the USB interface away from macOS's
mass-storage driver. That is why it runs as a LaunchDaemon. Ejecting the CD,
or sending the switch as an ordinary user, does not work on macOS.

macOS also refuses that takeover from a background daemon, even as root
(libusb reports "out of resources"). So the daemon runs the switch as root
inside the logged-in user's session, via `launchctl asuser`. The automatic
switch therefore needs someone logged in at the Mac. Before login, run
`sudo /usr/local/libexec/e3372-switch` by hand.

## Install

Requires an Apple-silicon Mac on macOS 12 or later. Nothing else is needed.

1. Download [Huawei-E3372-1.1.0.pkg](https://github.com/Sniffr/huawei-e3372-mac/releases/latest/download/Huawei-E3372-1.1.0.pkg).
2. Open it and follow the installer. It asks for an admin password.
   The package isn't signed with an Apple Developer ID. If macOS says it
   can't verify the developer, go to System Settings › Privacy & Security,
   click **Open Anyway**, and open the package again.
3. Plug the stick in. If it's already plugged in, it switches right away.

It installs:

| File | Purpose |
|---|---|
| `/usr/local/libexec/e3372-switch` | the switch tool |
| `/usr/local/libexec/e3372-uninstall` | removes everything again |
| `/Library/LaunchDaemons/com.huawei-e3372.switch.plist` | runs it on plug-in |
| `/var/log/e3372-switch.log` | what it did |
| `/Applications/E3372 Modem.app` | dialer, USSD and SMS app |

### From source

Needs the Xcode Command Line Tools (`xcode-select --install`) and Homebrew.
libusb is used only at build time and is linked in statically. The script
runs `brew install libusb` for you if it's missing.

```bash
git clone https://github.com/Sniffr/huawei-e3372-mac.git
cd huawei-e3372-mac
./install.sh
```

## Use

Plug the stick in. Within about 15 seconds the HiLink CD disappears and a new
network service named **HUAWEI_MOBILE** appears in System Settings › Network.
The stick hands the Mac an address by DHCP. On HiLink firmware that's usually
`192.168.8.x`; this stick uses `192.168.106.x`.

The stick's own web page is at its gateway address: <http://192.168.8.1> or
<http://192.168.106.1> (`ipconfig getoption <interface> router` shows which).
Use it for the SIM PIN, APN, data on/off, SMS and signal strength.

If Wi-Fi is also connected, macOS uses whichever service is higher in the
service order. To prefer the stick, go to System Settings › Network › ⋯ ›
Set Service Order, and drag it above Wi-Fi (or turn Wi-Fi off).

To run the switch by hand:

```bash
sudo /usr/local/libexec/e3372-switch
```

## The E3372 Modem app

Open **E3372 Modem** from Applications. The first time, macOS asks whether
it may find devices on your local network. Click **Allow**, because that's
how the app reaches the stick. The app works while Wi-Fi carries your
internet, and with no mobile data on the SIM.

- **Dialer:** a phone keypad for USSD codes. Dial `*144#` and the reply
  appears like a chat. For menus (M-PESA `*334#`, bundles `*544#`), type
  your choice in the reply box and press **End** when you're done. The
  buttons above the keypad are quick codes; edit them under **Device**.
- **Messages:** your texts grouped into conversations. Read, reply, start a
  new message, and delete conversations. When the stick's message storage
  is full (500 messages), new texts can't arrive. A banner then offers to
  delete the sent messages.
- **Menu bar:** signal bars and an unread count. New texts trigger a Mac
  notification.
- **Device:** operator, network type, signal (RSRP/SINR), SIM state, and a
  link to the stick's own web page.

The E3372 has no voice support, so it **can't make or receive calls**. If you
dial a plain phone number, the app offers to text it instead.

The app reaches the stick's address automatically. If it can't find the
stick, enter the address (for example `192.168.8.1`) under **Device ›
Stick**. It uses the same web API as the stick's own page; nothing else is
installed on the stick.

## Troubleshooting

- Check the log first: `cat /var/log/e3372-switch.log`
- Check the USB mode: `system_profiler SPUSBHostDataType | grep -A8 HUAWEI`.
  `Product ID: 0x1f01` means it is still in CD mode. `0x14dc` means network mode.
- If the network mode is up but there is no internet, open the stick's web page
  and check the SIM, PIN, APN and signal there.
- A stick with "Stick" (non-HiLink) firmware switches to a different ID
  (`0x1506`, NCM + serial ports). This repo does not handle that case.

## Uninstall

```bash
sudo /usr/local/libexec/e3372-uninstall
```

(or `./uninstall.sh` from a source checkout)

This removes the tool, the LaunchDaemon, the log and the app. The stick itself is not
changed: it still starts in CD mode on any computer. To also remove its network
service, open System Settings › Network, select it and click **−**.

## Build only

```bash
make            # → build/e3372-switch
make app        # → build/E3372 Modem.app
make pkg        # → build/Huawei-E3372-1.1.0.pkg
```
