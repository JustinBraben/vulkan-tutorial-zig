// src/resources.zig
// This module exports all compiled shader SPIR-V bytecode

pub const shaders = struct {
    // Lesson 09 shaders
    pub const vert_09 = @embedFile("vert_09");
    pub const frag_09 = @embedFile("frag_09");
    
    // Lesson 18 shaders
    pub const vert_18 = @embedFile("vert_18");
    pub const frag_18 = @embedFile("frag_18");
    
    // Lesson 22 shaders
    pub const vert_22 = @embedFile("vert_22");
    pub const frag_22 = @embedFile("frag_22");
    
    // Lesson 26 shaders
    pub const vert_26 = @embedFile("vert_26");
    pub const frag_26 = @embedFile("frag_26");
    
    // Lesson 27 shaders
    pub const vert_27 = @embedFile("vert_27");
    pub const frag_27 = @embedFile("frag_27");
};