/* phoon-rs C ABI — in-process entry point for the Wawona shell dispatcher.
 *
 * Link libphoon_rs.a (Apple mobile / static) or libphoon_rs.so (Android) and
 * call phoon_main exactly as a C `main`. Declared weak by the dispatcher so
 * builds without phoon still link. Mirrors waypipe_main / fastfetch_main.
 */
#ifndef WWN_PHOON_H
#define WWN_PHOON_H

#ifdef __cplusplus
extern "C" {
#endif

/* Runs the phoon CLI: `phoon [-l <lines>] [<date/time>]`. Returns the process
 * exit code (0 success, 1 usage/illegal-date). Writes the moon to stdout. */
int phoon_main(int argc, char **argv);

#ifdef __cplusplus
}
#endif

#endif /* WWN_PHOON_H */
