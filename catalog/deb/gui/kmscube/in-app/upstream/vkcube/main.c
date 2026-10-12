/*
 * Wayland + iland IOSurface dmabuf adaptation of krh/vkcube.
 *
 * Upstream: https://github.com/krh/vkcube
 * Revision: ffd566971fac916fc90d33a442369d5717ceb2a9
 *
 * Copyright (c) 2012 Arvin Schnell <arvin.schnell@gmail.com>
 * Copyright (c) 2012 Rob Clark <rob@ti.com>
 * Copyright (c) 2015 Intel Corporation
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice (including the next
 * paragraph) shall be included in all copies or substantial portions of the
 * Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 * IN THE SOFTWARE.
 *
 * Wayland adaptation: renders into ordinary Vulkan images, copies to
 * host-coherent staging, and posts BGRA pixels through iland's Wayland
 * winsys (IOSurface + zwp_linux_dmabuf_v1 modifier). Same ICD-neutral path
 * as the KMS variant (see vkcube_kms.c), but as a real compositor client
 * (xdg-shell) rather than an iland virtual DRM host.
 */

#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <wayland-client.h>
#include <vulkan/vulkan.h>

#include "xdg-shell-client-protocol.h"
#include "iland_wl_winsys.h"

#include "vulkan_dispatch.h"
#include "wwn_cube_hud.h"
#include "wwn_cube_hud.c"

#ifndef VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR
#define VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR 0x00000001
#endif
#ifndef VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME
#define VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME "VK_KHR_portability_enumeration"
#endif
#ifndef VK_KHR_PORTABILITY_SUBSET_EXTENSION_NAME
#define VK_KHR_PORTABILITY_SUBSET_EXTENSION_NAME "VK_KHR_portability_subset"
#endif

#define BUFFER_COUNT 2
#define DEFAULT_WIDTH 800
#define DEFAULT_HEIGHT 800
#define DEFAULT_FRAMES 0

struct matrix {
  float m[4][4];
};

struct ubo {
  struct matrix modelview;
  struct matrix modelviewprojection;
  float normal[12];
};

struct buffer {
  VkImage image;
  VkDeviceMemory image_memory;
  VkImageView view;
  VkFramebuffer framebuffer;
  VkBuffer staging;
  VkDeviceMemory staging_memory;
  void *staging_map;
  VkCommandBuffer command_buffer;
  VkFence fence;
};

struct app {
  struct wl_display *display;
  struct wl_registry *registry;
  struct wl_compositor *compositor;
  struct xdg_wm_base *wm_base;
  struct wl_surface *surface;
  struct xdg_surface *xdg_surface;
  struct xdg_toplevel *toplevel;
  IlandWlWinsys *winsys;
  IlandWlSwapchain *swapchain;
  bool configured;
  bool running;
  bool size_dirty;
  uint32_t width;
  uint32_t height;
  uint32_t pending_width;
  uint32_t pending_height;

  VkInstance instance;
  VkPhysicalDevice physical_device;
  VkPhysicalDeviceMemoryProperties memory_properties;
  VkDevice device;
  uint32_t queue_family;
  VkQueue queue;
  VkCommandPool command_pool;
  VkRenderPass render_pass;
  VkDescriptorSetLayout descriptor_set_layout;
  VkPipelineLayout pipeline_layout;
  VkPipeline pipeline;
  VkBuffer vertex_buffer;
  VkDeviceMemory vertex_memory;
  void *vertex_map;
  uint32_t vertex_offset;
  uint32_t color_offset;
  uint32_t normal_offset;
  VkDescriptorPool descriptor_pool;
  VkDescriptorSet descriptor_set;
  struct buffer buffers[BUFFER_COUNT];
};

static struct wwn_cube_hud g_hud;

static const uint32_t vertex_spirv[] = {
#include "vkcube.vert.spv.h"
};

static const uint32_t fragment_spirv[] = {
#include "vkcube.frag.spv.h"
};

static const float vertices[] = {
    -1, -1, +1, +1, -1, +1, -1, +1, +1, +1, +1, +1,
    +1, -1, -1, -1, -1, -1, +1, +1, -1, -1, +1, -1,
    +1, -1, +1, +1, -1, -1, +1, +1, +1, +1, +1, -1,
    -1, -1, -1, -1, -1, +1, -1, +1, -1, -1, +1, +1,
    -1, +1, +1, +1, +1, +1, -1, +1, -1, +1, +1, -1,
    -1, -1, -1, +1, -1, -1, -1, -1, +1, +1, -1, +1,
};

static const float colors[] = {
    0, 0, 1, 1, 0, 1, 0, 1, 1, 1, 1, 1,
    1, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0,
    1, 0, 1, 1, 0, 0, 1, 1, 1, 1, 1, 0,
    0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 1, 1,
    0, 1, 1, 1, 1, 1, 0, 1, 0, 1, 1, 0,
    0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 0, 1,
};

static const float normals[] = {
    0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1,
    0, 0, -1, 0, 0, -1, 0, 0, -1, 0, 0, -1,
    1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0,
    -1, 0, 0, -1, 0, 0, -1, 0, 0, -1, 0, 0,
    0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0,
    0, -1, 0, 0, -1, 0, 0, -1, 0, 0, -1, 0,
};

static int vk_error(VkResult result, const char *operation) {
  if (result == VK_SUCCESS)
    return 0;
  fprintf(stderr, "vkcube: %s failed (%d)\n", operation, result);
  return -1;
}

