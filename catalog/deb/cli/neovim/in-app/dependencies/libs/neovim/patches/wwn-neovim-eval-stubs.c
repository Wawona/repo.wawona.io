/* Stubs for Vim test/assertion helpers not shipped on Apple mobile.
 * nvim_eval_funcs.c still references these symbols; zsh's Test/ tree is not
 * archived into libwawona-zsh.a. Provide no-op definitions for link closure. */
#include <stddef.h>

#define STUB(name) void name(void) {}

STUB(f_assert_beeps)
STUB(f_assert_equal)
STUB(f_assert_equalfile)
STUB(f_assert_exception)
STUB(f_assert_fails)
STUB(f_assert_false)
STUB(f_assert_inrange)
STUB(f_assert_match)
STUB(f_assert_nobeep)
STUB(f_assert_notequal)
STUB(f_assert_notmatch)
STUB(f_assert_report)
STUB(f_assert_true)
STUB(f_test_garbagecollect_now)
STUB(f_test_write_list_log)
