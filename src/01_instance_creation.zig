const std = @import("std");
const vk = @import("vulkan");
const c = @import("c");
const Allocator = std.mem.Allocator;

const WIDTH: u32 = 800;
const HEIGHT: u32 = 600;

const BaseWrapper = vk.BaseWrapper;
const InstanceWrapper = vk.InstanceWrapper;
const Instance = vk.InstanceProxy;

const HelloTriangleApplication = struct {
    const Self = @This();

    window: ?*c.GLFWwindow = null,

    vkb: BaseWrapper = undefined,
    vki: InstanceWrapper = undefined,

    instance: Instance = undefined,

    pub fn init() Self {
        return Self{};
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
    }

    fn mainLoop(self: *Self) !void {
        while (c.glfwWindowShouldClose(self.window) == c.GLFW_FALSE) {
            c.glfwPollEvents();
        }
    }

    pub fn deinit(self: *Self) void {
        self.instance.destroyInstance(null);

        c.glfwDestroyWindow(self.window);

        c.glfwTerminate();
    }

    fn createInstance(self: *Self) !void {
        self.vkb = BaseWrapper.load(c.glfwGetInstanceProcAddress);

        const app_info = vk.ApplicationInfo{
            .p_application_name = "Hello Triangle",
            .application_version = @bitCast(vk.makeApiVersion(1, 0, 0, 0)),
            .p_engine_name = "No Engine",
            .engine_version = @bitCast(vk.makeApiVersion(1, 0, 0, 0)),
            .api_version = @bitCast(vk.API_VERSION_1_2),
        };

        var glfw_exts_count: u32 = 0;
        const glfw_exts = c.glfwGetRequiredInstanceExtensions(&glfw_exts_count);

        const instance = try self.vkb.createInstance(&.{
            .p_application_info = &app_info,
            .enabled_extension_count = glfw_exts_count,
            .pp_enabled_extension_names = @ptrCast(glfw_exts),
        }, null);

        self.vki = InstanceWrapper.load(instance, self.vkb.dispatch.vkGetInstanceProcAddr.?);
        self.instance = Instance.init(instance, &self.vki);
    }
};

pub fn main() void {
    var app = HelloTriangleApplication.init();
    defer app.deinit();
    app.run() catch |err| {
        std.log.err("application exited with error: {any}", .{err});
        return;
    };
}