#define VK_CHECK(call)                                                         \
  do {                                                                         \
    if (vk_error((call), #call) != 0)                                          \
      return -1;                                                               \
  } while (0)

static void matrix_identity(struct matrix *result) {
  memset(result, 0, sizeof(*result));
  result->m[0][0] = result->m[1][1] = 1.0f;
  result->m[2][2] = result->m[3][3] = 1.0f;
}

static void matrix_multiply(struct matrix *result, const struct matrix *a,
                            const struct matrix *b) {
  struct matrix tmp;
  for (int i = 0; i < 4; ++i)
    for (int j = 0; j < 4; ++j) {
      tmp.m[i][j] = 0.0f;
      for (int k = 0; k < 4; ++k)
        tmp.m[i][j] += a->m[i][k] * b->m[k][j];
    }
  *result = tmp;
}

static void matrix_translate(struct matrix *result, float x, float y, float z) {
  result->m[3][0] += result->m[0][0] * x + result->m[1][0] * y + result->m[2][0] * z;
  result->m[3][1] += result->m[0][1] * x + result->m[1][1] * y + result->m[2][1] * z;
  result->m[3][2] += result->m[0][2] * x + result->m[1][2] * y + result->m[2][2] * z;
  result->m[3][3] += result->m[0][3] * x + result->m[1][3] * y + result->m[2][3] * z;
}

static void matrix_rotate(struct matrix *result, float degrees, float x, float y,
                          float z) {
  const float radians = degrees * 0.01745329251994329577f;
  const float sine = sinf(radians);
  const float cosine = cosf(radians);
  const float length = sqrtf(x * x + y * y + z * z);
  if (length == 0.0f)
    return;
  x /= length;
  y /= length;
  z /= length;
  const float c = 1.0f - cosine;
  struct matrix rotation = {{
      {x * x * c + cosine, x * y * c - z * sine, x * z * c + y * sine, 0},
      {y * x * c + z * sine, y * y * c + cosine, y * z * c - x * sine, 0},
      {z * x * c - y * sine, z * y * c + x * sine, z * z * c + cosine, 0},
      {0, 0, 0, 1},
  }};
  matrix_multiply(result, &rotation, result);
}

static void matrix_frustum(struct matrix *result, float left, float right,
                           float bottom, float top, float near_z, float far_z) {
  struct matrix frustum = {{{0}}};
  const float dx = right - left, dy = top - bottom, dz = far_z - near_z;
  frustum.m[0][0] = 2.0f * near_z / dx;
  frustum.m[1][1] = 2.0f * near_z / dy;
  frustum.m[2][0] = (right + left) / dx;
  frustum.m[2][1] = (top + bottom) / dy;
  frustum.m[2][2] = -far_z / dz;
  frustum.m[2][3] = -1.0f;
  frustum.m[3][2] = -(near_z * far_z) / dz;
  matrix_multiply(result, &frustum, result);
}

static bool has_instance_extension(const char *name) {
  uint32_t count = 0;
  if (vkEnumerateInstanceExtensionProperties(NULL, &count, NULL) != VK_SUCCESS)
    return false;
  VkExtensionProperties *properties = calloc(count, sizeof(*properties));
  if (!properties)
    return false;
  bool found = false;
  if (vkEnumerateInstanceExtensionProperties(NULL, &count, properties) == VK_SUCCESS)
    for (uint32_t i = 0; i < count; ++i)
      if (strcmp(properties[i].extensionName, name) == 0) {
        found = true;
        break;
      }
  free(properties);
  return found;
}

static bool has_device_extension(VkPhysicalDevice device, const char *name) {
  uint32_t count = 0;
  if (vkEnumerateDeviceExtensionProperties(device, NULL, &count, NULL) != VK_SUCCESS)
    return false;
  VkExtensionProperties *properties = calloc(count, sizeof(*properties));
  if (!properties)
    return false;
  bool found = false;
  if (vkEnumerateDeviceExtensionProperties(device, NULL, &count, properties) == VK_SUCCESS)
    for (uint32_t i = 0; i < count; ++i)
      if (strcmp(properties[i].extensionName, name) == 0) {
        found = true;
        break;
      }
  free(properties);
  return found;
}

static int find_memory_type(struct app *app, uint32_t allowed,
                            VkMemoryPropertyFlags required) {
  for (uint32_t i = 0; i < app->memory_properties.memoryTypeCount; ++i)
    if ((allowed & (1u << i)) &&
        (app->memory_properties.memoryTypes[i].propertyFlags & required) == required)
      return (int)i;
  return -1;
}

static void wm_base_ping(void *data, struct xdg_wm_base *wm_base, uint32_t serial) {
  (void)data;
  xdg_wm_base_pong(wm_base, serial);
}

static const struct xdg_wm_base_listener wm_base_listener = { wm_base_ping };

static void xdg_surface_configure(void *data, struct xdg_surface *xdg_surface,
                                  uint32_t serial) {
  struct app *app = data;
  xdg_surface_ack_configure(xdg_surface, serial);
  app->configured = true;
}

static const struct xdg_surface_listener xdg_surface_listener = {
    xdg_surface_configure,
};

static void toplevel_configure(void *data, struct xdg_toplevel *toplevel,
                               int32_t width, int32_t height, struct wl_array *states) {
  struct app *app = data;
  (void)toplevel;
  (void)states;
  /* 0x0 means "pick your own size" — keep the pending suggestion. */
  if (width <= 0 || height <= 0)
    return;
  if ((uint32_t)width == app->pending_width &&
      (uint32_t)height == app->pending_height)
    return;
  app->pending_width = (uint32_t)width;
  app->pending_height = (uint32_t)height;
  /* After Vulkan targets exist, rebuild on the render thread (main loop). */
  if (app->device != VK_NULL_HANDLE)
    app->size_dirty = true;
}

static void toplevel_close(void *data, struct xdg_toplevel *toplevel) {
  struct app *app = data;
  (void)toplevel;
  app->running = false;
}

static const struct xdg_toplevel_listener toplevel_listener = {
    toplevel_configure,
    toplevel_close,
};

static void registry_global(void *data, struct wl_registry *registry, uint32_t name,
                            const char *interface, uint32_t version) {
  struct app *app = data;
  (void)version;
  if (strcmp(interface, "wl_compositor") == 0) {
    app->compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 1);
  } else if (strcmp(interface, "xdg_wm_base") == 0) {
    app->wm_base = wl_registry_bind(registry, name, &xdg_wm_base_interface, 1);
    xdg_wm_base_add_listener(app->wm_base, &wm_base_listener, NULL);
  }
}

static void registry_global_remove(void *data, struct wl_registry *registry, uint32_t name) {
  (void)data;
  (void)registry;
  (void)name;
}

static const struct wl_registry_listener registry_listener = {
    registry_global,
    registry_global_remove,
};

static int init_wayland(struct app *app) {
  app->display = wl_display_connect(NULL);
  if (!app->display) {
    fprintf(stderr, "vkcube: wl_display_connect failed (WAYLAND_DISPLAY set?)\n");
    return -1;
  }
  app->registry = wl_display_get_registry(app->display);
  wl_registry_add_listener(app->registry, &registry_listener, app);
  wl_display_roundtrip(app->display);
  if (!app->compositor || !app->wm_base) {
    fprintf(stderr, "vkcube: compositor lacks wl_compositor/xdg_wm_base\n");
    return -1;
  }
  app->surface = wl_compositor_create_surface(app->compositor);
  app->xdg_surface = xdg_wm_base_get_xdg_surface(app->wm_base, app->surface);
  xdg_surface_add_listener(app->xdg_surface, &xdg_surface_listener, app);
  app->toplevel = xdg_surface_get_toplevel(app->xdg_surface);
  xdg_toplevel_add_listener(app->toplevel, &toplevel_listener, app);
  xdg_toplevel_set_title(app->toplevel, "Vulkan Cube");
  xdg_toplevel_set_app_id(app->toplevel, "org.wawona.vkcube");
  wl_surface_commit(app->surface);
  while (!app->configured) {
    if (wl_display_dispatch(app->display) < 0) {
      fprintf(stderr, "vkcube: disconnected before first configure\n");
      return -1;
    }
  }
  if (app->pending_width == 0)
    app->pending_width = DEFAULT_WIDTH;
  if (app->pending_height == 0)
    app->pending_height = DEFAULT_HEIGHT;
  app->width = app->pending_width;
  app->height = app->pending_height;

  app->winsys = iland_wl_winsys_create(app->display);
  if (!app->winsys) {
    fprintf(stderr, "vkcube: compositor lacks zwp_linux_dmabuf_v1\n");
    return -1;
  }
  app->swapchain = iland_wl_swapchain_create_for_surface(
      app->winsys, app->surface, app->width, app->height,
      ILAND_WL_SWAPCHAIN_TOP_DOWN);
  if (!app->swapchain) {
    fprintf(stderr, "vkcube: iland_wl_swapchain_create_for_surface failed\n");
    return -1;
  }
  app->running = true;
  return 0;
}

/* Bring up a Vulkan instance and pick a physical device using whichever
 * provider's global dispatch is currently loaded. Returns 0 (and sets
 * app->instance + app->physical_device) when this provider yields at least one
 * device; returns -1 as a *soft* failure so init_vulkan can try the next
 * provider. Leaves app->instance = VK_NULL_HANDLE on a create failure so the
 * caller only ever destroys a real handle. */
static int wwn_vkcube_bringup_instance_and_gpu(struct app *app) {
  const bool portability =
      has_instance_extension(VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
  const char *instance_extensions[] = {
      VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME,
  };
  const VkApplicationInfo app_info = {
      .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
      .pApplicationName = "vkcube",
      .applicationVersion = VK_MAKE_VERSION(0, 1, 0),
      .pEngineName = "wwn-iland-wayland",
      .engineVersion = VK_MAKE_VERSION(1, 0, 0),
      .apiVersion = VK_API_VERSION_1_0,
  };
  const VkInstanceCreateInfo instance_info = {
      .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
      .flags = portability ? VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR : 0,
      .pApplicationInfo = &app_info,
      .enabledExtensionCount = portability ? 1u : 0u,
      .ppEnabledExtensionNames = portability ? instance_extensions : NULL,
  };
  if (vkCreateInstance(&instance_info, NULL, &app->instance) != VK_SUCCESS) {
    app->instance = VK_NULL_HANDLE;
    return -1;
  }
  if (wwn_vkcube_load_instance_dispatch(app->instance) != 0)
    return -1;

  uint32_t physical_count = 0;
  if (vkEnumeratePhysicalDevices(app->instance, &physical_count, NULL) !=
          VK_SUCCESS ||
      physical_count == 0)
    return -1;
  VkPhysicalDevice *physical_devices =
      calloc(physical_count, sizeof(*physical_devices));
  if (!physical_devices)
    return -1;
  if (vkEnumeratePhysicalDevices(app->instance, &physical_count,
                                 physical_devices) != VK_SUCCESS) {
    free(physical_devices);
    return -1;
  }
  app->physical_device = physical_devices[0];
  free(physical_devices);
  vkGetPhysicalDeviceMemoryProperties(app->physical_device,
                                      &app->memory_properties);
  return 0;
}

static int init_vulkan(struct app *app) {
  // Try each Vulkan provider in order (selected ICD -> MoltenVK -> SwiftShader
  // on macOS; single static MoltenVK on Apple mobile) until one enumerates a
  // physical device. A headless CI VM / Simulator can load the selected driver
  // yet find no device — advancing to the next provider is what keeps vkcube
  // running there without a real GPU.
  int providers = wwn_vkcube_provider_count();
  int ok = 0;
  for (int i = 0; i < providers; i++) {
    if (i > 0)
      wwn_vkcube_close_dispatch();
#ifdef WWN_VKCUBE_RUNTIME_DISPATCH
    const char *ppath = NULL;
    if (!wwn_vkcube_provider_at(i, &ppath))
      break;
    if (wwn_vkcube_load_global_dispatch_path(ppath) != 0)
      continue;
#else
    if (wwn_vkcube_load_global_dispatch() != 0)
      return -1;
#endif
    if (wwn_vkcube_bringup_instance_and_gpu(app) == 0) {
      ok = 1;
      break;
    }
    if (app->instance != VK_NULL_HANDLE) {
      vkDestroyInstance(app->instance, NULL);
      app->instance = VK_NULL_HANDLE;
    }
  }
  if (!ok)
    return fprintf(stderr,
                   "vkcube: no Vulkan physical device from any provider\n"),
           -1;

  uint32_t family_count = 0;
  vkGetPhysicalDeviceQueueFamilyProperties(app->physical_device, &family_count, NULL);
  VkQueueFamilyProperties *families = calloc(family_count, sizeof(*families));
  if (!families)
    return -1;
  vkGetPhysicalDeviceQueueFamilyProperties(app->physical_device, &family_count, families);
  app->queue_family = UINT32_MAX;
  for (uint32_t i = 0; i < family_count; ++i)
    if (families[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) {
      app->queue_family = i;
      break;
    }
  free(families);
  if (app->queue_family == UINT32_MAX)
    return fprintf(stderr, "vkcube: no Vulkan graphics queue\n"), -1;

  float priority = 1.0f;
  const VkDeviceQueueCreateInfo queue_info = {
      .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
      .queueFamilyIndex = app->queue_family,
      .queueCount = 1,
      .pQueuePriorities = &priority,
  };
  const bool subset =
      has_device_extension(app->physical_device, VK_KHR_PORTABILITY_SUBSET_EXTENSION_NAME);
  const char *device_extensions[] = {VK_KHR_PORTABILITY_SUBSET_EXTENSION_NAME};
  const VkDeviceCreateInfo device_info = {
      .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
      .queueCreateInfoCount = 1,
      .pQueueCreateInfos = &queue_info,
      .enabledExtensionCount = subset ? 1u : 0u,
      .ppEnabledExtensionNames = subset ? device_extensions : NULL,
  };
  VK_CHECK(vkCreateDevice(app->physical_device, &device_info, NULL, &app->device));
  if (wwn_vkcube_load_device_dispatch(app->device) != 0)
    return -1;
  vkGetDeviceQueue(app->device, app->queue_family, 0, &app->queue);

  const VkCommandPoolCreateInfo pool_info = {
      .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
      .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
      .queueFamilyIndex = app->queue_family,
  };
  VK_CHECK(vkCreateCommandPool(app->device, &pool_info, NULL, &app->command_pool));

  VkPhysicalDeviceProperties props;
  memset(&props, 0, sizeof(props));
  vkGetPhysicalDeviceProperties(app->physical_device, &props);
  wwn_cube_hud_init(&g_hud);
  wwn_cube_hud_set_client(&g_hud, "vkcube");
  wwn_cube_hud_set_vk(&g_hud, wwn_vkcube_loaded_provider_path(),
                      props.deviceName);
  return 0;
}

static int create_buffer_memory(struct app *app, VkDeviceSize size,
                                VkBufferUsageFlags usage,
                                VkMemoryPropertyFlags properties, VkBuffer *buffer,
                                VkDeviceMemory *memory, void **map) {
  const VkBufferCreateInfo buffer_info = {
      .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
      .size = size,
      .usage = usage,
      .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
  };
  VK_CHECK(vkCreateBuffer(app->device, &buffer_info, NULL, buffer));
  VkMemoryRequirements requirements;
  vkGetBufferMemoryRequirements(app->device, *buffer, &requirements);
  int memory_type = find_memory_type(app, requirements.memoryTypeBits, properties);
  if (memory_type < 0)
    return fprintf(stderr, "vkcube: no compatible buffer memory\n"), -1;
  const VkMemoryAllocateInfo allocation_info = {
      .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
      .allocationSize = requirements.size,
      .memoryTypeIndex = (uint32_t)memory_type,
  };
  VK_CHECK(vkAllocateMemory(app->device, &allocation_info, NULL, memory));
  VK_CHECK(vkBindBufferMemory(app->device, *buffer, *memory, 0));
  if (map)
    VK_CHECK(vkMapMemory(app->device, *memory, 0, size, 0, map));
  return 0;
}

static int init_render_pass(struct app *app) {
  const VkAttachmentDescription attachment = {
      .format = VK_FORMAT_B8G8R8A8_UNORM,
      .samples = VK_SAMPLE_COUNT_1_BIT,
      .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
      .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
      .stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE,
      .stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
      .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
      .finalLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
  };
  const VkAttachmentReference color_reference = {
      .attachment = 0,
      .layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
  };
  const VkSubpassDescription subpass = {
      .pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS,
      .colorAttachmentCount = 1,
      .pColorAttachments = &color_reference,
  };
  const VkSubpassDependency dependency = {
      .srcSubpass = 0,
      .dstSubpass = VK_SUBPASS_EXTERNAL,
      .srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
      .dstStageMask = VK_PIPELINE_STAGE_TRANSFER_BIT,
      .srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
      .dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT,
  };
  const VkRenderPassCreateInfo info = {
      .sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
      .attachmentCount = 1,
      .pAttachments = &attachment,
      .subpassCount = 1,
      .pSubpasses = &subpass,
      .dependencyCount = 1,
      .pDependencies = &dependency,
  };
  VK_CHECK(vkCreateRenderPass(app->device, &info, NULL, &app->render_pass));
  return 0;
}

static int init_geometry(struct app *app) {
  const VkDescriptorSetLayoutBinding binding = {
      .binding = 0,
      .descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
      .descriptorCount = 1,
      .stageFlags = VK_SHADER_STAGE_VERTEX_BIT,
  };
  const VkDescriptorSetLayoutCreateInfo set_layout_info = {
      .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
      .bindingCount = 1,
      .pBindings = &binding,
  };
  VK_CHECK(vkCreateDescriptorSetLayout(app->device, &set_layout_info, NULL,
                                      &app->descriptor_set_layout));
  const VkPipelineLayoutCreateInfo pipeline_layout_info = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
      .setLayoutCount = 1,
      .pSetLayouts = &app->descriptor_set_layout,
  };
  VK_CHECK(vkCreatePipelineLayout(app->device, &pipeline_layout_info, NULL,
                                  &app->pipeline_layout));

  app->vertex_offset = sizeof(struct ubo);
  app->color_offset = app->vertex_offset + sizeof(vertices);
  app->normal_offset = app->color_offset + sizeof(colors);
  VkDeviceSize size = app->normal_offset + sizeof(normals);
  if (create_buffer_memory(app, size,
                           VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT |
                               VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
                           VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
                               VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                           &app->vertex_buffer, &app->vertex_memory,
                           &app->vertex_map) != 0)
    return -1;
  memcpy((uint8_t *)app->vertex_map + app->vertex_offset, vertices, sizeof(vertices));
  memcpy((uint8_t *)app->vertex_map + app->color_offset, colors, sizeof(colors));
  memcpy((uint8_t *)app->vertex_map + app->normal_offset, normals, sizeof(normals));

  const VkDescriptorPoolSize pool_size = {
      .type = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
      .descriptorCount = 1,
  };
  const VkDescriptorPoolCreateInfo pool_info = {
      .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
      .maxSets = 1,
      .poolSizeCount = 1,
      .pPoolSizes = &pool_size,
  };
  VK_CHECK(vkCreateDescriptorPool(app->device, &pool_info, NULL,
                                  &app->descriptor_pool));
  const VkDescriptorSetAllocateInfo allocation_info = {
      .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
      .descriptorPool = app->descriptor_pool,
      .descriptorSetCount = 1,
      .pSetLayouts = &app->descriptor_set_layout,
  };
  VK_CHECK(vkAllocateDescriptorSets(app->device, &allocation_info,
                                    &app->descriptor_set));
  const VkDescriptorBufferInfo descriptor_buffer = {
      .buffer = app->vertex_buffer,
      .offset = 0,
      .range = sizeof(struct ubo),
  };
  const VkWriteDescriptorSet write = {
      .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
      .dstSet = app->descriptor_set,
      .dstBinding = 0,
      .descriptorCount = 1,
      .descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
      .pBufferInfo = &descriptor_buffer,
  };
  vkUpdateDescriptorSets(app->device, 1, &write, 0, NULL);
  return 0;
}

static int init_pipeline(struct app *app) {
  VkShaderModule vertex_module, fragment_module;
  const VkShaderModuleCreateInfo vertex_info = {
      .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
      .codeSize = sizeof(vertex_spirv),
      .pCode = vertex_spirv,
  };
  const VkShaderModuleCreateInfo fragment_info = {
      .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
      .codeSize = sizeof(fragment_spirv),
      .pCode = fragment_spirv,
  };
  VK_CHECK(vkCreateShaderModule(app->device, &vertex_info, NULL, &vertex_module));
  VK_CHECK(vkCreateShaderModule(app->device, &fragment_info, NULL, &fragment_module));
  const VkPipelineShaderStageCreateInfo stages[] = {
      {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
       .stage = VK_SHADER_STAGE_VERTEX_BIT,
       .module = vertex_module,
       .pName = "main"},
      {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
       .stage = VK_SHADER_STAGE_FRAGMENT_BIT,
       .module = fragment_module,
       .pName = "main"},
  };
  const VkVertexInputBindingDescription bindings[] = {
      {.binding = 0, .stride = 3 * sizeof(float), .inputRate = VK_VERTEX_INPUT_RATE_VERTEX},
      {.binding = 1, .stride = 3 * sizeof(float), .inputRate = VK_VERTEX_INPUT_RATE_VERTEX},
      {.binding = 2, .stride = 3 * sizeof(float), .inputRate = VK_VERTEX_INPUT_RATE_VERTEX},
  };
  const VkVertexInputAttributeDescription attributes[] = {
      {.location = 0, .binding = 0, .format = VK_FORMAT_R32G32B32_SFLOAT},
      {.location = 1, .binding = 1, .format = VK_FORMAT_R32G32B32_SFLOAT},
      {.location = 2, .binding = 2, .format = VK_FORMAT_R32G32B32_SFLOAT},
  };
  const VkPipelineVertexInputStateCreateInfo vertex_input = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
      .vertexBindingDescriptionCount = 3,
      .pVertexBindingDescriptions = bindings,
      .vertexAttributeDescriptionCount = 3,
      .pVertexAttributeDescriptions = attributes,
  };
  const VkPipelineInputAssemblyStateCreateInfo assembly = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
      .topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP,
  };
  const VkPipelineViewportStateCreateInfo viewport = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
      .viewportCount = 1,
      .scissorCount = 1,
  };
  const VkPipelineRasterizationStateCreateInfo rasterization = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
      .polygonMode = VK_POLYGON_MODE_FILL,
      .cullMode = VK_CULL_MODE_BACK_BIT,
      .frontFace = VK_FRONT_FACE_CLOCKWISE,
      .lineWidth = 1.0f,
  };
  const VkPipelineMultisampleStateCreateInfo multisample = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
      .rasterizationSamples = VK_SAMPLE_COUNT_1_BIT,
  };
  const VkPipelineColorBlendAttachmentState color_attachment = {
      .colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT |
                        VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT,
  };
  const VkPipelineColorBlendStateCreateInfo blend = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
      .attachmentCount = 1,
      .pAttachments = &color_attachment,
  };
  const VkDynamicState dynamic_states[] = {VK_DYNAMIC_STATE_VIEWPORT,
                                           VK_DYNAMIC_STATE_SCISSOR};
  const VkPipelineDynamicStateCreateInfo dynamic = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
      .dynamicStateCount = 2,
      .pDynamicStates = dynamic_states,
  };
  const VkGraphicsPipelineCreateInfo pipeline_info = {
      .sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
      .stageCount = 2,
      .pStages = stages,
      .pVertexInputState = &vertex_input,
      .pInputAssemblyState = &assembly,
      .pViewportState = &viewport,
      .pRasterizationState = &rasterization,
      .pMultisampleState = &multisample,
      .pColorBlendState = &blend,
      .pDynamicState = &dynamic,
      .layout = app->pipeline_layout,
      .renderPass = app->render_pass,
  };
  VkResult result = vkCreateGraphicsPipelines(app->device, VK_NULL_HANDLE, 1,
                                               &pipeline_info, NULL, &app->pipeline);
  vkDestroyShaderModule(app->device, fragment_module, NULL);
  vkDestroyShaderModule(app->device, vertex_module, NULL);
  return vk_error(result, "vkCreateGraphicsPipelines");
}

