#include "fastfetch.h"
#include "common/processing.h"
#include "common/strutil.h"

const char* ffProcessSpawn(char* const argv[], bool useStdErr, FFProcessHandle* outHandle) {
    (void)argv;
    (void)useStdErr;
    (void)outHandle;
    return "subprocess unavailable on Apple mobile";
}

const char* ffProcessReadOutput(FFProcessHandle* handle, FFstrbuf* buffer) {
    (void)handle;
    (void)buffer;
    return "subprocess unavailable on Apple mobile";
}

void ffProcessGetInfoLinux(pid_t pid, FFstrbuf* processName, FFstrbuf* exe, const char** exeName, FFstrbuf* exePath) {
    (void)pid;
    (void)processName;
    (void)exe;
    (void)exeName;
    (void)exePath;
}

const char* ffProcessGetBasicInfoLinux(pid_t pid, FFstrbuf* name, pid_t* ppid, int32_t* tty) {
    (void)pid;
    (void)name;
    (void)ppid;
    (void)tty;
    return "process info unavailable on Apple mobile";
}
