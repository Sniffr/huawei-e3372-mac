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
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <spawn.h>
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

static int find_endpoints(libusb_device *dev, int *iface, unsigned char *ep_out, unsigned char *ep_in)
{
	struct libusb_config_descriptor *cfg;
	if (libusb_get_active_config_descriptor(dev, &cfg) != 0 &&
	    libusb_get_config_descriptor(dev, 0, &cfg) != 0)
		return -1;
	for (int i = 0; i < cfg->bNumInterfaces; i++) {
		const struct libusb_interface_descriptor *alt = &cfg->interface[i].altsetting[0];
		if (alt->bInterfaceClass != LIBUSB_CLASS_MASS_STORAGE)
			continue;
		*ep_out = *ep_in = 0;
		for (int e = 0; e < alt->bNumEndpoints; e++) {
			const struct libusb_endpoint_descriptor *d = &alt->endpoint[e];
			if ((d->bmAttributes & 3) != LIBUSB_TRANSFER_TYPE_BULK)
				continue;
			if (d->bEndpointAddress & LIBUSB_ENDPOINT_IN)
				*ep_in = d->bEndpointAddress;
			else
				*ep_out = d->bEndpointAddress;
		}
		if (*ep_out) {
			*iface = alt->bInterfaceNumber;
			libusb_free_config_descriptor(cfg);
			return 0;
		}
	}
	libusb_free_config_descriptor(cfg);
	return -1;
}

#define RETRY (-1)

/* Returns 0 if a stick was switched or none needed switching, RETRY if the
 * interface could not be taken over yet. */
static int try_switch(int attempt, int last)
{
	int quiet_retry = !last;
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

	if (last)
		libusb_set_option(ctx, LIBUSB_OPTION_LOG_LEVEL, LIBUSB_LOG_LEVEL_DEBUG);

	int rc = 1, iface;
	unsigned char ep, ep_in;
	if (find_endpoints(libusb_get_device(h), &iface, &ep, &ep_in) != 0) {
		fprintf(stderr, "no mass-storage bulk OUT endpoint found\n");
		goto out;
	}

	/* Capture the device (root only): macOS re-enumerates it with this process
	 * as owner, so macOS's mass-storage driver lets go.  Do it even when no
	 * kernel driver shows as attached, because a capture left over from an
	 * earlier run also blocks the claim, and only a new capture clears it. */
	int r = libusb_detach_kernel_driver(h, iface);
	if (r != 0 && last)
		fprintf(stderr, "detach kernel driver: %s\n", libusb_strerror(r));
	r = libusb_claim_interface(h, iface);
	if (r != 0) {
		if (r == LIBUSB_ERROR_ACCESS)
			fprintf(stderr, "claim interface %d: %s (run as root)\n", iface, libusb_strerror(r));
		else {
			if (!quiet_retry)
				fprintf(stderr, "claim interface %d: %s\n", iface, libusb_strerror(r));
			rc = RETRY;
		}
		goto out;
	}

	int sent = 0;
	r = libusb_bulk_transfer(h, ep, (unsigned char *)switch_msg, sizeof switch_msg, &sent, 2000);
	if (r != 0 || sent != (int)sizeof switch_msg) {
		fprintf(stderr, "send switch message: %s\n", libusb_strerror(r));
		libusb_release_interface(h, iface);
		goto out;
	}
	/* Read the command status, as usb_modeswitch does, then give the stick
	 * time to drop off the bus.  Releasing the interface hands it back to
	 * macOS, which resets the device; doing that too early cancels the
	 * switch.  Errors from here on are expected and harmless. */
	if (ep_in) {
		unsigned char csw[13];
		libusb_bulk_transfer(h, ep_in, csw, sizeof csw, &sent, 1000);
	}
	sleep(5);
	libusb_release_interface(h, iface);
	printf("Switch message sent; the E3372 will reappear as a network adapter\n");
	rc = 0;
out:
	libusb_close(h);
	libusb_exit(ctx);
	return rc;
}

/* Right after plug-in macOS is still attaching its storage driver and the
 * takeover fails, so keep trying for a while with a fresh handle each time. */
static int switch_stick(void)
{
	for (int attempt = 1; attempt <= 15; attempt++) {
		int rc = try_switch(attempt, attempt == 15);
		if (rc != RETRY)
			return rc;
		sleep(1);
	}
	return 1;
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
		xpc_set_event_stream_handler("com.apple.iokit.matching",
					     dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0),
					     ^(xpc_object_t event) { (void)event; });

		/* From a LaunchDaemon, macOS refuses to open the stick's interface
		 * ("out of resources") even as root; from root inside the logged-in
		 * user's session it works.  So run the switch there when someone is
		 * logged in at the console. */
		struct stat st;
		if (stat("/dev/console", &st) == 0 && st.st_uid != 0) {
			char uid[16];
			snprintf(uid, sizeof uid, "%u", st.st_uid);
			char *args[] = { "launchctl", "asuser", uid, argv[0], NULL };
			pid_t pid;
			int status = 1;
			if (posix_spawn(&pid, "/bin/launchctl", NULL, NULL, args, NULL) == 0 &&
			    waitpid(pid, &status, 0) == pid)
				return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
			fprintf(stderr, "could not run in the user session; trying directly\n");
		}
	}

	/* Plug-in events and manual runs can overlap; one switch at a time. */
	int lock = open("/tmp/e3372-switch.lock", O_RDONLY | O_CREAT, 0644);
	if (lock >= 0)
		flock(lock, LOCK_EX);

	int rc = switch_stick();
	if (rc != 0)
		fprintf(stderr, "switch failed\n");
	if (rc == 0 && geteuid() == 0)
		register_interface();
	return rc;
}
