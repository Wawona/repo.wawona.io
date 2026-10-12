#pragma once

/*
 * Runtime Vulkan dispatch for the hosts that pick their provider at runtime:
 * Android (system libvulkan.so vs bundled SwiftShader) and macOS (MoltenVK vs
 * KosmicKrisp, both bundled as dylibs with no loader alongside them). Apple
 * mobile links MoltenVK statically, so it calls the vk* symbols directly.
 */
#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif

/* The iOS *Simulator* also uses runtime dispatch: MoltenVK is still
 * force-loaded, but on the headless CI simulator its Metal pipeline bring-up
 * fatally aborts the whole app (Metal domain 102). Loading the bundled
 * SwiftShader CPU ICD by dlopen (WWN_VULKAN_LIBRARY) instead means Metal is
 * never engaged, so vkcube renders on the CPU and survives. On-device iOS keeps
 * the static MoltenVK path (TARGET_OS_SIMULATOR is 0 there). */
#if defined(__ANDROID__) \
    || (defined(__APPLE__) && (TARGET_OS_OSX || (TARGET_OS_SIMULATOR && !TARGET_OS_TV)))
#define WWN_VKCUBE_RUNTIME_DISPATCH 1
#endif

#ifdef WWN_VKCUBE_RUNTIME_DISPATCH

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void *wwn_vk_library;
static char wwn_vk_loaded_path[512];
static PFN_vkGetInstanceProcAddr wwn_vkGetInstanceProcAddr;
static PFN_vkGetDeviceProcAddr wwn_vkGetDeviceProcAddr;

#define WWN_VK_GLOBAL_FUNCTIONS(X) \
  X(vkEnumerateInstanceExtensionProperties) \
  X(vkCreateInstance)
#define WWN_VK_INSTANCE_FUNCTIONS(X) \
  X(vkEnumeratePhysicalDevices) \
  X(vkGetPhysicalDeviceProperties) \
  X(vkGetPhysicalDeviceMemoryProperties) \
  X(vkGetPhysicalDeviceQueueFamilyProperties) \
  X(vkEnumerateDeviceExtensionProperties) \
  X(vkCreateDevice) \
  X(vkDestroyInstance)
#define WWN_VK_DEVICE_FUNCTIONS(X) \
  X(vkGetDeviceQueue) \
  X(vkCreateCommandPool) \
  X(vkCreateBuffer) \
  X(vkGetBufferMemoryRequirements) \
  X(vkAllocateMemory) \
  X(vkBindBufferMemory) \
  X(vkMapMemory) \
  X(vkCreateRenderPass) \
  X(vkCreateDescriptorSetLayout) \
  X(vkCreatePipelineLayout) \
  X(vkCreateDescriptorPool) \
  X(vkAllocateDescriptorSets) \
  X(vkUpdateDescriptorSets) \
  X(vkCreateShaderModule) \
  X(vkCreateGraphicsPipelines) \
  X(vkDestroyShaderModule) \
  X(vkCreateImage) \
  X(vkGetImageMemoryRequirements) \
  X(vkBindImageMemory) \
  X(vkCreateImageView) \
  X(vkCreateFramebuffer) \
  X(vkAllocateCommandBuffers) \
  X(vkFreeCommandBuffers) \
  X(vkCreateFence) \
  X(vkWaitForFences) \
  X(vkResetFences) \
  X(vkResetCommandBuffer) \
  X(vkBeginCommandBuffer) \
  X(vkCmdBeginRenderPass) \
  X(vkCmdBindVertexBuffers) \
  X(vkCmdBindPipeline) \
  X(vkCmdBindDescriptorSets) \
  X(vkCmdSetViewport) \
  X(vkCmdSetScissor) \
  X(vkCmdDraw) \
  X(vkCmdEndRenderPass) \
  X(vkCmdCopyImageToBuffer) \
  X(vkEndCommandBuffer) \
  X(vkQueueSubmit) \
  X(vkDeviceWaitIdle) \
  X(vkDestroyFence) \
  X(vkUnmapMemory) \
  X(vkDestroyBuffer) \
  X(vkFreeMemory) \
  X(vkDestroyFramebuffer) \
  X(vkDestroyImageView) \
  X(vkDestroyImage) \
  X(vkDestroyDescriptorPool) \
  X(vkDestroyPipeline) \
  X(vkDestroyPipelineLayout) \
  X(vkDestroyDescriptorSetLayout) \
  X(vkDestroyRenderPass) \
  X(vkDestroyCommandPool) \
  X(vkDestroyDevice)