static int init_buffers(struct app *app) {
  for (uint32_t i = 0; i < BUFFER_COUNT; ++i) {
    struct buffer *buffer = &app->buffers[i];

    const VkImageCreateInfo image_info = {
        .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = VK_IMAGE_TYPE_2D,
        .format = VK_FORMAT_B8G8R8A8_UNORM,
        .extent = {app->width, app->height, 1},
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = VK_SAMPLE_COUNT_1_BIT,
        .tiling = VK_IMAGE_TILING_OPTIMAL,
        .usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
        .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
        .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
    };
    VK_CHECK(vkCreateImage(app->device, &image_info, NULL, &buffer->image));
    VkMemoryRequirements requirements;
    vkGetImageMemoryRequirements(app->device, buffer->image, &requirements);
    int memory_type = find_memory_type(app, requirements.memoryTypeBits,
                                       VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    if (memory_type < 0)
      memory_type = find_memory_type(app, requirements.memoryTypeBits, 0);
    if (memory_type < 0)
      return fprintf(stderr, "vkcube: no image memory\n"), -1;
    const VkMemoryAllocateInfo image_allocation = {
        .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = requirements.size,
        .memoryTypeIndex = (uint32_t)memory_type,
    };
    VK_CHECK(vkAllocateMemory(app->device, &image_allocation, NULL,
                              &buffer->image_memory));
    VK_CHECK(vkBindImageMemory(app->device, buffer->image, buffer->image_memory, 0));
    const VkImageViewCreateInfo view_info = {
        .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = buffer->image,
        .viewType = VK_IMAGE_VIEW_TYPE_2D,
        .format = VK_FORMAT_B8G8R8A8_UNORM,
        .subresourceRange = {
            .aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
            .levelCount = 1,
            .layerCount = 1,
        },
    };
    VK_CHECK(vkCreateImageView(app->device, &view_info, NULL, &buffer->view));
    const VkFramebufferCreateInfo framebuffer_info = {
        .sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
        .renderPass = app->render_pass,
        .attachmentCount = 1,
        .pAttachments = &buffer->view,
        .width = app->width,
        .height = app->height,
        .layers = 1,
    };
    VK_CHECK(vkCreateFramebuffer(app->device, &framebuffer_info, NULL,
                                 &buffer->framebuffer));

    const VkDeviceSize staging_size =
        (VkDeviceSize)app->width * (VkDeviceSize)app->height * 4u;
    if (create_buffer_memory(app, staging_size, VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                             VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
                                 VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                             &buffer->staging, &buffer->staging_memory,
                             &buffer->staging_map) != 0)
      return -1;
    const VkCommandBufferAllocateInfo command_info = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = app->command_pool,
        .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };
    VK_CHECK(vkAllocateCommandBuffers(app->device, &command_info,
                                      &buffer->command_buffer));
    const VkFenceCreateInfo fence_info = {
        .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = VK_FENCE_CREATE_SIGNALED_BIT,
    };
    VK_CHECK(vkCreateFence(app->device, &fence_info, NULL, &buffer->fence));
  }
  return 0;
}

