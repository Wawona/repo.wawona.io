/* Minimal <linux/input.h> for wasi.
 *
 * GTK4's GDK Wayland backend includes <linux/input.h> unconditionally and
 * uses the mouse/tablet button codes below. The real kernel header pulls in
 * <linux/types.h> (and asm/types.h) and ioctls that do not exist on wasi, so
 * provide just the constants. Values are from
 * linux/input-event-codes.h (stable UAPI).
 */
#ifndef _WASIX_LINUX_INPUT_H
#define _WASIX_LINUX_INPUT_H

#define BTN_LEFT 0x110
#define BTN_RIGHT 0x111
#define BTN_MIDDLE 0x112
#define BTN_SIDE 0x113
#define BTN_EXTRA 0x114
#define BTN_FORWARD 0x115
#define BTN_BACK 0x116
#define BTN_TASK 0x117

#define BTN_TOOL_PEN 0x140
#define BTN_TOOL_RUBBER 0x141
#define BTN_TOOL_BRUSH 0x142
#define BTN_TOOL_PENCIL 0x143
#define BTN_TOOL_AIRBRUSH 0x144
#define BTN_TOOL_FINGER 0x145
#define BTN_TOOL_MOUSE 0x146
#define BTN_TOOL_LENS 0x147
#define BTN_TOOL_QUINTTAP 0x148
#define BTN_STYLUS3 0x149
#define BTN_TOUCH 0x14a
#define BTN_STYLUS 0x14b
#define BTN_STYLUS2 0x14c
#define BTN_TOOL_DOUBLETAP 0x14d
#define BTN_TOOL_TRIPLETAP 0x14e
#define BTN_TOOL_QUADTAP 0x14f

#endif /* _WASIX_LINUX_INPUT_H */
