#include "cpu.h"
#include "common/sysctl.h"
#include "common/strutil.h"

static const char* detectFrequency(FFCPUResult* cpu) {
    (void)cpu;
    /* pmgr / voltage-states registry probes crash in the iOS sandbox. */
    return NULL;
}

static const char* detectCoreCount(FFCPUResult* cpu) {
    uint32_t nPerfLevels = (uint32_t) ffSysctlGetInt("hw.nperflevels", 0);
    if (nPerfLevels <= 0) {
        return "sysctl(hw.nperflevels) failed";
    }

    char sysctlKey[] = "hw.perflevelN.logicalcpu";
    if (nPerfLevels > ARRAY_SIZE(cpu->coreTypes)) {
        nPerfLevels = ARRAY_SIZE(cpu->coreTypes);
    }
    for (uint32_t i = 0; i < nPerfLevels; ++i) {
        sysctlKey[strlen("hw.perflevel")] = (char) ('0' + i);
        cpu->coreTypes[i] = (FFCPUCore) {
            .freq = nPerfLevels - i,
            .count = (uint32_t) ffSysctlGetInt(sysctlKey, 0),
        };
    }
    return NULL;
}

const char* ffDetectCPUImpl(const FFCPUOptions* options, FFCPUResult* cpu) {
    if (ffSysctlGetString("machdep.cpu.brand_string", &cpu->name) != NULL) {
        return "sysctlbyname(machdep.cpu.brand_string) failed";
    }

    ffSysctlGetString("machdep.cpu.vendor", &cpu->vendor);
    cpu->packages = (uint16_t) ffSysctlGetInt("hw.packages", 1);
    if (cpu->vendor.length == 0 && ffStrbufStartsWithS(&cpu->name, "Apple ")) {
        ffStrbufAppendS(&cpu->vendor, "Apple");
    }

    cpu->coresPhysical = (uint16_t) ffSysctlGetInt("hw.physicalcpu_max", 1);
    if (cpu->coresPhysical == 1) {
        cpu->coresPhysical = (uint16_t) ffSysctlGetInt("hw.physicalcpu", 1);
    }

    cpu->coresLogical = (uint16_t) ffSysctlGetInt("hw.logicalcpu_max", 1);
    if (cpu->coresLogical == 1) {
        cpu->coresLogical = (uint16_t) ffSysctlGetInt("hw.ncpu", 1);
    }

    cpu->coresOnline = (uint16_t) ffSysctlGetInt("hw.logicalcpu", 1);
    if (cpu->coresOnline == 1) {
        cpu->coresOnline = (uint16_t) ffSysctlGetInt("hw.activecpu", 1);
    }

    ffCPUDetectByCpuid(cpu);
    detectFrequency(cpu);
    if (options->showPeCoreCount) {
        detectCoreCount(cpu);
    }

    cpu->temperature = FF_CPU_TEMP_UNSET;

    return NULL;
}