static void destroy_frame_buffers(struct app *app) {
  if (!app->device)
    return;
  vkDeviceWaitIdle(app->device);
  for (uint32_t i = 0; i < BUFFER_COUNT; ++i) {
    struct buffer *buffer = &app->buffers[i];
    if (buffer->fence)
      vkDestroyFence(app->device, buffer->fence, NULL);
    if (buffer->command_buffer)
      vkFreeCommandBuffers(app->device, app->command_pool, 1,
                           &buffer->command_buffer);
    if (buffer->staging_map)
      vkUnmapMemory(app->device, buffer->staging_memory);
    if (buffer->staging)
      vkDestroyBuffer(app->device, buffer->staging, NULL);
    if (buffer->staging_memory)
      vkFreeMemory(app->device, buffer->staging_memory, NULL);
    if (buffer->framebuffer)
      vkDestroyFramebuffer(app->device, buffer->framebuffer, NULL);
    if (buffer->view)
      vkDestroyImageView(app->device, buffer->view, NULL);
    if (buffer->image)
      vkDestroyImage(app->device, buffer->image, NULL);
    if (buffer->image_memory)
      vkFreeMemory(app->device, buffer->image_memory, NULL);
    memset(buffer, 0, sizeof(*buffer));
  }
}

/* Match opengl-cube: honor xdg_toplevel configure by resizing the Wayland
 * dmabuf swapchain and rebuilding Vulkan color/staging targets. */
