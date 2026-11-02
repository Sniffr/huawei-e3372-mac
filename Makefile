LIBUSB_PREFIX ?= $(shell brew --prefix libusb 2>/dev/null || echo /opt/homebrew)
CFLAGS  = -O2 -Wall -arch arm64 -I$(LIBUSB_PREFIX)/include/libusb-1.0
LDLIBS  = $(LIBUSB_PREFIX)/lib/libusb-1.0.a -framework IOKit -framework CoreFoundation -framework Security

build/e3372-switch: src/e3372-switch.c
	@mkdir -p build
	$(CC) $(CFLAGS) $< $(LDLIBS) -o $@

clean:
	rm -rf build

.PHONY: clean
