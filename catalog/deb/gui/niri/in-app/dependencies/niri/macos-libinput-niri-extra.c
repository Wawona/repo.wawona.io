/* Appended onto iland libinput.c (structs already in that TU).
 * smithay/input-sys 1.21 binds the full Linux libinput ABI. The iland
 * shim covers weston's subset; these are the extra symbols niri Tty needs.
 * Gesture/switch/pad events are never emitted, so those getters stay NULL/0.
 */
#include <stddef.h>

struct libinput_event_gesture;
struct libinput_event_switch;
struct libinput_event_tablet_pad;
struct libinput_event_device_notify;

struct libinput *libinput_ref(struct libinput *l) { return l; }

int libinput_device_get_size(struct libinput_device *d, double *w, double *h) {
  (void)d;
  if (w) *w = 0;
  if (h) *h = 0;
  return -1;
}

int libinput_device_config_accel_get_default_profile(struct libinput_device *d) {
  (void)d;
  return LIBINPUT_CONFIG_ACCEL_PROFILE_ADAPTIVE;
}
int libinput_device_config_click_get_default_method(struct libinput_device *d) {
  (void)d;
  return 0;
}
int libinput_device_config_click_set_method(struct libinput_device *d, int m) {
  (void)d;
  (void)m;
  return LIBINPUT_CONFIG_STATUS_SUCCESS;
}
int libinput_device_config_dwtp_set_enabled(struct libinput_device *d, int e) {
  (void)d;
  (void)e;
  return LIBINPUT_CONFIG_STATUS_SUCCESS;
}
int libinput_device_config_scroll_get_default_method(struct libinput_device *d) {
  (void)d;
  return LIBINPUT_CONFIG_SCROLL_2FG;
}
int libinput_device_config_scroll_get_natural_scroll_enabled(
    struct libinput_device *d) {
  (void)d;
  return 0;
}
int libinput_device_config_scroll_set_button_lock(struct libinput_device *d,
                                                  int e) {
  (void)d;
  (void)e;
  return LIBINPUT_CONFIG_STATUS_SUCCESS;
}
int libinput_device_config_send_events_set_mode(struct libinput_device *d,
                                                int m) {
  (void)d;
  (void)m;
  return LIBINPUT_CONFIG_STATUS_SUCCESS;
}
int libinput_device_config_tap_get_default_button_map(struct libinput_device *d) {
  (void)d;
  return 0;
}
int libinput_device_config_tap_get_default_drag_enabled(
    struct libinput_device *d) {
  (void)d;
  return 0;
}
int libinput_device_config_tap_set_button_map(struct libinput_device *d, int m) {
  (void)d;
  (void)m;
  return LIBINPUT_CONFIG_STATUS_SUCCESS;
}

#define BASE(ptr, member)                                                      \
  ((ptr) ? (struct libinput_event *)((char *)(ptr) -                           \
                                     offsetof(struct libinput_event, member))  \
         : NULL)

struct libinput_event *
libinput_event_keyboard_get_base_event(struct libinput_event_keyboard *e) {
  return BASE(e, keyboard);
}
struct libinput_event *
libinput_event_pointer_get_base_event(struct libinput_event_pointer *e) {
  return BASE(e, pointer);
}
struct libinput_event *
libinput_event_touch_get_base_event(struct libinput_event_touch *e) {
  return BASE(e, touch);
}
struct libinput_event *
libinput_event_tablet_tool_get_base_event(struct libinput_event_tablet_tool *e) {
  return BASE(e, tablet);
}
struct libinput_event *
libinput_event_gesture_get_base_event(struct libinput_event_gesture *e) {
  (void)e;
  return NULL;
}
struct libinput_event *
libinput_event_switch_get_base_event(struct libinput_event_switch *e) {
  (void)e;
  return NULL;
}
struct libinput_event *
libinput_event_tablet_pad_get_base_event(struct libinput_event_tablet_pad *e) {
  (void)e;
  return NULL;
}
struct libinput_event *libinput_event_device_notify_get_base_event(
    struct libinput_event_device_notify *e) {
  return (struct libinput_event *)e;
}

