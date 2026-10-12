/*
 * Copyright (c) 2018 Dongseong Hwang <dongseong.hwang@intel.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sub license,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice (including the
 * next paragraph) shall be included in all copies or substantial portions
 * of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

/* Based on a egl cube test app originally written by Arvin Schnell */

#include <getopt.h>
#include <string>

#ifdef WWN_ILAND_EMBEDDED
#include <unistd.h>
#endif

#include "gbm_es2_demo.h"

static const char* shortopts = "AD:M";

static const struct option longopts[] = {{"atomic", no_argument, 0, 'A'},
                                         {"device", required_argument, 0, 'D'},
                                         {"map", no_argument, 0, 'M'},
                                         {0, 0, 0, 0}};

static void usage(const char* name) {
  printf(
      "Usage: %s [-ADMmV]\n"
      "\n"
      "options:\n"
      "    -A, --atomic             use atomic modesetting and fencing\n"
      "    -D, --device=DEVICE      use the given device\n"
      "    -M, --map                mmap test\n",
      name);
}

/* Unmangled entry for in-process Wawona / kmscube-style packaging. */
extern "C" int gbm_es2_demo_main(int argc, char* argv[]) {
  const char* card = "/dev/dri/card0";
  bool atomic = false;
  bool map = false;
  int opt;

#ifdef WWN_ILAND_EMBEDDED
  /* Embedded in the Wawona host, fd 0 is the app's stdin. On Android that is an
   * EOF/closed descriptor, so Run()'s select(fd 0) fires immediately and the
   * demo takes its interactive-exit path after a single frame, then crashes in
   * the software-GPU driver's teardown. A native Linux run has a TTY stdin with
   * no pending keypress, so select() blocks and the cube renders continuously.
   * Reproduce that platform behaviour (a POSIX/stdin substitution, not a client
   * change): point fd 0 at the read end of an empty pipe whose write end we keep
   * open, so stdin never signals readable/EOF and the demo runs until the host
   * tears it down — identical observable behaviour to upstream with no input.
   * iOS/macOS already block on stdin, so this is a no-op safety net there. #140 */
  {
    int sp[2];
    if (pipe(sp) == 0) {
      if (sp[0] != 0) {
        dup2(sp[0], 0);
        close(sp[0]);
      }
      /* Intentionally keep sp[1] open for the client's lifetime: closing it
       * would make the read end report EOF and reintroduce the early exit. */
    }
  }
#endif

  optind = 1;
  while ((opt = getopt_long_only(argc, argv, shortopts, longopts, nullptr)) !=
         -1) {
    switch (opt) {
      case 'A':
        atomic = true;
        break;
      case 'D':
        card = optarg;
        break;
      case 'M':
        map = true;
        break;
      default:
        usage(argv[0]);
        return -1;
    }
  }

  std::unique_ptr<demo::ES2Cube> demo;
  if (map) {
    demo.reset(new demo::ES2CubeMapImpl());
  } else {
    demo.reset(new demo::ES2CubeImpl());
  }
  if (!demo->Initialize(card, atomic)) {
    fprintf(stderr, "failed to initialize ES2Cube.\n");
    return -1;
  }

  if (!demo->Run()) {
    fprintf(stderr, "something wrong happened.\n");
    return -1;
  }

  return 0;
}

/* Standalone CLI entry. In-process archives rename this via -Dmain=… so the
 * host Swift/JNI @main keeps LC_MAIN (see apple-mobile.nix / android.nix). */
int main(int argc, char* argv[]) {
  return gbm_es2_demo_main(argc, argv);
}