static int apply_pending_size(struct app *app) {
  if (!app->size_dirty)
    return 0;
  if (app->pending_width == 0 || app->pending_height == 0) {
    app->size_dirty = false;
    return 0;
  }
  if (app->pending_width == app->width && app->pending_height == app->height &&
      app->swapchain) {
    app->size_dirty = false;
    return 0;
  }

  app->width = app->pending_width;
  app->height = app->pending_height;

  if (app->swapchain &&
      iland_wl_swapchain_resize(app->swapchain, app->width, app->height) < 0)
    return fprintf(stderr, "vkcube: swapchain resize to %ux%u failed\n",
                   app->width, app->height),
           -1;

  if (app->device != VK_NULL_HANDLE && app->render_pass != VK_NULL_HANDLE) {
    destroy_frame_buffers(app);
    if (init_buffers(app) != 0)
      return fprintf(stderr, "vkcube: buffer recreate at %ux%u failed\n",
                     app->width, app->height),
             -1;
  }

  fprintf(stderr, "vkcube: resized to %ux%u\n", app->width, app->height);
  app->size_dirty = false;
  return 0;
}

static void update_ubo(struct app *app, uint32_t frame) {
  struct ubo ubo;
  matrix_identity(&ubo.modelview);
  matrix_translate(&ubo.modelview, 0.0f, 0.0f, -8.0f);
  matrix_rotate(&ubo.modelview, 45.0f + 0.6f * frame, 1, 0, 0);
  matrix_rotate(&ubo.modelview, 45.0f - 1.2f * frame, 0, 1, 0);
  matrix_rotate(&ubo.modelview, 10.0f + 0.3f * frame, 0, 0, 1);
  struct matrix projection;
  matrix_identity(&projection);
  float aspect = (float)app->height / (float)app->width;
  matrix_frustum(&projection, -2.8f, 2.8f, -2.8f * aspect, 2.8f * aspect, 6, 10);
  matrix_identity(&ubo.modelviewprojection);
  matrix_multiply(&ubo.modelviewprojection, &ubo.modelview, &projection);
  memcpy(ubo.normal, &ubo.modelview, sizeof(ubo.normal));
  memcpy(app->vertex_map, &ubo, sizeof(ubo));
}