#define WWN_DECLARE_VK(name) static PFN_##name wwn_##name;
WWN_VK_GLOBAL_FUNCTIONS(WWN_DECLARE_VK)
WWN_VK_INSTANCE_FUNCTIONS(WWN_DECLARE_VK)
WWN_VK_DEVICE_FUNCTIONS(WWN_DECLARE_VK)
#undef WWN_DECLARE_VK

#if defined(__ANDROID__)
/* Bundled SwiftShader when Settings selected it, else the system loader. */
#define WWN_VKCUBE_PROVIDER_ENV "WWN_SWIFTSHADER_LIBRARY"
#define WWN_VKCUBE_PROVIDER_FALLBACK "libvulkan.so"
#else
/* Set by WWNSettings_ApplyGraphicsDriverSelection to the bundled ICD dylib for
 * the selected driver. There is no Vulkan loader in the bundle, so this is the
 * ICD itself rather than a manifest. */
#define WWN_VKCUBE_PROVIDER_ENV "WWN_VULKAN_LIBRARY"
#define WWN_VKCUBE_PROVIDER_FALLBACK "libMoltenVK.dylib"
#endif

#ifndef WWN_VKCUBE_PROVIDER_FALLBACKS_ENV
#if defined(__ANDROID__)
#define WWN_VKCUBE_PROVIDER_FALLBACKS_ENV "WWN_SWIFTSHADER_LIBRARY_FALLBACKS"
#else
#define WWN_VKCUBE_PROVIDER_FALLBACKS_ENV "WWN_VULKAN_LIBRARY_FALLBACKS"
#endif
#endif

/*
 * Ordered Vulkan provider (ICD) list. There is no Vulkan loader in the app
 * bundle, so vkcube emulates the loader's multi-ICD behaviour itself: try the
 * Settings-selected ICD first (WWN_VULKAN_LIBRARY), then WWNSettings'
 * colon-separated fallbacks (WWN_VULKAN_LIBRARY_FALLBACKS = hardware MoltenVK,
 * then the SwiftShader CPU device), then the compile-time default. This is what
 * lets vkcube run on a headless CI VM / Simulator whose selected driver (e.g.
 * KosmicKrisp) loads yet enumerates no physical device: init_vulkan advances to
 * the next provider until one yields a device.
 */
enum { WWN_VKCUBE_MAX_PROVIDERS = 8 };

static int wwn_vkcube_provider_at(int index, const char **out) {
  static char slots[WWN_VKCUBE_MAX_PROVIDERS][512];
  static int count = -1;
  if (count < 0) {
    count = 0;
    const char *sel = getenv(WWN_VKCUBE_PROVIDER_ENV);
    if (sel && sel[0]) {
      snprintf(slots[count], sizeof(slots[0]), "%s", sel);
      count++;
    }
    const char *fb = getenv(WWN_VKCUBE_PROVIDER_FALLBACKS_ENV);
    if (fb && fb[0]) {
      static char scratch[2048];
      snprintf(scratch, sizeof(scratch), "%s", fb);
      char *save = NULL;
      for (char *tok = strtok_r(scratch, ":", &save);
           tok && count < WWN_VKCUBE_MAX_PROVIDERS;
           tok = strtok_r(NULL, ":", &save)) {
        if (tok[0]) {
          snprintf(slots[count], sizeof(slots[0]), "%s", tok);
          count++;
        }
      }
    }
    if (count < WWN_VKCUBE_MAX_PROVIDERS) {
      snprintf(slots[count], sizeof(slots[0]), "%s", WWN_VKCUBE_PROVIDER_FALLBACK);
      count++;
    }
  }
  if (index < 0 || index >= count)
    return 0;
  *out = slots[index];
  return 1;
}

static int wwn_vkcube_provider_count(void) {
  const char *p;
  int i = 0;
  while (wwn_vkcube_provider_at(i, &p))
    i++;
  return i;
}

/* Load the global Vulkan dispatch from a specific provider path. Returns 0 on
 * success. Caller iterates providers (init_vulkan) and calls
 * wwn_vkcube_close_dispatch between attempts. */
