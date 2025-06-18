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
const resources = @import("resources");

const vert_spv align(@alignOf(u32)) = resources.shaders.vert_18.*;
const frag_spv align(@alignOf(u32)) = resources.shaders.frag_18.*;

const WIDTH: u32 = 800;
const HEIGHT: u32 = 600;

const MAX_FRAMES_IN_FLIGHT: u32 = 2;

const validation_layers = [_][*:0]const u8{"VK_LAYER_KHRONOS_validation"};

const device_extensions = [_][*:0]const u8{vk.extensions.khr_swapchain.name};
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
    present_family: ?u32 = null,

    fn isComplete(self: *const QueueFamilyIndices) bool {
        return self.graphics_family != null and self.present_family != null;
    }
};

pub const SwapChainSupportDetails = struct {
    allocator: Allocator,
    capabilities: vk.SurfaceCapabilitiesKHR = undefined,
    formats: ?[]vk.SurfaceFormatKHR = null,
    present_modes: ?[]vk.PresentModeKHR = null,

    pub fn init(allocator: Allocator) SwapChainSupportDetails {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: SwapChainSupportDetails) void {
        if (self.formats != null) self.allocator.free(self.formats.?);
        if (self.present_modes != null) self.allocator.free(self.present_modes.?);
    }
};

pub const Vertex = struct {
    pos: [2]f32 = .{ 0, 0 },
    color: [3]f32 = .{ 0, 0, 0 },

    pub fn getBindingDescription() vk.VertexInputBindingDescription {
        return vk.VertexInputBindingDescription{
            .binding = 0,
            .stride = @sizeOf(Vertex),
            .input_rate = .vertex,
        };
    }

    pub fn getAttributeDescriptions() [2]vk.VertexInputAttributeDescription {
        return [2]vk.VertexInputAttributeDescription{
            .{
                .binding = 0,
                .location = 0,
                .format = .r32g32_sfloat,
                .offset = @offsetOf(Vertex, "pos"),
            },
            .{
                .binding = 0,
                .location = 1,
                .format = .r32g32b32_sfloat,
                .offset = @offsetOf(Vertex, "color"),
            },
        };
    }
};

const vertices = [_]Vertex{
    .{ .pos = .{ -0.5, -0.5 }, .color = .{ 1, 0, 0 } },
    .{ .pos = .{ 0.5, -0.5 }, .color = .{ 0, 1, 0 } },
    .{ .pos = .{ 0.5, 0.5 }, .color = .{ 0, 0, 1 } },
    .{ .pos = .{ -0.5, 0.5 }, .color = .{ 1, 1, 1 } },
};

const indices_input = [_]u16{ 0, 1, 2, 2, 3, 0 };

