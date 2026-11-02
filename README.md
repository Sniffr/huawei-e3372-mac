# Huawei E3372 on Apple-silicon Macs

This gets a Huawei E3372 LTE USB stick with **HiLink** firmware online on an
Apple-silicon Mac. It needs no kernel extension and no Huawei software.

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

## Install

Requires the Xcode Command Line Tools (`xcode-select --install`) and
Homebrew. libusb is used only at build time; the installer runs
`brew install libusb` for you if it is missing.

```bash
~/huawei-e3372/install.sh
```

It asks for your password once. It installs:

| File | Purpose |
|---|---|
| `/usr/local/libexec/e3372-switch` | the switch tool |
| `/Library/LaunchDaemons/com.huawei-e3372.switch.plist` | runs it on plug-in |
| `/var/log/e3372-switch.log` | what it did |

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
~/huawei-e3372/uninstall.sh
```

This removes the tool, the LaunchDaemon and the log. The stick itself is not
changed: it still starts in CD mode on any computer. To also remove its network
service, open System Settings › Network, select it and click **−**.

## Build only

```bash
make            # → build/e3372-switch
```
