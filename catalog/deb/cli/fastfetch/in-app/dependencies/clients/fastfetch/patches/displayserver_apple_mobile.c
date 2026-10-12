#include "displayserver.h"

void ffConnectDisplayServerImpl(FFDisplayServerResult* ds) {
    if (getenv("WAYLAND_DISPLAY")) {
        const char* desktop = getenv("XDG_CURRENT_DESKTOP");

        ffStrbufSetStatic(&ds->wmProcessName, "Wayland");
        if (desktop && *desktop) {
            ffStrbufSetStatic(&ds->wmPrettyName, desktop);
        }
        ffStrbufSetS(&ds->wmProtocolName, FF_WM_PROTOCOL_WAYLAND);
    }
}
