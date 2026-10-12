/*
 * Standalone weston_log()/weston_log_set_handler() for the in-process client
 * toytoolkit build (android.nix / ios.nix). mobile-weston-host-clients.c and
 * wwn-weston-log.c extern-declare these expecting the *real* libweston
 * implementation (libweston/log.c) to provide them - true when this file is
 * staged into a full libweston build (macos.nix), but there is no such build
 * on the client-only mobile toytoolkit path.
 *
 * Keep this shim in the toytoolkit archive, but export weak symbols. Toytoolkit
 * clients need logging when linked without the compositor; when Wawona also
 * links the real nested-compositor archive, libweston/log.c provides the strong
 * symbols and wins.
 */

#include <stdarg.h>
#include <stdio.h>

typedef int (*wwn_weston_log_func_t)(const char *fmt, va_list ap);

static wwn_weston_log_func_t g_wwn_log_handler;
static wwn_weston_log_func_t g_wwn_log_continue_handler;

__attribute__((weak)) void
weston_log_set_handler(wwn_weston_log_func_t log, wwn_weston_log_func_t cont)
{
	g_wwn_log_handler = log;
	g_wwn_log_continue_handler = cont;
}

__attribute__((weak)) int
weston_log(const char *fmt, ...)
{
	va_list ap;
	int ret;

	va_start(ap, fmt);
	ret = g_wwn_log_handler ? g_wwn_log_handler(fmt, ap)
				: vfprintf(stderr, fmt, ap);
	va_end(ap);
	return ret;
}

__attribute__((weak)) int
weston_log_continue(const char *fmt, ...)
{
	va_list ap;
	int ret;

	va_start(ap, fmt);
	ret = g_wwn_log_continue_handler ? g_wwn_log_continue_handler(fmt, ap)
					  : vfprintf(stderr, fmt, ap);
	va_end(ap);
	return ret;
}
