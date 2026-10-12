#include "codec.h"

/*
 * watchOS has no VideoToolbox framework, so the VideoToolbox-based
 * codec_apple.c cannot compile there. Report no hardware codecs instead.
 */
const char* ffDetectCodecNative(FFCodecOptions* options, FFlist* result) {
    (void)options;
    (void)result;
    return NULL;
}