static int wwn_vkcube_load_global_dispatch_path(const char *path) {
  wwn_vk_library = dlopen(path, RTLD_NOW | RTLD_LOCAL);
  if (!wwn_vk_library) {
    fprintf(stderr, "vkcube: cannot load Vulkan provider %s: %s\n", path,
            dlerror());
    return -1;
  }
  wwn_vkGetInstanceProcAddr =
      (PFN_vkGetInstanceProcAddr)dlsym(wwn_vk_library, "vkGetInstanceProcAddr");
  if (!wwn_vkGetInstanceProcAddr) {
    /* Mesa-derived ICDs (KosmicKrisp) only export the ICD-negotiated name. */
    wwn_vkGetInstanceProcAddr = (PFN_vkGetInstanceProcAddr)dlsym(
        wwn_vk_library, "vk_icdGetInstanceProcAddr");
  }
  if (!wwn_vkGetInstanceProcAddr) {
    fprintf(stderr, "vkcube: %s has no vkGetInstanceProcAddr\n", path);
    return -1;
  }
    snprintf(wwn_vk_loaded_path, sizeof(wwn_vk_loaded_path), "%s", path);
  fprintf(stderr, "vkcube: Vulkan provider %s\n", path);
#define WWN_LOAD_GLOBAL(name) \
  wwn_##name = (PFN_##name)wwn_vkGetInstanceProcAddr(VK_NULL_HANDLE, #name); \
  if (!wwn_##name) { \
    fprintf(stderr, "vkcube: missing global Vulkan entrypoint %s\n", #name); \
    return -1; \
  }
  WWN_VK_GLOBAL_FUNCTIONS(WWN_LOAD_GLOBAL)
#undef WWN_LOAD_GLOBAL
  return 0;
}

/* Backwards-compatible single-provider entry (first provider only). */
static int wwn_vkcube_load_global_dispatch(void) {
  const char *path = NULL;
  if (!wwn_vkcube_provider_at(0, &path))
    path = WWN_VKCUBE_PROVIDER_FALLBACK;
  return wwn_vkcube_load_global_dispatch_path(path);
}

static int wwn_vkcube_load_instance_dispatch(VkInstance instance) {
#define WWN_LOAD_INSTANCE(name) \
  wwn_##name = (PFN_##name)wwn_vkGetInstanceProcAddr(instance, #name); \
  if (!wwn_##name) { \
    fprintf(stderr, "vkcube: missing instance Vulkan entrypoint %s\n", #name); \
    return -1; \
  }
  WWN_VK_INSTANCE_FUNCTIONS(WWN_LOAD_INSTANCE)
#undef WWN_LOAD_INSTANCE
  wwn_vkGetDeviceProcAddr = (PFN_vkGetDeviceProcAddr)
      wwn_vkGetInstanceProcAddr(instance, "vkGetDeviceProcAddr");
  return wwn_vkGetDeviceProcAddr ? 0 : -1;
}

static int wwn_vkcube_load_device_dispatch(VkDevice device) {
#define WWN_LOAD_DEVICE(name) \
  wwn_##name = (PFN_##name)wwn_vkGetDeviceProcAddr(device, #name); \
  if (!wwn_##name) { \
    fprintf(stderr, "vkcube: missing device Vulkan entrypoint %s\n", #name); \
    return -1; \
  }
  WWN_VK_DEVICE_FUNCTIONS(WWN_LOAD_DEVICE)
#undef WWN_LOAD_DEVICE
  return 0;
}

static void wwn_vkcube_close_dispatch(void) {
  if (wwn_vk_library)
    dlclose(wwn_vk_library);
  wwn_vk_library = NULL;
  wwn_vk_loaded_path[0] = 0;
}

static const char *wwn_vkcube_loaded_provider_path(void) {
  return wwn_vk_loaded_path[0] ? wwn_vk_loaded_path : NULL;
}

#define vkEnumerateInstanceExtensionProperties wwn_vkEnumerateInstanceExtensionProperties
#define vkCreateInstance wwn_vkCreateInstance
#define vkEnumeratePhysicalDevices wwn_vkEnumeratePhysicalDevices
#define vkGetPhysicalDeviceProperties wwn_vkGetPhysicalDeviceProperties
#define vkGetPhysicalDeviceMemoryProperties wwn_vkGetPhysicalDeviceMemoryProperties
#define vkGetPhysicalDeviceQueueFamilyProperties wwn_vkGetPhysicalDeviceQueueFamilyProperties
#define vkEnumerateDeviceExtensionProperties wwn_vkEnumerateDeviceExtensionProperties
#define vkCreateDevice wwn_vkCreateDevice
#define vkDestroyInstance wwn_vkDestroyInstance
#define vkGetDeviceQueue wwn_vkGetDeviceQueue
#define vkCreateCommandPool wwn_vkCreateCommandPool
#define vkCreateBuffer wwn_vkCreateBuffer
#define vkGetBufferMemoryRequirements wwn_vkGetBufferMemoryRequirements
#define vkAllocateMemory wwn_vkAllocateMemory
#define vkBindBufferMemory wwn_vkBindBufferMemory
#define vkMapMemory wwn_vkMapMemory
#define vkCreateRenderPass wwn_vkCreateRenderPass
#define vkCreateDescriptorSetLayout wwn_vkCreateDescriptorSetLayout
#define vkCreatePipelineLayout wwn_vkCreatePipelineLayout
#define vkCreateDescriptorPool wwn_vkCreateDescriptorPool
#define vkAllocateDescriptorSets wwn_vkAllocateDescriptorSets
#define vkUpdateDescriptorSets wwn_vkUpdateDescriptorSets
#define vkCreateShaderModule wwn_vkCreateShaderModule
#define vkCreateGraphicsPipelines wwn_vkCreateGraphicsPipelines
#define vkDestroyShaderModule wwn_vkDestroyShaderModule
#define vkCreateImage wwn_vkCreateImage
#define vkGetImageMemoryRequirements wwn_vkGetImageMemoryRequirements
#define vkBindImageMemory wwn_vkBindImageMemory
#define vkCreateImageView wwn_vkCreateImageView
#define vkCreateFramebuffer wwn_vkCreateFramebuffer
#define vkAllocateCommandBuffers wwn_vkAllocateCommandBuffers
#define vkFreeCommandBuffers wwn_vkFreeCommandBuffers
#define vkCreateFence wwn_vkCreateFence
#define vkWaitForFences wwn_vkWaitForFences
#define vkResetFences wwn_vkResetFences
#define vkResetCommandBuffer wwn_vkResetCommandBuffer
#define vkBeginCommandBuffer wwn_vkBeginCommandBuffer
#define vkCmdBeginRenderPass wwn_vkCmdBeginRenderPass
#define vkCmdBindVertexBuffers wwn_vkCmdBindVertexBuffers
#define vkCmdBindPipeline wwn_vkCmdBindPipeline
#define vkCmdBindDescriptorSets wwn_vkCmdBindDescriptorSets
#define vkCmdSetViewport wwn_vkCmdSetViewport
#define vkCmdSetScissor wwn_vkCmdSetScissor
#define vkCmdDraw wwn_vkCmdDraw
#define vkCmdEndRenderPass wwn_vkCmdEndRenderPass
#define vkCmdCopyImageToBuffer wwn_vkCmdCopyImageToBuffer
#define vkEndCommandBuffer wwn_vkEndCommandBuffer
#define vkQueueSubmit wwn_vkQueueSubmit
#define vkDeviceWaitIdle wwn_vkDeviceWaitIdle
#define vkDestroyFence wwn_vkDestroyFence
#define vkUnmapMemory wwn_vkUnmapMemory
#define vkDestroyBuffer wwn_vkDestroyBuffer
#define vkFreeMemory wwn_vkFreeMemory
#define vkDestroyFramebuffer wwn_vkDestroyFramebuffer
#define vkDestroyImageView wwn_vkDestroyImageView
#define vkDestroyImage wwn_vkDestroyImage
#define vkDestroyDescriptorPool wwn_vkDestroyDescriptorPool
#define vkDestroyPipeline wwn_vkDestroyPipeline
#define vkDestroyPipelineLayout wwn_vkDestroyPipelineLayout
#define vkDestroyDescriptorSetLayout wwn_vkDestroyDescriptorSetLayout
#define vkDestroyRenderPass wwn_vkDestroyRenderPass
#define vkDestroyCommandPool wwn_vkDestroyCommandPool
#define vkDestroyDevice wwn_vkDestroyDevice

#else /* statically linked provider (Apple mobile) */

/* Apple mobile links one ICD (MoltenVK) statically: a single implicit provider,
 * no dlopen, no fallback list. The provider-loop shape in init_vulkan still
 * compiles against these no-ops. */
static int wwn_vkcube_provider_count(void) { return 1; }
static int wwn_vkcube_load_global_dispatch(void) { return 0; }
static int wwn_vkcube_load_instance_dispatch(VkInstance instance) {
  (void)instance;
  return 0;
}
static int wwn_vkcube_load_device_dispatch(VkDevice device) {
  (void)device;
  return 0;
}
static void wwn_vkcube_close_dispatch(void) {}

static const char *wwn_vkcube_loaded_provider_path(void) { return "MoltenVK"; }

#endif
