VERSION = 1.1.0
LIBUSB_PREFIX ?= $(shell brew --prefix libusb 2>/dev/null || echo /opt/homebrew)
CFLAGS  = -O2 -Wall -arch arm64 -mmacosx-version-min=12.0 -I$(LIBUSB_PREFIX)/include/libusb-1.0
LDLIBS  = $(LIBUSB_PREFIX)/lib/libusb-1.0.a -framework IOKit -framework CoreFoundation -framework Security
PKG     = Huawei-E3372-$(VERSION).pkg

build/e3372-switch: src/e3372-switch.c
	@mkdir -p build
	$(CC) $(CFLAGS) $< $(LDLIBS) -o $@ 2>&1 | grep -v 'was built for newer' || true
	@test -x $@

APP_SOURCES = $(wildcard app/Sources/E3372Modem/*.swift) app/Package.swift app/bundle.sh app/tools/make-icon.swift

# The E3372 Modem app (dialer, USSD, SMS, status).
app: build/E3372\ Modem.app/Contents/MacOS/E3372Modem

build/E3372\ Modem.app/Contents/MacOS/E3372Modem: $(APP_SOURCES)
	app/bundle.sh

# Installer package for people without Homebrew or the Command Line Tools.
pkg: build/$(PKG)

build/$(PKG): build/e3372-switch app com.huawei-e3372.switch.plist uninstall.sh pkg/scripts/postinstall
	rm -rf build/root
	mkdir -p build/root/usr/local/libexec build/root/Library/LaunchDaemons build/root/Applications
	cp build/e3372-switch build/root/usr/local/libexec/
	cp uninstall.sh build/root/usr/local/libexec/e3372-uninstall
	cp com.huawei-e3372.switch.plist build/root/Library/LaunchDaemons/
	cp -R "build/E3372 Modem.app" build/root/Applications/
	# Install the app in /Applications even if a copy with the same bundle ID
	# exists elsewhere (pkgbuild otherwise "relocates" onto that copy).
	pkgbuild --analyze --root build/root build/components.plist
	plutil -replace 0.BundleIsRelocatable -bool NO build/components.plist
	pkgbuild --root build/root --component-plist build/components.plist --scripts pkg/scripts \
		--identifier com.huawei-e3372.switch --version $(VERSION) --ownership recommended $@

clean:
	rm -rf build

.PHONY: app pkg clean