struct libinput_event_device_notify *
libinput_event_get_device_notify_event(struct libinput_event *e) {
  return (struct libinput_event_device_notify *)e;
}
struct libinput_event_gesture *
libinput_event_get_gesture_event(struct libinput_event *e) {
  (void)e;
  return NULL;
}
struct libinput_event_switch *
libinput_event_get_switch_event(struct libinput_event *e) {
  (void)e;
  return NULL;
}
struct libinput_event_tablet_pad *
libinput_event_get_tablet_pad_event(struct libinput_event *e) {
  (void)e;
  return NULL;
}

double libinput_event_gesture_get_angle_delta(struct libinput_event_gesture *e) {
  (void)e;
  return 0;
}
int libinput_event_gesture_get_cancelled(struct libinput_event_gesture *e) {
  (void)e;
  return 0;
}
double libinput_event_gesture_get_dx(struct libinput_event_gesture *e) {
  (void)e;
  return 0;
}
double libinput_event_gesture_get_dx_unaccelerated(
    struct libinput_event_gesture *e) {
  (void)e;
  return 0;
}
double libinput_event_gesture_get_dy(struct libinput_event_gesture *e) {
  (void)e;
  return 0;
}
double libinput_event_gesture_get_dy_unaccelerated(
    struct libinput_event_gesture *e) {
  (void)e;
  return 0;
}
int libinput_event_gesture_get_finger_count(struct libinput_event_gesture *e) {
  (void)e;
  return 0;
}
double libinput_event_gesture_get_scale(struct libinput_event_gesture *e) {
  (void)e;
  return 1.0;
}
uint64_t libinput_event_gesture_get_time_usec(struct libinput_event_gesture *e) {
  (void)e;
  return 0;
}

double libinput_event_pointer_get_scroll_value(struct libinput_event_pointer *e,
                                               int axis) {
  return libinput_event_pointer_get_axis_value(
      e, (enum libinput_pointer_axis)axis);
}
double libinput_event_pointer_get_scroll_value_v120(
    struct libinput_event_pointer *e, int axis) {
  return libinput_event_pointer_get_axis_value_discrete(
      e, (enum libinput_pointer_axis)axis);
}

int libinput_event_switch_get_switch(struct libinput_event_switch *e) {
  (void)e;
  return 0;
}
int libinput_event_switch_get_switch_state(struct libinput_event_switch *e) {
  (void)e;
  return 0;
}

double libinput_event_tablet_tool_get_rotation(
    struct libinput_event_tablet_tool *e) {
  (void)e;
  return 0;
}
double libinput_event_tablet_tool_get_slider_position(
    struct libinput_event_tablet_tool *e) {
  (void)e;
  return 0;
}
uint64_t libinput_event_tablet_tool_get_time_usec(
    struct libinput_event_tablet_tool *e) {
  return e ? e->time : 0;
}
double libinput_event_tablet_tool_get_wheel_delta(
    struct libinput_event_tablet_tool *e) {
  (void)e;
  return 0;
}
int libinput_event_tablet_tool_get_wheel_delta_discrete(
    struct libinput_event_tablet_tool *e) {
  (void)e;
  return 0;
}
int libinput_event_tablet_tool_rotation_has_changed(
    struct libinput_event_tablet_tool *e) {
  (void)e;
  return 0;
}
int libinput_event_tablet_tool_slider_has_changed(
    struct libinput_event_tablet_tool *e) {
  (void)e;
  return 0;
}
int libinput_event_tablet_tool_wheel_has_changed(
    struct libinput_event_tablet_tool *e) {
  (void)e;
  return 0;
}

int32_t libinput_event_touch_get_slot(struct libinput_event_touch *e) {
  return e ? e->seat_slot : -1;
}

int libinput_tablet_tool_has_rotation(struct libinput_tablet_tool *t) {
  (void)t;
  return 0;
}
int libinput_tablet_tool_has_slider(struct libinput_tablet_tool *t) {
  (void)t;
  return 0;
}
int libinput_tablet_tool_has_wheel(struct libinput_tablet_tool *t) {
  (void)t;
  return 0;
}
struct libinput_tablet_tool *
libinput_tablet_tool_ref(struct libinput_tablet_tool *t) {
  return t;
}
struct libinput_tablet_tool *
libinput_tablet_tool_unref(struct libinput_tablet_tool *t) {
  (void)t;
  return NULL;
}
