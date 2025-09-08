const std = @import("std");
const c = @cImport({
    // REQUIRED only for GLFW CreateWindowSurface.
    @cDefine("GLFW_INCLUDE_VULKAN", {});
    @cInclude("GLFW/glfw3.h");
    @cDefine("STB_IMAGE_IMPLEMENTATION", {});
    @cInclude("stb/stb_image.h");
});

const vk = @import("vulkan");

// Re-export the GLFW things that we need
pub const GLFW_TRUE = c.GLFW_TRUE;
pub const GLFW_FALSE = c.GLFW_FALSE;
pub const GLFW_CLIENT_API = c.GLFW_CLIENT_API;
pub const GLFW_NO_API = c.GLFW_NO_API;
pub const GLFW_RESIZABLE = c.GLFW_RESIZABLE;
pub const GLFW_MOUSE_BUTTON_LEFT = c.GLFW_MOUSE_BUTTON_LEFT;
pub const GLFW_PRESS = c.GLFW_PRESS;
pub const GLFW_RELEASE = c.GLFW_RELEASE;
pub const GLFW_CURSOR = c.GLFW_CURSOR;
pub const GLFW_CURSOR_DISABLED = c.GLFW_CURSOR_DISABLED;
pub const GLFW_KEY_W = c.GLFW_KEY_W;
pub const GLFW_KEY_S = c.GLFW_KEY_S;
pub const GLFW_KEY_A = c.GLFW_KEY_A;
pub const GLFW_KEY_D = c.GLFW_KEY_D;
pub const GLFW_KEY_LEFT = c.GLFW_KEY_LEFT;
pub const GLFW_KEY_RIGHT = c.GLFW_KEY_RIGHT;
pub const GLFW_KEY_UP = c.GLFW_KEY_UP;
pub const GLFW_KEY_DOWN = c.GLFW_KEY_DOWN;
pub const GLFW_KEY_ESCAPE = c.GLFW_KEY_ESCAPE;


pub const GLFWwindow = c.GLFWwindow;

pub const glfwInit = c.glfwInit;
pub const glfwTerminate = c.glfwTerminate;
pub const glfwVulkanSupported = c.glfwVulkanSupported;
pub const glfwWindowHint = c.glfwWindowHint;
pub const glfwCreateWindow = c.glfwCreateWindow;
pub const glfwDestroyWindow = c.glfwDestroyWindow;
pub const glfwWindowShouldClose = c.glfwWindowShouldClose;
pub const glfwSetWindowShouldClose = c.glfwSetWindowShouldClose;
pub const glfwGetRequiredInstanceExtensions = c.glfwGetRequiredInstanceExtensions;
pub const glfwGetFramebufferSize = c.glfwGetFramebufferSize;
pub const glfwSetWindowUserPointer = c.glfwSetWindowUserPointer;
pub const glfwGetWindowUserPointer = c.glfwGetWindowUserPointer;
pub const glfwSetFramebufferSizeCallback = c.glfwSetFramebufferSizeCallback;
pub const glfwSetCursorPosCallback = c.glfwSetCursorPosCallback;
pub const glfwSetMouseButtonCallback = c.glfwSetMouseButtonCallback;
pub const glfwSetInputMode = c.glfwSetInputMode;
pub const glfwPollEvents = c.glfwPollEvents;
pub const glfwWaitEvents = c.glfwWaitEvents;
pub const glfwGetKey = c.glfwGetKey;

// usually the GLFW vulkan functions are exported if Vulkan is included,
// but since thats not the case here, they are manually imported.

pub extern fn glfwGetInstanceProcAddress(instance: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction;
pub extern fn glfwGetPhysicalDevicePresentationSupport(instance: vk.Instance, pdev: vk.PhysicalDevice, queuefamily: u32) c_int;
pub extern fn glfwCreateWindowSurface(instance: vk.Instance, window: *GLFWwindow, allocation_callbacks: ?*const vk.AllocationCallbacks, surface: *vk.SurfaceKHR) vk.Result;

// Re-export the STBI things that we need
pub const STBI_rgb_alpha = c.STBI_rgb_alpha;
pub const stbi_load = c.stbi_load;
pub const stbi_image_free = c.stbi_image_free;