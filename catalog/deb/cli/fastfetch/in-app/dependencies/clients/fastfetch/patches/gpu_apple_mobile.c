#include "gpu.h"

#include <TargetConditionals.h>

/*
 * Apple mobile GPU name via Metal only (no IOKit registry walk, which is
 * blocked in the iOS sandbox). MTLCreateSystemDefaultDevice() is documented as
 * safe off the main thread and returns without any UI. Metal is unavailable on
 * watchOS, so this file self-stubs there (the Metal framework is also dropped
 * from the watchOS link by apple-mobile.nix framework tiering).
 *
 * Compiled as Objective-C (-x objective-c) so Metal can be used from a .c path.
 */

#if defined(TARGET_OS_WATCH) && TARGET_OS_WATCH

const char* ffDetectGPUImpl(const FFGPUOptions* options, FFlist* gpus) {
    (void)options;
    (void)gpus;
    return "GPU detection is not supported on watchOS";
}

#else

#import <Metal/Metal.h>

const char* ffDetectGPUImpl(const FFGPUOptions* options, FFlist* gpus) {
    (void)options;

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device)
        return "MTLCreateSystemDefaultDevice() returned nil";

    FFGPUResult* gpu = FF_LIST_ADD(FFGPUResult, *gpus);
    gpu->index = FF_GPU_INDEX_UNSET;
    gpu->type = device.hasUnifiedMemory ? FF_GPU_TYPE_INTEGRATED : FF_GPU_TYPE_DISCRETE;
    ffStrbufInitStatic(&gpu->vendor, FF_GPU_VENDOR_NAME_APPLE);
    ffStrbufInitS(&gpu->name, device.name.UTF8String);
    ffStrbufInit(&gpu->driver);
    ffStrbufInitStatic(&gpu->platformApi, "Metal");
    ffStrbufInit(&gpu->memoryType);
    gpu->temperature = FF_GPU_TEMP_UNSET;
    gpu->coreCount = FF_GPU_CORE_COUNT_UNSET;
    gpu->frequency = FF_GPU_FREQUENCY_UNSET;
    gpu->coreUsage = FF_GPU_CORE_USAGE_UNSET;
    gpu->dedicated = (FFGPUMemory) { FF_GPU_VMEM_SIZE_UNSET, FF_GPU_VMEM_SIZE_UNSET };
    gpu->shared = (FFGPUMemory) { FF_GPU_VMEM_SIZE_UNSET, FF_GPU_VMEM_SIZE_UNSET };
    gpu->deviceId = 0;

    return NULL;
}

#endif
