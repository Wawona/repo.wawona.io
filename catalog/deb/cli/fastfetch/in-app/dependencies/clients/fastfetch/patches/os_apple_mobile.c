#include "os.h"
#include "common/sysctl.h"
#include "common/strutil.h"

#include <TargetConditionals.h>

/*
 * Sandbox-safe OS detection for Apple mobile. Reports the correct platform
 * label per target in os->name (iOS/iPadOS/tvOS/watchOS/visionOS). os->id is
 * always "macos" so built-in logo detection matches macOS (Apple logo); see
 * logo/logo.c logoGetBuiltinDetected().
 */
void ffDetectOSImpl(FFOSResult* os) {
#if defined(TARGET_OS_WATCH) && TARGET_OS_WATCH
    ffStrbufSetStatic(&os->name, "watchOS");
#elif defined(TARGET_OS_TV) && TARGET_OS_TV
    ffStrbufSetStatic(&os->name, "tvOS");
#elif defined(TARGET_OS_VISION) && TARGET_OS_VISION
    ffStrbufSetStatic(&os->name, "visionOS");
#elif defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    {
        FF_STRBUF_AUTO_DESTROY machine = ffStrbufCreate();
        ffSysctlGetString("hw.machine", &machine);
        if (ffStrbufStartsWithS(&machine, "iPad")) {
            ffStrbufSetStatic(&os->name, "iPadOS");
        } else {
            ffStrbufSetStatic(&os->name, "iOS");
        }
    }
#else
    ffStrbufSetStatic(&os->name, "Apple mobile");
#endif

    ffStrbufSetStatic(&os->id, "macos");

    ffSysctlGetString("kern.osproductversion", &os->version);
    ffSysctlGetString("kern.osversion", &os->buildID);

    ffStrbufAppend(&os->versionID, &os->version);

    if (os->version.length > 0) {
        ffStrbufSetF(&os->prettyName, "%s %s (%s)", os->name.chars, os->version.chars, os->buildID.chars);
    } else {
        ffStrbufSet(&os->prettyName, &os->name);
    }
}