static int render_frame(struct app *app, struct buffer *buffer, uint32_t frame) {
  VK_CHECK(vkWaitForFences(app->device, 1, &buffer->fence, VK_TRUE, UINT64_MAX));
  VK_CHECK(vkResetFences(app->device, 1, &buffer->fence));
  VK_CHECK(vkResetCommandBuffer(buffer->command_buffer, 0));
  update_ubo(app, frame);
  const VkCommandBufferBeginInfo begin = {
      .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
      .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
  };
  VK_CHECK(vkBeginCommandBuffer(buffer->command_buffer, &begin));
  const VkClearValue clear = {.color = {{0.2f, 0.2f, 0.2f, 1.0f}}};
  const VkRenderPassBeginInfo render = {
      .sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
      .renderPass = app->render_pass,
      .framebuffer = buffer->framebuffer,
      .renderArea = {{0, 0}, {app->width, app->height}},
      .clearValueCount = 1,
      .pClearValues = &clear,
  };
  vkCmdBeginRenderPass(buffer->command_buffer, &render, VK_SUBPASS_CONTENTS_INLINE);
  VkBuffer vertex_buffers[] = {app->vertex_buffer, app->vertex_buffer,
                               app->vertex_buffer};
  VkDeviceSize offsets[] = {app->vertex_offset, app->color_offset,
                            app->normal_offset};
  vkCmdBindVertexBuffers(buffer->command_buffer, 0, 3, vertex_buffers, offsets);
  vkCmdBindPipeline(buffer->command_buffer, VK_PIPELINE_BIND_POINT_GRAPHICS,
                    app->pipeline);
  vkCmdBindDescriptorSets(buffer->command_buffer, VK_PIPELINE_BIND_POINT_GRAPHICS,
                          app->pipeline_layout, 0, 1, &app->descriptor_set, 0, NULL);
  const VkViewport viewport = {0, 0, (float)app->width, (float)app->height, 0, 1};
  const VkRect2D scissor = {{0, 0}, {app->width, app->height}};
  vkCmdSetViewport(buffer->command_buffer, 0, 1, &viewport);
  vkCmdSetScissor(buffer->command_buffer, 0, 1, &scissor);
  for (uint32_t first = 0; first < 24; first += 4)
    vkCmdDraw(buffer->command_buffer, 4, 1, first, 0);
  vkCmdEndRenderPass(buffer->command_buffer);
  const VkBufferImageCopy copy = {
      .bufferOffset = 0,
      .bufferRowLength = app->width,
      .bufferImageHeight = app->height,
      .imageSubresource = {
          .aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
          .mipLevel = 0,
          .baseArrayLayer = 0,
          .layerCount = 1,
      },
      .imageExtent = {app->width, app->height, 1},
  };
  vkCmdCopyImageToBuffer(buffer->command_buffer, buffer->image,
                         VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, buffer->staging, 1,
                         &copy);
  VK_CHECK(vkEndCommandBuffer(buffer->command_buffer));
  const VkSubmitInfo submit = {
      .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
      .commandBufferCount = 1,
      .pCommandBuffers = &buffer->command_buffer,
  };
  VK_CHECK(vkQueueSubmit(app->queue, 1, &submit, buffer->fence));
  VK_CHECK(vkWaitForFences(app->device, 1, &buffer->fence, VK_TRUE, UINT64_MAX));

  wwn_cube_hud_tick(&g_hud);
  wwn_cube_hud_blit_rgba(buffer->staging_map, (int)app->width, (int)app->height,
                         (int)app->width * 4, &g_hud, 1);

  if (iland_wl_swapchain_present_pixels(app->swapchain, buffer->staging_map,
                                         app->width * 4u) != 0)
    return fprintf(stderr, "vkcube: wayland present failed\n"), -1;
  /* Drain releases so acquire does not stall forever. */
  wl_display_dispatch_pending(app->display);
  wl_display_flush(app->display);
  return 0;
}