const HelloTriangleApplication = struct {
    const Self = @This();
    allocator: Allocator,

    window: ?*c.GLFWwindow = null,

    vkb: BaseWrapper = undefined,
    vki: InstanceWrapper = undefined,
    vkd: DeviceWrapper = undefined,

    instance: Instance = undefined,
    debug_messenger: vk.DebugUtilsMessengerEXT = .null_handle,
    surface: vk.SurfaceKHR = .null_handle,

    physical_device: vk.PhysicalDevice = .null_handle,
    device: Device = undefined,

    graphics_queue: vk.Queue = .null_handle,
    present_queue: vk.Queue = .null_handle,

    swap_chain: vk.SwapchainKHR = .null_handle,
    swap_chain_images: ?[]vk.Image = null,
    swap_chain_image_format: vk.Format = .undefined,
    swap_chain_extent: vk.Extent2D = .{ .width = 0, .height = 0 },
    swap_chain_image_views: ?[]vk.ImageView = null,
    swap_chain_framebuffers: ?[]vk.Framebuffer = null,

    render_pass: vk.RenderPass = .null_handle,
    pipeline_layout: vk.PipelineLayout = .null_handle,
    graphics_pipeline: vk.Pipeline = .null_handle,

    command_pool: vk.CommandPool = .null_handle,

    vertex_buffer: vk.Buffer = .null_handle,
    vertex_buffer_memory: vk.DeviceMemory = .null_handle,
    index_buffer: vk.Buffer = .null_handle,
    index_buffer_memory: vk.DeviceMemory = .null_handle,

    command_buffers: ?[]vk.CommandBuffer = null,

    image_available_semaphores: ?[]vk.Semaphore = null,
    render_finished_semaphores: ?[]vk.Semaphore = null,
    in_flight_fences: ?[]vk.Fence = null,
    current_frame: u32 = 0,

    framebuffer_resized: bool = false,

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
        c.glfwSetWindowUserPointer(self.window, self);
        _ = c.glfwSetFramebufferSizeCallback(self.window, framebufferResizeCallback);
    }

    fn framebufferResizeCallback(window: ?*c.GLFWwindow, _: c_int, _: c_int) callconv(.c) void {
        var self: *Self = @ptrCast(@alignCast(c.glfwGetWindowUserPointer(window)));
        self.framebuffer_resized = true;
    }

    fn initVulkan(self: *Self) !void {
        try self.createInstance();
        try self.setupDebugMessenger();
        try self.createSurface();
        try self.pickPhysicalDevice();
        try self.createLogicalDevice();
        try self.createSwapChain();
        try self.createImageViews();
        try self.createRenderPass();
        try self.createGraphicsPipeline();
        try self.createFramebuffers();
        try self.createCommandPool();
        try self.createVertexBuffer();
        try self.createIndexBuffer();
        try self.createCommandBuffers();
        try self.createSyncObjects();
    }

    fn mainLoop(self: *Self) !void {
        while (c.glfwWindowShouldClose(self.window) == c.GLFW_FALSE) {
            c.glfwPollEvents();
            try self.drawFrame();
        }

        _ = try self.device.deviceWaitIdle();
    }

    fn cleanupSwapChain(self: *Self) void {
        if (self.swap_chain_framebuffers) |swap_chain_framebuffers| {
            for (swap_chain_framebuffers) |framebuffer| {
                self.device.destroyFramebuffer(framebuffer, null);
            }
            self.allocator.free(swap_chain_framebuffers);
            self.swap_chain_framebuffers = null;
        }

        if (self.swap_chain_image_views) |swap_chain_image_views| {
            for (swap_chain_image_views) |image_view| {
                self.device.destroyImageView(image_view, null);
            }
            self.allocator.free(swap_chain_image_views);
            self.swap_chain_image_views = null;
        }

        if (self.swap_chain_images) |swap_chain_images| {
            self.allocator.free(swap_chain_images);
            self.swap_chain_images = null;
        }

        if (self.swap_chain != .null_handle) {
            self.device.destroySwapchainKHR(self.swap_chain, null);
            self.swap_chain = .null_handle;
        }
    }

    pub fn deinit(self: *Self) void {
        self.cleanupSwapChain();

        if (self.graphics_pipeline != .null_handle) self.device.destroyPipeline(self.graphics_pipeline, null);
        if (self.pipeline_layout != .null_handle) self.device.destroyPipelineLayout(self.pipeline_layout, null);
        if (self.render_pass != .null_handle) self.device.destroyRenderPass(self.render_pass, null);

        if (self.index_buffer != .null_handle) self.device.destroyBuffer(self.index_buffer, null);
        if (self.index_buffer_memory != .null_handle) self.device.freeMemory(self.index_buffer_memory, null);

        if (self.vertex_buffer != .null_handle) self.device.destroyBuffer(self.vertex_buffer, null);
        if (self.vertex_buffer_memory != .null_handle) self.device.freeMemory(self.vertex_buffer_memory, null);

        if (self.render_finished_semaphores != null) {
            for (self.render_finished_semaphores.?) |semaphore| {
                self.device.destroySemaphore(semaphore, null);
            }
            self.allocator.free(self.render_finished_semaphores.?);
        }
        if (self.image_available_semaphores != null) {
            for (self.image_available_semaphores.?) |semaphore| {
                self.device.destroySemaphore(semaphore, null);
            }
            self.allocator.free(self.image_available_semaphores.?);
        }
        if (self.in_flight_fences != null) {
            for (self.in_flight_fences.?) |fence| {
                self.device.destroyFence(fence, null);
            }
            self.allocator.free(self.in_flight_fences.?);
        }

        if (self.command_pool != .null_handle) self.device.destroyCommandPool(self.command_pool, null);
        if (self.command_buffers != null) self.allocator.free(self.command_buffers.?);

        if (self.device.handle != .null_handle) self.device.destroyDevice(null);

        if (enable_validation_layers and self.debug_messenger != .null_handle) {
            self.instance.destroyDebugUtilsMessengerEXT(self.debug_messenger, null);
        }

        self.instance.destroySurfaceKHR(self.surface, null);
        self.instance.destroyInstance(null);

        c.glfwDestroyWindow(self.window);

        c.glfwTerminate();
    }

    fn recreateSwapChain(self: *Self) !void {
        var window_width: u32 = undefined;
        var window_height: u32 = undefined;
        c.glfwGetFramebufferSize(self.window.?, @ptrCast(&window_width), @ptrCast(&window_height));

        while (window_width == 0 or window_height == 0) {
            c.glfwGetFramebufferSize(self.window.?, @ptrCast(&window_width), @ptrCast(&window_height));
            c.glfwWaitEvents();
        }

        try self.device.deviceWaitIdle();

        self.cleanupSwapChain();

        try self.createSwapChain();
        try self.createImageViews();
        try self.createFramebuffers();
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

    fn createSurface(self: *Self) !void {
        if (c.glfwCreateWindowSurface(self.instance.handle, self.window.?, null, &self.surface) != .success) {
            return error.SurfaceInitFailed;
        }
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

    fn createLogicalDevice(self: *Self) !void {
        const indices = try self.findQueueFamilies(self.physical_device);
        const queue_priority = [_]f32{1};

        var queue_create_info = [_]vk.DeviceQueueCreateInfo{
            .{
                .flags = .{},
                .queue_family_index = indices.graphics_family.?,
                .queue_count = 1,
                .p_queue_priorities = &queue_priority,
            },
            .{
                .flags = .{},
                .queue_family_index = indices.present_family.?,
                .queue_count = 1,
                .p_queue_priorities = &queue_priority,
            },
        };

        var device_extension_names = std.ArrayList([*:0]const u8).init(self.allocator);
        defer device_extension_names.deinit();
        try device_extension_names.appendSlice(device_extensions[0..]);
        if (is_macos) try device_extension_names.appendSlice(macos_device_extensions[0..]);

        var create_info = vk.DeviceCreateInfo{
            .flags = .{},
            .queue_create_info_count = queue_create_info.len,
            .p_queue_create_infos = &queue_create_info,
            .enabled_layer_count = 0,
            .pp_enabled_layer_names = undefined,
            .enabled_extension_count = @intCast(device_extension_names.items.len),
            .pp_enabled_extension_names = device_extension_names.items.ptr,
            .p_enabled_features = null,
        };

        if (enable_validation_layers) {
            create_info.enabled_layer_count = validation_layers.len;
            create_info.pp_enabled_layer_names = &validation_layers;
        }

        const device = try self.instance.createDevice(self.physical_device, &create_info, null);

        self.vkd = DeviceWrapper.load(device, self.instance.wrapper.dispatch.vkGetDeviceProcAddr.?);
        self.device = Device.init(device, &self.vkd);

        self.graphics_queue = self.device.getDeviceQueue(indices.graphics_family.?, 0);
        self.present_queue = self.device.getDeviceQueue(indices.present_family.?, 0);
    }

    fn createSwapChain(self: *Self) !void {
        const swap_chain_support = try self.querySwapChainSupport(self.physical_device);
        defer swap_chain_support.deinit();

        const surface_format: vk.SurfaceFormatKHR = chooseSwapSurfaceFormat(swap_chain_support.formats.?);
        const present_mode: vk.PresentModeKHR = chooseSwapPresentMode(swap_chain_support.present_modes.?);
        const extent: vk.Extent2D = try self.chooseSwapExtent(swap_chain_support.capabilities);

        var image_count = swap_chain_support.capabilities.min_image_count + 1;
        if (swap_chain_support.capabilities.max_image_count > 0) {
            image_count = @min(image_count, swap_chain_support.capabilities.max_image_count);
        }

        const indices = try self.findQueueFamilies(self.physical_device);
        const queue_family_indices = [_]u32{ indices.graphics_family.?, indices.present_family.? };
        const sharing_mode: vk.SharingMode = if (indices.graphics_family.? != indices.present_family.?)
            .concurrent
        else
            .exclusive;

        self.swap_chain = try self.device.createSwapchainKHR(&.{
            .flags = .{},
            .surface = self.surface,
            .min_image_count = image_count,
            .image_format = surface_format.format,
            .image_color_space = surface_format.color_space,
            .image_extent = extent,
            .image_array_layers = 1,
            .image_usage = .{ .color_attachment_bit = true },
            .image_sharing_mode = sharing_mode,
            .queue_family_index_count = queue_family_indices.len,
            .p_queue_family_indices = &queue_family_indices,
            .pre_transform = swap_chain_support.capabilities.current_transform,
            .composite_alpha = .{ .opaque_bit_khr = true },
            .present_mode = present_mode,
            .clipped = vk.TRUE,
            .old_swapchain = .null_handle,
        }, null);

        self.swap_chain_images = try self.device.getSwapchainImagesAllocKHR(self.swap_chain, self.allocator);

        self.swap_chain_image_format = surface_format.format;
        self.swap_chain_extent = extent;
    }

    fn createImageViews(self: *Self) !void {
        self.swap_chain_image_views = try self.allocator.alloc(vk.ImageView, self.swap_chain_images.?.len);

        for (self.swap_chain_images.?, 0..) |image, i| {
            self.swap_chain_image_views.?[i] = try self.device.createImageView(&.{
                .flags = .{},
                .image = image,
                .view_type = .@"2d",
                .format = self.swap_chain_image_format,
                .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
                .subresource_range = .{
                    .aspect_mask = .{ .color_bit = true },
                    .base_mip_level = 0,
                    .level_count = 1,
                    .base_array_layer = 0,
                    .layer_count = 1,
                },
            }, null);
        }
    }

    fn createRenderPass(self: *Self) !void {
        const color_attachment = [_]vk.AttachmentDescription{.{
            .flags = .{},
            .format = self.swap_chain_image_format,
            .samples = .{ .@"1_bit" = true },
            .load_op = .clear,
            .store_op = .store,
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            .initial_layout = .undefined,
            .final_layout = .present_src_khr,
        }};

        const color_attachment_ref = [_]vk.AttachmentReference{.{
            .attachment = 0,
            .layout = .color_attachment_optimal,
        }};

        const subpass = [_]vk.SubpassDescription{.{
            .flags = .{},
            .pipeline_bind_point = .graphics,
            .input_attachment_count = 0,
            .p_input_attachments = undefined,
            .color_attachment_count = color_attachment_ref.len,
            .p_color_attachments = &color_attachment_ref,
            .p_resolve_attachments = null,
            .p_depth_stencil_attachment = null,
            .preserve_attachment_count = 0,
            .p_preserve_attachments = undefined,
        }};

        const dependencies = [_]vk.SubpassDependency{.{
            .src_subpass = vk.SUBPASS_EXTERNAL,
            .dst_subpass = 0,
            .src_stage_mask = .{ .color_attachment_output_bit = true },
            .src_access_mask = .{},
            .dst_stage_mask = .{ .color_attachment_output_bit = true },
            .dst_access_mask = .{ .color_attachment_write_bit = true },
            .dependency_flags = .{},
        }};

        self.render_pass = try self.device.createRenderPass(&.{
            .flags = .{},
            .attachment_count = color_attachment.len,
            .p_attachments = &color_attachment,
            .subpass_count = subpass.len,
            .p_subpasses = &subpass,
            .dependency_count = dependencies.len,
            .p_dependencies = &dependencies,
        }, null);
    }

    fn createGraphicsPipeline(self: *Self) !void {
        const vert_shader_module: vk.ShaderModule = try self.device.createShaderModule(&.{
            .code_size = vert_spv.len,
            .p_code = @ptrCast(&vert_spv),
        }, null);
        defer self.device.destroyShaderModule(vert_shader_module, null);
        const frag_shader_module: vk.ShaderModule = try self.device.createShaderModule(&.{
            .code_size = frag_spv.len,
            .p_code = @ptrCast(&frag_spv),
        }, null);
        defer self.device.destroyShaderModule(frag_shader_module, null);

        const shader_stages = [_]vk.PipelineShaderStageCreateInfo{
            .{
                .flags = .{},
                .stage = .{ .vertex_bit = true },
                .module = vert_shader_module,
                .p_name = "main",
                .p_specialization_info = null,
            },
            .{
                .flags = .{},
                .stage = .{ .fragment_bit = true },
                .module = frag_shader_module,
                .p_name = "main",
                .p_specialization_info = null,
            },
        };

        const binding_description = Vertex.getBindingDescription();
        const attribute_descriptions = Vertex.getAttributeDescriptions();

        const vertex_input_info = vk.PipelineVertexInputStateCreateInfo{
            .flags = .{},
            .vertex_binding_description_count = 1,
            .p_vertex_binding_descriptions = @ptrCast(&binding_description),
            .vertex_attribute_description_count = attribute_descriptions.len,
            .p_vertex_attribute_descriptions = &attribute_descriptions,
        };

        const input_assembly = vk.PipelineInputAssemblyStateCreateInfo{
            .flags = .{},
            .topology = .triangle_list,
            .primitive_restart_enable = vk.FALSE,
        };

        const viewport_state = vk.PipelineViewportStateCreateInfo{
            .flags = .{},
            .viewport_count = 1,
            .p_viewports = undefined,
            .scissor_count = 1,
            .p_scissors = undefined,
        };

        const rasterizer = vk.PipelineRasterizationStateCreateInfo{
            .flags = .{},
            .depth_clamp_enable = vk.FALSE,
            .rasterizer_discard_enable = vk.FALSE,
            .polygon_mode = .fill,
            .cull_mode = .{ .back_bit = true },
            .front_face = .clockwise,
            .depth_bias_enable = vk.FALSE,
            .depth_bias_constant_factor = 0,
            .depth_bias_clamp = 0,
            .depth_bias_slope_factor = 0,
            .line_width = 1,
        };

        const multisampling = vk.PipelineMultisampleStateCreateInfo{
            .flags = .{},
            .rasterization_samples = .{ .@"1_bit" = true },
            .sample_shading_enable = vk.FALSE,
            .min_sample_shading = 1,
            .p_sample_mask = null,
            .alpha_to_coverage_enable = vk.FALSE,
            .alpha_to_one_enable = vk.FALSE,
        };

        const color_blend_attachment = [_]vk.PipelineColorBlendAttachmentState{.{
            .blend_enable = vk.FALSE,
            .src_color_blend_factor = .one,
            .dst_color_blend_factor = .zero,
            .color_blend_op = .add,
            .src_alpha_blend_factor = .one,
            .dst_alpha_blend_factor = .zero,
            .alpha_blend_op = .add,
            .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
        }};

        const color_blending = vk.PipelineColorBlendStateCreateInfo{
            .flags = .{},
            .logic_op_enable = vk.FALSE,
            .logic_op = .copy,
            .attachment_count = color_blend_attachment.len,
            .p_attachments = &color_blend_attachment,
            .blend_constants = [_]f32{ 0, 0, 0, 0 },
        };
        const dynamic_states = [_]vk.DynamicState{ .viewport, .scissor };

        const dynamic_state = vk.PipelineDynamicStateCreateInfo{
            .flags = .{},
            .dynamic_state_count = dynamic_states.len,
            .p_dynamic_states = &dynamic_states,
        };

        self.pipeline_layout = try self.device.createPipelineLayout(&.{
            .flags = .{},
            .set_layout_count = 0,
            .p_set_layouts = undefined,
            .push_constant_range_count = 0,
            .p_push_constant_ranges = undefined,
        }, null);

        const pipeline_info = [_]vk.GraphicsPipelineCreateInfo{.{
            .flags = .{},
            .stage_count = shader_stages.len,
            .p_stages = &shader_stages,
            .p_vertex_input_state = &vertex_input_info,
            .p_input_assembly_state = &input_assembly,
            .p_tessellation_state = null,
            .p_viewport_state = &viewport_state,
            .p_rasterization_state = &rasterizer,
            .p_multisample_state = &multisampling,
            .p_depth_stencil_state = null,
            .p_color_blend_state = &color_blending,
            .p_dynamic_state = &dynamic_state,
            .layout = self.pipeline_layout,
            .render_pass = self.render_pass,
            .subpass = 0,
            .base_pipeline_handle = .null_handle,
            .base_pipeline_index = -1,
        }};

        _ = try self.device.createGraphicsPipelines(
            .null_handle,
            pipeline_info.len,
            &pipeline_info,
            null,
            @ptrCast(&self.graphics_pipeline),
        );
    }

    fn createFramebuffers(self: *Self) !void {
        self.swap_chain_framebuffers = try self.allocator.alloc(vk.Framebuffer, self.swap_chain_image_views.?.len);

        for (self.swap_chain_framebuffers.?, 0..) |*framebuffer, i| {
            const attachments = [_]vk.ImageView{self.swap_chain_image_views.?[i]};

            framebuffer.* = try self.device.createFramebuffer(&.{
                .flags = .{},
                .render_pass = self.render_pass,
                .attachment_count = attachments.len,
                .p_attachments = &attachments,
                .width = self.swap_chain_extent.width,
                .height = self.swap_chain_extent.height,
                .layers = 1,
            }, null);
        }
    }

    fn createCommandPool(self: *Self) !void {
        const queue_family_indices = try self.findQueueFamilies(self.physical_device);

        self.command_pool = try self.device.createCommandPool(&.{
            .flags = .{ .reset_command_buffer_bit = true },
            .queue_family_index = queue_family_indices.graphics_family.?,
        }, null);
    }

    fn createVertexBuffer(self: *Self) !void {
        const buffer_size: vk.DeviceSize = @sizeOf(@TypeOf(vertices));

        var staging_buffer: vk.Buffer = undefined;
        var staging_buffer_memory: vk.DeviceMemory = undefined;
        try createBuffer(self, buffer_size, .{ .transfer_src_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true }, &staging_buffer, &staging_buffer_memory);

        const data = try self.device.mapMemory(staging_buffer_memory, 0, buffer_size, .{});
        std.mem.copyForwards(u8, @as([*]u8, @ptrCast(data.?))[0..buffer_size], std.mem.sliceAsBytes(&vertices));
        self.device.unmapMemory(staging_buffer_memory);

        try createBuffer(self, buffer_size, .{ .transfer_dst_bit = true, .vertex_buffer_bit = true }, .{ .device_local_bit = true }, &self.vertex_buffer, &self.vertex_buffer_memory);

        try copyBuffer(self, staging_buffer, self.vertex_buffer, buffer_size);

        self.device.destroyBuffer(staging_buffer, null);
        self.device.freeMemory(staging_buffer_memory, null);
    }

    fn createIndexBuffer(self: *Self) !void {
        const buffer_size: vk.DeviceSize = @sizeOf(@TypeOf(indices_input));

        var staging_buffer: vk.Buffer = undefined;
        var staging_buffer_memory: vk.DeviceMemory = undefined;
        try createBuffer(self, buffer_size, .{ .transfer_src_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true }, &staging_buffer, &staging_buffer_memory);

        const data = try self.device.mapMemory(staging_buffer_memory, 0, buffer_size, .{});
        std.mem.copyForwards(u8, @as([*]u8, @ptrCast(data.?))[0..buffer_size], std.mem.sliceAsBytes(&indices_input));
        self.device.unmapMemory(staging_buffer_memory);

        try createBuffer(self, buffer_size, .{ .transfer_dst_bit = true, .index_buffer_bit = true }, .{ .device_local_bit = true }, &self.index_buffer, &self.index_buffer_memory);

        try copyBuffer(self, staging_buffer, self.index_buffer, buffer_size);

        self.device.destroyBuffer(staging_buffer, null);
        self.device.freeMemory(staging_buffer_memory, null);
    }

    fn createBuffer(self: *Self, size: vk.DeviceSize, usage: vk.BufferUsageFlags, properties: vk.MemoryPropertyFlags, buffer: *vk.Buffer, buffer_memory: *vk.DeviceMemory) !void {
        buffer.* = try self.device.createBuffer(&.{
            .flags = .{},
            .size = size,
            .usage = usage,
            .sharing_mode = .exclusive,
            .queue_family_index_count = 0,
            .p_queue_family_indices = undefined,
        }, null);

        const mem_requirements = self.device.getBufferMemoryRequirements(buffer.*);

        buffer_memory.* = try self.device.allocateMemory(&.{
            .allocation_size = mem_requirements.size,
            .memory_type_index = try self.findMemoryType(mem_requirements.memory_type_bits, properties),
        }, null);
        try self.device.bindBufferMemory(buffer.*, buffer_memory.*, 0);
    }

    fn copyBuffer(self: *Self, src_buffer: vk.Buffer, dst_buffer: vk.Buffer, size: vk.DeviceSize) !void {
        const alloc_info = vk.CommandBufferAllocateInfo{
            .level = .primary,
            .command_pool = self.command_pool,
            .command_buffer_count = 1,
        };

        var command_buffer: vk.CommandBuffer = undefined;
        try self.device.allocateCommandBuffers(&alloc_info, @ptrCast(&command_buffer));

        const begin_info = vk.CommandBufferBeginInfo{
            .flags = .{ .one_time_submit_bit = true },
            .p_inheritance_info = null,
        };

        try self.device.beginCommandBuffer(command_buffer, &begin_info);

        const copy_region = [_]vk.BufferCopy{.{
            .src_offset = 0,
            .dst_offset = 0,
            .size = size,
        }};
        self.device.cmdCopyBuffer(command_buffer, src_buffer, dst_buffer, 1, &copy_region);

        try self.device.endCommandBuffer(command_buffer);

        const submit_infos = [_]vk.SubmitInfo{.{
            .wait_semaphore_count = 0,
            .p_wait_semaphores = undefined,
            .p_wait_dst_stage_mask = undefined,
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast(&command_buffer),
            .signal_semaphore_count = 0,
            .p_signal_semaphores = undefined,
        }};
        try self.device.queueSubmit(self.graphics_queue, submit_infos.len, &submit_infos, .null_handle);
        try self.device.queueWaitIdle(self.graphics_queue);

        self.device.freeCommandBuffers(self.command_pool, 1, @ptrCast(&command_buffer));
    }

    fn findMemoryType(self: *Self, type_filter: u32, properties: vk.MemoryPropertyFlags) !u32 {
        const mem_properties = self.vki.getPhysicalDeviceMemoryProperties(self.physical_device);
        for (mem_properties.memory_types[0..mem_properties.memory_type_count], 0..) |mem_type, i| {
            if (type_filter & (@as(u32, 1) << @truncate(i)) != 0 and mem_type.property_flags.contains(properties)) {
                return @truncate(i);
            }
        }

        return error.NoSuitableMemoryType;
    }

    fn createCommandBuffers(self: *Self) !void {
        self.command_buffers = try self.allocator.alloc(vk.CommandBuffer, MAX_FRAMES_IN_FLIGHT);

        try self.device.allocateCommandBuffers(&.{
            .command_pool = self.command_pool,
            .level = .primary,
            .command_buffer_count = @intCast(self.command_buffers.?.len),
        }, self.command_buffers.?.ptr);
    }

    fn recordCommandBuffer(self: *Self, command_buffer: vk.CommandBuffer, image_index: u32) !void {
        try self.device.beginCommandBuffer(command_buffer, &.{
            .flags = .{},
            .p_inheritance_info = null,
        });

        const clear_values = [_]vk.ClearValue{.{
            .color = .{ .float_32 = .{ 0, 0, 0, 1 } },
        }};

        const render_pass_info = vk.RenderPassBeginInfo{
            .render_pass = self.render_pass,
            .framebuffer = self.swap_chain_framebuffers.?[image_index],
            .render_area = vk.Rect2D{
                .offset = .{ .x = 0, .y = 0 },
                .extent = self.swap_chain_extent,
            },
            .clear_value_count = clear_values.len,
            .p_clear_values = &clear_values,
        };

        self.device.cmdBeginRenderPass(command_buffer, &render_pass_info, .@"inline");
        {
            self.device.cmdBindPipeline(command_buffer, .graphics, self.graphics_pipeline);

            const viewports = [_]vk.Viewport{.{
                .x = 0,
                .y = 0,
                .width = @as(f32, @floatFromInt(self.swap_chain_extent.width)),
                .height = @as(f32, @floatFromInt(self.swap_chain_extent.height)),
                .min_depth = 0,
                .max_depth = 1,
            }};
            self.device.cmdSetViewport(command_buffer, 0, viewports.len, &viewports);

            const scissors = [_]vk.Rect2D{.{
                .offset = .{ .x = 0, .y = 0 },
                .extent = self.swap_chain_extent,
            }};
            self.device.cmdSetScissor(command_buffer, 0, scissors.len, &scissors);

            const vertex_buffers = [_]vk.Buffer{self.vertex_buffer};
            const offsets = [_]vk.DeviceSize{0};
            self.device.cmdBindVertexBuffers(command_buffer, 0, 1, &vertex_buffers, &offsets);

            self.device.cmdBindIndexBuffer(command_buffer, self.index_buffer, 0, vk.IndexType.uint16);

            self.device.cmdDrawIndexed(command_buffer, indices_input.len, 1, 0, 0, 0);
        }
        self.device.cmdEndRenderPass(command_buffer);

        try self.device.endCommandBuffer(command_buffer);
    }

    fn createSyncObjects(self: *Self) !void {
        self.image_available_semaphores = try self.allocator.alloc(vk.Semaphore, MAX_FRAMES_IN_FLIGHT);
        self.render_finished_semaphores = try self.allocator.alloc(vk.Semaphore, MAX_FRAMES_IN_FLIGHT);
        self.in_flight_fences = try self.allocator.alloc(vk.Fence, MAX_FRAMES_IN_FLIGHT);

        var i: usize = 0;
        while (i < MAX_FRAMES_IN_FLIGHT) : (i += 1) {
            self.image_available_semaphores.?[i] = try self.device.createSemaphore(&.{ .flags = .{} }, null);
            self.render_finished_semaphores.?[i] = try self.device.createSemaphore(&.{ .flags = .{} }, null);
            self.in_flight_fences.?[i] = try self.device.createFence(&.{ .flags = .{ .signaled_bit = true } }, null);
        }
    }

    fn drawFrame(self: *Self) !void {
        _ = try self.device.waitForFences(1, @ptrCast(&self.in_flight_fences.?[self.current_frame]), vk.TRUE, std.math.maxInt(u64));

        const result = self.device.acquireNextImageKHR(self.swap_chain, std.math.maxInt(u64), self.image_available_semaphores.?[self.current_frame], .null_handle) catch |err| switch (err) {
            error.OutOfDateKHR => {
                try self.recreateSwapChain();
                return;
            },
            else => |e| return e,
        };

        if (result.result != .success and result.result != .suboptimal_khr) {
            return error.ImageAcquireFailed;
        }

        try self.device.resetFences(1, @ptrCast(&self.in_flight_fences.?[self.current_frame]));

        try self.device.resetCommandBuffer(self.command_buffers.?[self.current_frame], .{});
        try self.recordCommandBuffer(self.command_buffers.?[self.current_frame], result.image_index);

        const wait_semaphores = [_]vk.Semaphore{self.image_available_semaphores.?[self.current_frame]};
        const wait_stages = [_]vk.PipelineStageFlags{.{ .color_attachment_output_bit = true }};
        const signal_semaphores = [_]vk.Semaphore{self.render_finished_semaphores.?[self.current_frame]};

        const submit_info = vk.SubmitInfo{
            .wait_semaphore_count = wait_semaphores.len,
            .p_wait_semaphores = &wait_semaphores,
            .p_wait_dst_stage_mask = &wait_stages,
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast(&self.command_buffers.?[self.current_frame]),
            .signal_semaphore_count = signal_semaphores.len,
            .p_signal_semaphores = &signal_semaphores,
        };
        _ = try self.device.queueSubmit(self.graphics_queue, 1, &[_]vk.SubmitInfo{submit_info}, self.in_flight_fences.?[self.current_frame]);

        const present_result = self.device.queuePresentKHR(self.present_queue, &.{
            .wait_semaphore_count = signal_semaphores.len,
            .p_wait_semaphores = @ptrCast(&signal_semaphores),
            .swapchain_count = 1,
            .p_swapchains = @ptrCast(&self.swap_chain),
            .p_image_indices = @ptrCast(&result.image_index),
            .p_results = null,
        }) catch |err| switch (err) {
            error.OutOfDateKHR => vk.Result.error_out_of_date_khr,
            else => return err,
        };

        if (present_result == .error_out_of_date_khr or present_result == .suboptimal_khr or self.framebuffer_resized) {
            self.framebuffer_resized = false;
            try self.recreateSwapChain();
        } else if (present_result != .success) {
            return error.ImagePresentFailed;
        }

        self.current_frame = (self.current_frame + 1) % MAX_FRAMES_IN_FLIGHT;
    }

    fn chooseSwapSurfaceFormat(available_formats: []vk.SurfaceFormatKHR) vk.SurfaceFormatKHR {
        for (available_formats) |available_format| {
            if (available_format.format == .b8g8r8a8_srgb and available_format.color_space == .srgb_nonlinear_khr) {
                return available_format;
            }
        }

        return available_formats[0];
    }

    fn chooseSwapPresentMode(available_present_modes: []vk.PresentModeKHR) vk.PresentModeKHR {
        for (available_present_modes) |available_present_mode| {
            if (available_present_mode == .mailbox_khr) {
                return available_present_mode;
            }
        }

        return .fifo_khr;
    }

    fn chooseSwapExtent(self: *Self, capabilities: vk.SurfaceCapabilitiesKHR) !vk.Extent2D {
        if (capabilities.current_extent.width != 0xFFFF_FFFF) {
            return capabilities.current_extent;
        } else {
            var window_width: u32 = undefined;
            var window_height: u32 = undefined;
            c.glfwGetFramebufferSize(self.window.?, @ptrCast(&window_width), @ptrCast(&window_height));

            return vk.Extent2D{
                .width = std.math.clamp(window_width, capabilities.min_image_extent.width, capabilities.max_image_extent.width),
                .height = std.math.clamp(window_height, capabilities.min_image_extent.height, capabilities.max_image_extent.height),
            };
        }
    }

    fn querySwapChainSupport(self: *Self, device: vk.PhysicalDevice) !SwapChainSupportDetails {
        var details = SwapChainSupportDetails.init(self.allocator);

        details.capabilities = try self.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(device, self.surface);

        details.formats = try self.instance.getPhysicalDeviceSurfaceFormatsAllocKHR(device, self.surface, details.allocator);

        details.present_modes = try self.instance.getPhysicalDeviceSurfacePresentModesAllocKHR(device, self.surface, details.allocator);

        return details;
    }

    fn isDeviceSuitable(self: *Self, device: vk.PhysicalDevice) !bool {
        const indices = try self.findQueueFamilies(device);

        const extensions_supported = try self.checkDeviceExtensionSupport(device);

        var swap_chain_adequate = false;
        if (extensions_supported) {
            const swap_chain_support = try self.querySwapChainSupport(device);
            defer swap_chain_support.deinit();

            swap_chain_adequate = swap_chain_support.formats != null and swap_chain_support.present_modes != null;
        }

        return indices.isComplete() and extensions_supported and swap_chain_adequate;
    }

    fn checkDeviceExtensionSupport(self: *Self, device: vk.PhysicalDevice) !bool {
        const available_extensions = try self.instance.enumerateDeviceExtensionPropertiesAlloc(device, null, self.allocator);
        defer self.allocator.free(available_extensions);

        const required_extensions = device_extensions[0..];

        for (required_extensions) |required_extension| {
            for (available_extensions) |available_extension| {
                const len = std.mem.indexOfScalar(u8, &available_extension.extension_name, 0).?;
                const available_extension_name = available_extension.extension_name[0..len];
                if (std.mem.eql(u8, std.mem.span(required_extension), available_extension_name)) {
                    break;
                }
            } else {
                return false;
            }
        }

        return true;
    }

    fn findQueueFamilies(self: *Self, device: vk.PhysicalDevice) !QueueFamilyIndices {
        var indices: QueueFamilyIndices = .{};

        const queue_families = try self.instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(device, self.allocator);
        defer self.allocator.free(queue_families);

        for (queue_families, 0..) |queue_family, i| {
            if (indices.graphics_family == null and queue_family.queue_flags.graphics_bit) {
                indices.graphics_family = @intCast(i);
            } else if (indices.present_family == null and (try self.instance.getPhysicalDeviceSurfaceSupportKHR(device, @intCast(i), self.surface)) == vk.TRUE) {
                indices.present_family = @intCast(i);
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
