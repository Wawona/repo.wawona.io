/* Minimal wl_shm + xdg_wm_base client for Wawona. Process binary, no App Store patches.
 * Speaks the same protocols as classic weston clients/simple-shm. */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <wayland-client.h>

/* Generated protocol headers come from wayland-scanner at build time. */
#include "xdg-shell-client-protocol.h"

static struct wl_display *display;
static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct xdg_wm_base *xdg_wm_base;
static int running = 1;

static void
xdg_wm_base_ping(void *data, struct xdg_wm_base *wm_base, uint32_t serial)
{
	(void)data;
	xdg_wm_base_pong(wm_base, serial);
}

static const struct xdg_wm_base_listener xdg_wm_base_listener = {
	.ping = xdg_wm_base_ping,
};

static void
registry_global(void *data, struct wl_registry *registry, uint32_t name,
		const char *interface, uint32_t version)
{
	(void)data;
	(void)version;
	if (strcmp(interface, "wl_compositor") == 0) {
		compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 4);
	} else if (strcmp(interface, "wl_shm") == 0) {
		shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
	} else if (strcmp(interface, "xdg_wm_base") == 0) {
		xdg_wm_base = wl_registry_bind(registry, name, &xdg_wm_base_interface, 1);
		xdg_wm_base_add_listener(xdg_wm_base, &xdg_wm_base_listener, NULL);
	}
}

static void
registry_global_remove(void *data, struct wl_registry *registry, uint32_t name)
{
	(void)data;
	(void)registry;
	(void)name;
}

static const struct wl_registry_listener registry_listener = {
	.global = registry_global,
	.global_remove = registry_global_remove,
};

static void
xdg_surface_configure(void *data, struct xdg_surface *xdg_surface, uint32_t serial)
{
	(void)data;
	xdg_surface_ack_configure(xdg_surface, serial);
}

static const struct xdg_surface_listener xdg_surface_listener = {
	.configure = xdg_surface_configure,
};

static void
xdg_toplevel_configure(void *data, struct xdg_toplevel *toplevel, int32_t width,
		       int32_t height, struct wl_array *states)
{
	(void)data;
	(void)toplevel;
	(void)width;
	(void)height;
	(void)states;
}

static void
xdg_toplevel_close(void *data, struct xdg_toplevel *toplevel)
{
	(void)data;
	(void)toplevel;
	running = 0;
}

static const struct xdg_toplevel_listener xdg_toplevel_listener = {
	.configure = xdg_toplevel_configure,
	.close = xdg_toplevel_close,
};

static int
create_shm_file(size_t size)
{
	int fd = -1;
#if defined(__linux__) && defined(__NR_memfd_create)
	/* Prefer memfd on Android/Termux and modern Linux (no /dev/shm needed). */
	fd = (int)syscall(__NR_memfd_create, "weston-simple-shm", 0);
#endif
#if !defined(__ANDROID__)
	/* POSIX shm_open is not in Bionic; Termux uses memfd or libandroid-shmem. */
	if (fd < 0) {
		char name[] = "/weston-simple-shm-XXXXXX";
		fd = shm_open(name, O_RDWR | O_CREAT | O_EXCL, 0600);
		if (fd < 0)
			return -1;
		shm_unlink(name);
	}
#endif
	if (fd < 0)
		return -1;
	if (ftruncate(fd, (off_t)size) < 0) {
		close(fd);
		return -1;
	}
	return fd;
}

int
main(int argc, char **argv)
{
	(void)argc;
	(void)argv;
	display = wl_display_connect(NULL);
	if (!display) {
		fprintf(stderr, "weston-simple-shm: failed to connect to Wayland display\n");
		return 1;
	}

	struct wl_registry *registry = wl_display_get_registry(display);
	wl_registry_add_listener(registry, &registry_listener, NULL);
	wl_display_roundtrip(display);

	if (!compositor || !shm || !xdg_wm_base) {
		fprintf(stderr, "weston-simple-shm: missing globals (compositor/shm/xdg_wm_base)\n");
		return 1;
	}

	const int width = 320;
	const int height = 240;
	const int stride = width * 4;
	const size_t size = (size_t)stride * (size_t)height;
	int fd = create_shm_file(size);
	if (fd < 0) {
		perror("shm");
		return 1;
	}
	void *data = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (data == MAP_FAILED) {
		perror("mmap");
		return 1;
	}
	uint32_t *pixels = data;
	for (int y = 0; y < height; ++y) {
		for (int x = 0; x < width; ++x) {
			uint8_t r = (uint8_t)(x * 255 / width);
			uint8_t g = (uint8_t)(y * 255 / height);
			uint8_t b = 64;
			pixels[y * width + x] = (0xffu << 24) | ((uint32_t)r << 16) | ((uint32_t)g << 8) | b;
		}
	}

	struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, (int32_t)size);
	struct wl_buffer *buffer = wl_shm_pool_create_buffer(pool, 0, width, height, stride, WL_SHM_FORMAT_ARGB8888);
	struct wl_surface *surface = wl_compositor_create_surface(compositor);
	struct xdg_surface *xdg_surface = xdg_wm_base_get_xdg_surface(xdg_wm_base, surface);
	xdg_surface_add_listener(xdg_surface, &xdg_surface_listener, NULL);
	struct xdg_toplevel *toplevel = xdg_surface_get_toplevel(xdg_surface);
	xdg_toplevel_add_listener(toplevel, &xdg_toplevel_listener, NULL);
	xdg_toplevel_set_title(toplevel, "weston-simple-shm");
	wl_surface_commit(surface);
	wl_display_roundtrip(display);

	wl_surface_attach(surface, buffer, 0, 0);
	wl_surface_damage(surface, 0, 0, width, height);
	wl_surface_commit(surface);

	while (running && wl_display_dispatch(display) != -1) {
	}

	munmap(data, size);
	close(fd);
	wl_display_disconnect(display);
	return 0;
}