static void destroy_app(struct app *app) {
  destroy_frame_buffers(app);
  if (app->device && app->vertex_map)
    vkUnmapMemory(app->device, app->vertex_memory);
  if (app->device && app->vertex_buffer)
    vkDestroyBuffer(app->device, app->vertex_buffer, NULL);
  if (app->device && app->vertex_memory)
    vkFreeMemory(app->device, app->vertex_memory, NULL);
  if (app->device && app->descriptor_pool)
    vkDestroyDescriptorPool(app->device, app->descriptor_pool, NULL);
  if (app->device && app->pipeline)
    vkDestroyPipeline(app->device, app->pipeline, NULL);
  if (app->device && app->pipeline_layout)
    vkDestroyPipelineLayout(app->device, app->pipeline_layout, NULL);
  if (app->device && app->descriptor_set_layout)
    vkDestroyDescriptorSetLayout(app->device, app->descriptor_set_layout, NULL);
  if (app->device && app->render_pass)
    vkDestroyRenderPass(app->device, app->render_pass, NULL);
  if (app->device && app->command_pool)
    vkDestroyCommandPool(app->device, app->command_pool, NULL);
  if (app->device)
    vkDestroyDevice(app->device, NULL);
  if (app->instance)
    vkDestroyInstance(app->instance, NULL);
  if (app->swapchain)
    iland_wl_swapchain_destroy(app->swapchain);
  if (app->winsys)
    iland_wl_winsys_destroy(app->winsys);
  if (app->toplevel)
    xdg_toplevel_destroy(app->toplevel);
  if (app->xdg_surface)
    xdg_surface_destroy(app->xdg_surface);
  if (app->surface)
    wl_surface_destroy(app->surface);
  if (app->wm_base)
    xdg_wm_base_destroy(app->wm_base);
  if (app->compositor)
    wl_compositor_destroy(app->compositor);
  if (app->registry)
    wl_registry_destroy(app->registry);
  if (app->display)
    wl_display_disconnect(app->display);
}

