const std = @import("std");
const builtin = @import("builtin");
const is_macos = builtin.os.tag == .macos;
const vk = @import("vulkan");
const c = @import("c");
const Allocator = std.mem.Allocator;

const macos_extension_names = [_][*:0]const u8{
    vk.extensions.khr_portability_enumeration.name,
    vk.extensions.khr_get_physical_device_properties_2.name,
};

const WIDTH: u32 = 800;
const HEIGHT: u32 = 600;

const validation_layers = [_][*:0]const u8{"VK_LAYER_KHRONOS_validation"};

const macos_device_extensions = [_][*:0]const u8{vk.extensions.khr_portability_subset.name};

const enable_validation_layers: bool = switch (builtin.mode) {
    .Debug, .ReleaseSafe => true,
    else => false,
};

const BaseWrapper = vk.BaseWrapper;
const InstanceWrapper = vk.InstanceWrapper;
const DeviceWrapper = vk.DeviceWrapper;

const Instance = vk.InstanceProxy;
const Device = vk.DeviceProxy;

const QueueFamilyIndices = struct {
    graphics_family: ?u32 = null,

    fn isComplete(self: *const QueueFamilyIndices) bool {
        return self.graphics_family != null;
    }
};

const HelloTriangleApplication = struct {
    const Self = @This();
    allocator: Allocator,

    window: ?*c.GLFWwindow = null,

    vkb: BaseWrapper = undefined,
    vki: InstanceWrapper = undefined,

    instance: Instance = undefined,
    debug_messenger: vk.DebugUtilsMessengerEXT = .null_handle,

    physical_device: vk.PhysicalDevice = .null_handle,

    pub fn init(allocator: Allocator) Self {
        return Self{ .allocator = allocator };
    }

    pub fn run(self: *Self) !void {
        try self.initWindow();
        try self.initVulkan();
        try self.mainLoop();
    }

    fn initWindow(self: *Self) !void {
        if (c.glfwInit() != c.GLFW_TRUE) return error.GlfwInitFailed;
        c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
        self.window = c.glfwCreateWindow(
            WIDTH,
            HEIGHT,
            "Vulkan",
            null,
            null,
        ) orelse return error.WindowInitFailed;
    }

    fn initVulkan(self: *Self) !void {
        try self.createInstance();
        try self.setupDebugMessenger();
        try self.pickPhysicalDevice();
    }

    fn mainLoop(self: *Self) !void {
        while (c.glfwWindowShouldClose(self.window) == c.GLFW_FALSE) {
            c.glfwPollEvents();
        }
    }

    pub fn deinit(self: *Self) void {
        if (enable_validation_layers and self.debug_messenger != .null_handle) {
            self.instance.destroyDebugUtilsMessengerEXT(self.debug_messenger, null);
        }

        self.instance.destroyInstance(null);

        c.glfwDestroyWindow(self.window);

        c.glfwTerminate();
    }

    fn createInstance(self: *Self) !void {
        self.vkb = BaseWrapper.load(c.glfwGetInstanceProcAddress);

        if (enable_validation_layers and !try self.checkValidationLayerSupport()) {
            return error.MissingValidationLayer;
        }

        const app_info = vk.ApplicationInfo{
            .p_application_name = "Hello Triangle",
            .application_version = @bitCast(vk.makeApiVersion(1, 0, 0, 0)),
            .p_engine_name = "No Engine",
            .engine_version = @bitCast(vk.makeApiVersion(1, 0, 0, 0)),
            .api_version = @bitCast(vk.API_VERSION_1_2),
        };

        var extensions = try getRequiredExtensions(self.allocator);
        defer extensions.deinit();

        var create_info = vk.InstanceCreateInfo{
            .flags = if (is_macos) .{ .enumerate_portability_bit_khr = true } else .{},
            .p_application_info = &app_info,
            .enabled_layer_count = 0,
            .pp_enabled_layer_names = undefined,
            .enabled_extension_count = @intCast(extensions.items.len),
            .pp_enabled_extension_names = extensions.items.ptr,
        };

        if (enable_validation_layers) {
            create_info.enabled_layer_count = validation_layers.len;
            create_info.pp_enabled_layer_names = &validation_layers;

            var debug_create_info: vk.DebugUtilsMessengerCreateInfoEXT = undefined;
            populateDebugMessengerCreateInfo(&debug_create_info);
            create_info.p_next = &debug_create_info;
        }

        const instance = try self.vkb.createInstance(&create_info, null);

        self.vki = InstanceWrapper.load(instance, self.vkb.dispatch.vkGetInstanceProcAddr.?);
        self.instance = Instance.init(instance, &self.vki);
    }

    fn populateDebugMessengerCreateInfo(create_info: *vk.DebugUtilsMessengerCreateInfoEXT) void {
        create_info.* = .{
            .flags = .{},
            .message_severity = .{
                .verbose_bit_ext = true,
                .warning_bit_ext = true,
                .error_bit_ext = true,
            },
            .message_type = .{
                .general_bit_ext = true,
                .validation_bit_ext = true,
                .performance_bit_ext = true,
            },
            .pfn_user_callback = debugCallback,
            .p_user_data = null,
        };
    }

    fn setupDebugMessenger(self: *Self) !void {
        if (!enable_validation_layers) return;

        var create_info: vk.DebugUtilsMessengerCreateInfoEXT = undefined;
        populateDebugMessengerCreateInfo(&create_info);

        self.debug_messenger = try self.instance.createDebugUtilsMessengerEXT(&create_info, null);
    }

    fn pickPhysicalDevice(self: *Self) !void {
        const devices = try self.instance.enumeratePhysicalDevicesAlloc(self.allocator);
        defer self.allocator.free(devices);

        if (devices.len == 0) {
            return error.NoGPUsSupportVulkan;
        }

        for (devices) |device| {
            if (try self.isDeviceSuitable(device)) {
                self.physical_device = device;
                break;
            }
        }

        if (self.physical_device == .null_handle) {
            return error.NoSuitableDevice;
        }
    }

    fn isDeviceSuitable(self: *Self, device: vk.PhysicalDevice) !bool {
        const indices = try self.findQueueFamilies(device);

        return indices.isComplete();
    }

    fn findQueueFamilies(self: *Self, device: vk.PhysicalDevice) !QueueFamilyIndices {
        var indices: QueueFamilyIndices = .{};

        const queue_families = try self.instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(device, self.allocator);
        defer self.allocator.free(queue_families);

        for (queue_families, 0..) |queue_family, i| {
            if (queue_family.queue_flags.graphics_bit) {
                indices.graphics_family = @intCast(i);
            }

            if (indices.isComplete()) {
                break;
            }
        }

        return indices;
    }

    fn getRequiredExtensions(allocator: Allocator) !std.ArrayListAligned([*:0]const u8, null) {
        var extension_names = std.ArrayList([*:0]const u8).init(allocator);
        // these extensions are to support vulkan in mac os
        // glfw will get get them by default https://github.com/glfw/glfw/issues/2335
        if (is_macos) try extension_names.appendSlice(macos_extension_names[0..]);

        var glfw_exts_count: u32 = 0;
        const glfw_exts = c.glfwGetRequiredInstanceExtensions(&glfw_exts_count);
        try extension_names.appendSlice(@ptrCast(glfw_exts[0..glfw_exts_count]));

        if (enable_validation_layers) {
            try extension_names.append(vk.extensions.ext_debug_utils.name);
        }

        return extension_names;
    }

    fn checkValidationLayerSupport(self: *Self) !bool {
        const available_layers = try self.vkb.enumerateInstanceLayerPropertiesAlloc(self.allocator);
        defer self.allocator.free(available_layers);

        for (validation_layers) |layer_name| {
            var layer_found: bool = false;

            for (available_layers) |layer_properties| {
                const available_len = std.mem.indexOfScalar(u8, &layer_properties.layer_name, 0).?;
                const available_layer_name = layer_properties.layer_name[0..available_len];
                if (std.mem.eql(u8, std.mem.span(layer_name), available_layer_name)) {
                    layer_found = true;
                    break;
                }
            }

            if (!layer_found) {
                return false;
            }
        }

        return true;
    }

    fn debugCallback(_: vk.DebugUtilsMessageSeverityFlagsEXT, _: vk.DebugUtilsMessageTypeFlagsEXT, p_callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT, _: ?*anyopaque) callconv(vk.vulkan_call_conv) vk.Bool32 {
        if (p_callback_data != null) {
            std.log.debug("validation layer: {s}", .{p_callback_data.?.p_message});
        }

        return vk.FALSE;
    }
};

pub fn main() void {
    var gpa_impl = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_impl.deinit();
    const gpa = gpa_impl.allocator();

    var app = HelloTriangleApplication.init(gpa);
    defer app.deinit();
    app.run() catch |err| {
        std.log.err("application exited with error: {any}", .{err});
        return;
    };
}
