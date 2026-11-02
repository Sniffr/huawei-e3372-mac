/*
 * e3372-switch: take a Huawei E3372 HiLink stick out of its virtual-CD mode.
 *
 * Out of the box the stick enumerates as 12d1:1f01, a USB mass-storage
 * device holding Huawei's (Intel-only) installer.  Huawei's vendor SCSI
 * command, wrapped in a Bulk-Only CBW, makes it re-enumerate as 12d1:14dc,
 * a CDC-ECM Ethernet adapter that macOS drives natively, no kext needed.
 * This is the message usb_modeswitch sends for this stick (HuaweiNewMode).
 *
 * Taking the interface away from macOS's mass-storage driver needs root,
 * so this runs from a LaunchDaemon that launchd starts whenever a 12d1:1f01
 * device appears.  Run by hand:  sudo e3372-switch
 * From launchd:                  e3372-switch --launchd
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dispatch/dispatch.h>
#include <xpc/xpc.h>
#include <libusb.h>

#define VID_HUAWEI   0x12d1
#define PID_STORAGE  0x1f01
#define PID_HILINK   0x14dc

/* 55534243 12345678 00000000 00 00 0a | 11 06 20 00 00 00 00 00 01 00 ... */
static const unsigned char switch_msg[31] = {
	0x55, 0x53, 0x42, 0x43,		/* dCBWSignature "USBC" */
	0x12, 0x34, 0x56, 0x78,		/* dCBWTag */
	0x00, 0x00, 0x00, 0x00,		/* dCBWDataTransferLength */
	0x00,				/* bmCBWFlags */
	0x00,				/* bCBWLUN */
	0x0a,				/* bCBWCBLength */
	0x11, 0x06, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};

static int find_out_endpoint(libusb_device *dev, int *iface, unsigned char *ep)
{
	struct libusb_config_descriptor *cfg;
	if (libusb_get_active_config_descriptor(dev, &cfg) != 0 &&
	    libusb_get_config_descriptor(dev, 0, &cfg) != 0)
		return -1;
	for (int i = 0; i < cfg->bNumInterfaces; i++) {
		const struct libusb_interface_descriptor *alt = &cfg->interface[i].altsetting[0];
		if (alt->bInterfaceClass != LIBUSB_CLASS_MASS_STORAGE)
			continue;
		for (int e = 0; e < alt->bNumEndpoints; e++) {
			const struct libusb_endpoint_descriptor *d = &alt->endpoint[e];
			if ((d->bmAttributes & 3) == LIBUSB_TRANSFER_TYPE_BULK &&
			    !(d->bEndpointAddress & LIBUSB_ENDPOINT_IN)) {
				*iface = alt->bInterfaceNumber;
				*ep = d->bEndpointAddress;
				libusb_free_config_descriptor(cfg);
				return 0;
			}
		}
	}
	libusb_free_config_descriptor(cfg);
	return -1;
}

/* Returns 0 if a stick was switched or none needed switching. */
static int switch_stick(void)
{
	libusb_context *ctx;
	if (libusb_init(&ctx) != 0) {
		fprintf(stderr, "libusb_init failed\n");
		return 1;
	}

	libusb_device_handle *h = libusb_open_device_with_vid_pid(ctx, VID_HUAWEI, PID_STORAGE);
	if (!h) {
		libusb_device_handle *n = libusb_open_device_with_vid_pid(ctx, VID_HUAWEI, PID_HILINK);
		printf(n ? "E3372 already in network mode\n" : "No E3372 in storage mode found\n");
		if (n)
			libusb_close(n);
		libusb_exit(ctx);
		return 0;
	}

	int rc = 1, iface;
	unsigned char ep;
	if (find_out_endpoint(libusb_get_device(h), &iface, &ep) != 0) {
		fprintf(stderr, "no mass-storage bulk OUT endpoint found\n");
		goto out;
	}

	/* macOS's mass-storage driver owns the interface; libusb takes it (root only). */
	libusb_set_auto_detach_kernel_driver(h, 1);
	int r = libusb_claim_interface(h, iface);
	if (r != 0) {
		fprintf(stderr, "claim interface %d: %s%s\n", iface, libusb_strerror(r),
			r == LIBUSB_ERROR_ACCESS ? " (run as root)" : "");
		goto out;
	}

	int sent = 0;
	r = libusb_bulk_transfer(h, ep, (unsigned char *)switch_msg, sizeof switch_msg, &sent, 2000);
	if (r != 0 || sent != (int)sizeof switch_msg) {
		fprintf(stderr, "send switch message: %s\n", libusb_strerror(r));
		libusb_release_interface(h, iface);
		goto out;
	}
	/* The stick detaches right after this; errors from here on don't matter. */
	libusb_release_interface(h, iface);
	printf("Switch message sent; the E3372 will reappear as a network adapter\n");
	rc = 0;
out:
	libusb_close(h);
	libusb_exit(ctx);
	return rc;
}

/* Wait for the stick to come back as a network adapter, then let macOS add
 * a network service for it (it otherwise only does that interactively). */
static void register_interface(void)
{
	for (int i = 0; i < 20; i++) {
		sleep(1);
		libusb_context *ctx;
		if (libusb_init(&ctx) != 0)
			break;
		libusb_device_handle *n = libusb_open_device_with_vid_pid(ctx, VID_HUAWEI, PID_HILINK);
		if (n)
			libusb_close(n);
		libusb_exit(ctx);
		if (n) {
			sleep(3);	/* let the Ethernet interface attach */
			system("/usr/sbin/networksetup -detectnewhardware");
			return;
		}
	}
	fprintf(stderr, "E3372 did not come back as a network adapter\n");
}

int main(int argc, char **argv)
{
	setvbuf(stdout, NULL, _IOLBF, 0);

	if (argc > 1 && strcmp(argv[1], "--launchd") == 0) {
		/* launchd keeps relaunching us until the IOKit match event is consumed. */
		xpc_set_event_stream_handler("com.apple.iokit.matching", dispatch_get_main_queue(),
					     ^(xpc_object_t event) { (void)event; });
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
			if (switch_stick() == 0)
				register_interface();
			exit(0);
		});
		dispatch_main();
	}

	int rc = switch_stick();
	if (rc == 0 && geteuid() == 0)
		register_interface();
	return rc;
}
