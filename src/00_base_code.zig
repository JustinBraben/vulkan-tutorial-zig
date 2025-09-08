const std = @import("std");

const c = @import("c");

const WIDTH: u32 = 800;
const HEIGHT: u32 = 600;

const HelloTriangleApplication = struct {
    const Self = @This();

    window: ?*c.GLFWwindow = null,

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
        c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_FALSE);
        self.window = c.glfwCreateWindow(
        WIDTH,
        HEIGHT,
        "Vulkan",
        null,
        null,
        ) orelse return error.WindowInitFailed;
    }

    fn initVulkan(_: *Self) !void {}

    fn mainLoop(self: *Self) !void {
        while (c.glfwWindowShouldClose(self.window) == c.GLFW_FALSE) {
            c.glfwPollEvents();
        }
    }

    pub fn deinit(self: *Self) void {
        c.glfwDestroyWindow(self.window);

        c.glfwTerminate();
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