static uint32_t parse_frame_count(int argc, char **argv) {
  uint32_t frames = DEFAULT_FRAMES;
  const char *environment = getenv("WAWONA_VKCUBE_FRAMES");
  if (environment && *environment)
    frames = (uint32_t)strtoul(environment, NULL, 10);
  for (int i = 1; i < argc; ++i) {
    const char prefix[] = "--frames=";
    if (strncmp(argv[i], prefix, sizeof(prefix) - 1) == 0)
      frames = (uint32_t)strtoul(argv[i] + sizeof(prefix) - 1, NULL, 10);
    else if (strcmp(argv[i], "--display-mode=kms") != 0 &&
             strcmp(argv[i], "--display-mode=wayland") != 0)
      fprintf(stderr, "vkcube: ignoring option %s\n", argv[i]);
  }
  return frames;
}

int main(int argc, char **argv) {
  struct app app;
  memset(&app, 0, sizeof(app));
  app.width = DEFAULT_WIDTH;
  app.height = DEFAULT_HEIGHT;
  int result = -1;
  if (init_wayland(&app) != 0 || init_vulkan(&app) != 0 ||
      init_render_pass(&app) != 0 || init_geometry(&app) != 0 ||
      init_pipeline(&app) != 0 || init_buffers(&app) != 0)
    goto out;

  uint32_t frames = parse_frame_count(argc, argv);
  fprintf(stderr,
          "vkcube: rendering %ux%u via Vulkan -> Wayland IOSurface dmabuf\n",
          app.width, app.height);
  for (uint32_t frame = 0; app.running && (frames == 0 || frame < frames);
       ++frame) {
    /* Non-blocking: present already flushes; drain configure/close here. */
    wl_display_dispatch_pending(app.display);
    wl_display_flush(app.display);

    if (apply_pending_size(&app) != 0)
      goto out;

    struct buffer *buffer = &app.buffers[frame % BUFFER_COUNT];
    if (render_frame(&app, buffer, frame) != 0)
      goto out;
  }
  result = 0;
out:
  destroy_app(&app);
  wwn_vkcube_close_dispatch();
  return result;
}
