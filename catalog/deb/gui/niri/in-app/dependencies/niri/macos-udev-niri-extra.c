/* Appended onto iland udev.c for smithay udev crate. */
struct udev *udev_ref(struct udev *u) {
  if (u)
    u->refcount++;
  return u;
}

struct udev *udev_device_get_udev(struct udev_device *d) {
  (void)d;
  return udev_new();
}
