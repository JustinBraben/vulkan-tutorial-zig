const std = @import("std");

const vkgen = @import("vulkan_zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const vulkan_headers = b.dependency("vulkan_headers", .{
        .target = target,
        .optimize = optimize,
    });
    const registry = vulkan_headers.path("registry/vk.xml");

    const vulkan_zig = b.dependency("vulkan_zig", .{
        .registry = registry,
    });

    const c_module = b.addModule("c", .{
        .root_source_file = b.path("libs/c.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    c_module.addImport("vulkan", vulkan_zig.module("vulkan-zig"));
    c_module.addIncludePath(b.path("libs"));
    c_module.addCSourceFile(.{
        .file = b.path("libs/stb/stb_image.c"),
        .flags = &.{"-std=c99", "-g"},
    });

    const glfw = b.dependency("glfw", .{
        .target = target,
        .optimize = optimize,
    });
    c_module.linkLibrary(glfw.artifact("glfw"));

    const zalgebra = b.dependency("zalgebra", .{});

    const resources_module = b.createModule(.{
        .root_source_file = b.path("src/resources.zig"),
        .target = target,
        .optimize = optimize,
    });
    addShader(b, resources_module, "vert_09", "src/09_shader_base.vert");
    addShader(b, resources_module, "frag_09", "src/09_shader_base.frag");
    addShader(b, resources_module, "vert_18", "src/18_shader_vertexbuffer.vert");
    addShader(b, resources_module, "frag_18", "src/18_shader_vertexbuffer.frag");
    addShader(b, resources_module, "vert_22", "src/22_shader_ubo.vert");
    addShader(b, resources_module, "frag_22", "src/22_shader_ubo.frag");
    addShader(b, resources_module, "vert_26", "src/26_shader_textures.vert");
    addShader(b, resources_module, "frag_26", "src/26_shader_textures.frag");
    addShader(b, resources_module, "vert_27", "src/27_shader_depth.vert");
    addShader(b, resources_module, "frag_27", "src/27_shader_depth.frag");

    const lessons_step = b.step("lessons", "Build all lessons");
    for (lessons) |lesson_name| {
        const lesson_exe_mod = b.createModule(.{
            .root_source_file = b.path(b.fmt("src/{s}.zig", .{ lesson_name })),
            .target = target,
            .optimize = optimize,
        });

        lesson_exe_mod.addImport("vulkan", vulkan_zig.module("vulkan-zig"));
        lesson_exe_mod.addImport("c", c_module);
        lesson_exe_mod.addImport("zalgebra", zalgebra.module("zalgebra"));
        lesson_exe_mod.addImport("resources", resources_module);

        const lesson_exe = b.addExecutable(.{
            .name = lesson_name,
            .root_module = lesson_exe_mod,
        });

        const compile_step = b.step(lesson_name, b.fmt("Build {s}", .{lesson_name}));
        compile_step.dependOn(&b.addInstallArtifact(lesson_exe, .{}).step);
        b.getInstallStep().dependOn(compile_step);

        const run_cmd = b.addRunArtifact(lesson_exe);
        run_cmd.step.dependOn(compile_step);

        const run_step = b.step(b.fmt("run-{s}", .{lesson_name}), b.fmt("Run {s}", .{lesson_name}));
        run_step.dependOn(&run_cmd.step);
    }

    // Create "all" step
    const all_step = b.step("all", "Build everything and runs all tests");
    all_step.dependOn(lessons_step);

    b.default_step.dependOn(all_step);
}

const lessons = [_][]const u8{
    "00_base_code",
    "01_instance_creation",
    "02_validation_layers",
    "03_physical_device_selection",
    "04_logical_device",
    "05_window_surface",
    "06_swap_chain_creation",
    "07_image_views",
    "08_graphics_pipeline",
    "09_shader_module",
    "10_fixed_functions",
    "11_render_passes",
    "12_graphics_pipeline_complete",
    "13_framebuffers",
    "14_command_buffers",
    "15_hello_triangle",
    "16_frames_in_flight",
    "17_swap_chain_recreation",
    "18_vertex_input",
    "19_vertex_buffer",
    "20_staging_buffer",
    "21_index_buffer",
    "22_descriptor_layout",
    "23_descriptor_sets",
    "24_texture_image",
    "25_sampler",
    // "26_texture_mapping",
    // "27_depth_buffering",
    // "28_model_loading",
    // "29_mipmapping",
    // "30_multisampling",
};

fn addShader(
    b: *std.Build,
    module: *std.Build.Module,
    shader_name: []const u8,
    shader_path: []const u8,
) void {
    const shader_cmd = b.addSystemCommand(&.{
        "glslc",
        "--target-env=vulkan1.2",
        "-o",
    });
    const shader_spv = shader_cmd.addOutputFileArg(shader_name);
    shader_cmd.addFileArg(b.path(shader_path));
    module.addAnonymousImport(b.fmt("{s}", .{shader_name}), .{
        .root_source_file = shader_spv,
    });
}