#include "host.h"
#include "common/sysctl.h"
#include "common/strutil.h"

/*
 * Sandbox-safe host detection for Apple mobile.
 *
 * The macOS path (host_apple.c) walks the IORegistry for serial/UUID/product
 * name; those calls are blocked/crash in the iOS sandbox. Instead we read the
 * device identifier from sysctl(hw.machine) (e.g. "iPhone14,5") and map it to a
 * marketing name where known, falling back to the raw identifier. No serial or
 * UUID is exposed (privacy + sandbox).
 */

typedef struct FFAppleModelName {
    const char* id;
    const char* name;
} FFAppleModelName;

static const FFAppleModelName modelNames[] = {
    // iPhone
    { "iPhone12,1", "iPhone 11" },
    { "iPhone12,3", "iPhone 11 Pro" },
    { "iPhone12,5", "iPhone 11 Pro Max" },
    { "iPhone12,8", "iPhone SE (2nd generation)" },
    { "iPhone13,1", "iPhone 12 mini" },
    { "iPhone13,2", "iPhone 12" },
    { "iPhone13,3", "iPhone 12 Pro" },
    { "iPhone13,4", "iPhone 12 Pro Max" },
    { "iPhone14,2", "iPhone 13 Pro" },
    { "iPhone14,3", "iPhone 13 Pro Max" },
    { "iPhone14,4", "iPhone 13 mini" },
    { "iPhone14,5", "iPhone 13" },
    { "iPhone14,6", "iPhone SE (3rd generation)" },
    { "iPhone14,7", "iPhone 14" },
    { "iPhone14,8", "iPhone 14 Plus" },
    { "iPhone15,2", "iPhone 14 Pro" },
    { "iPhone15,3", "iPhone 14 Pro Max" },
    { "iPhone15,4", "iPhone 15" },
    { "iPhone15,5", "iPhone 15 Plus" },
    { "iPhone16,1", "iPhone 15 Pro" },
    { "iPhone16,2", "iPhone 15 Pro Max" },
    { "iPhone17,1", "iPhone 16 Pro" },
    { "iPhone17,2", "iPhone 16 Pro Max" },
    { "iPhone17,3", "iPhone 16" },
    { "iPhone17,4", "iPhone 16 Plus" },
    { "iPhone17,5", "iPhone 16e" },
    { "iPhone18,1", "iPhone 17 Pro" },
    { "iPhone18,2", "iPhone 17 Pro Max" },
    { "iPhone18,3", "iPhone 17" },
    { "iPhone18,4", "iPhone Air" },
    // iPad
    { "iPad13,1", "iPad Air (4th generation)" },
    { "iPad13,2", "iPad Air (4th generation)" },
    { "iPad13,16", "iPad Air (5th generation)" },
    { "iPad13,17", "iPad Air (5th generation)" },
    { "iPad13,18", "iPad (10th generation)" },
    { "iPad13,19", "iPad (10th generation)" },
    { "iPad14,1", "iPad mini (6th generation)" },
    { "iPad14,2", "iPad mini (6th generation)" },
    { "iPad14,3", "iPad Pro 11-inch (4th generation)" },
    { "iPad14,4", "iPad Pro 11-inch (4th generation)" },
    { "iPad14,5", "iPad Pro 12.9-inch (6th generation)" },
    { "iPad14,6", "iPad Pro 12.9-inch (6th generation)" },
    { "iPad16,3", "iPad Pro 11-inch (M4)" },
    { "iPad16,4", "iPad Pro 11-inch (M4)" },
    { "iPad16,5", "iPad Pro 13-inch (M4)" },
    { "iPad16,6", "iPad Pro 13-inch (M4)" },
    // Apple TV
    { "AppleTV6,2", "Apple TV 4K" },
    { "AppleTV11,1", "Apple TV 4K (2nd generation)" },
    { "AppleTV14,1", "Apple TV 4K (3rd generation)" },
    // Apple Watch
    { "Watch6,1", "Apple Watch Series 6" },
    { "Watch6,6", "Apple Watch Series 7" },
    { "Watch6,10", "Apple Watch Series 8" },
    { "Watch6,14", "Apple Watch Series 9" },
    { "Watch7,1", "Apple Watch Series 10" },
    // Apple Vision
    { "RealityDevice14,1", "Apple Vision Pro" },
};

static const char* getMarketingName(const FFstrbuf* id) {
    for (uint32_t i = 0; i < ARRAY_SIZE(modelNames); ++i) {
        if (ffStrbufEqualS(id, modelNames[i].id))
            return modelNames[i].name;
    }
    return NULL;
}

const char* ffDetectHost(FFHostResult* host) {
    const char* error = ffSysctlGetString("hw.machine", &host->family);
    if (error) {
        error = ffSysctlGetString("hw.model", &host->family);
    }
    if (error) {
        return error;
    }

    const char* marketing = getMarketingName(&host->family);
    if (marketing) {
        ffStrbufSetStatic(&host->name, marketing);
    } else {
        ffStrbufSet(&host->name, &host->family);
    }

    ffStrbufSetStatic(&host->vendor, "Apple Inc.");

    /* IORegistry host probes (serial, UUID) are unavailable in the iOS sandbox. */
    return NULL;
}
