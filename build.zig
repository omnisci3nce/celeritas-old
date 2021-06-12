const std = @import("std");
const Builder = @import("std").build.Builder;
const builtin = @import("builtin");

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    // const windows = b.option(bool, "windows", "create windows build") orelse false;

    var exe = b.addExecutable("celeritas_demo", "src/main.zig");
    exe.addCSourceFile("deps/stb_image-2.26/stb_image_impl.c", &[_][]const u8{"-std=c99"});
    exe.setBuildMode(mode);

    exe.addPackagePath("zlm", "deps/zlm/zlm.zig");
    exe.addIncludeDir("deps/stb_image-2.26");

    exe.addPackagePath("zalgebra", "deps/zalgebra/src/main.zig");
    exe.addIncludeDir("deps/zalgebra");
    exe.addIncludeDir("src");

    switch (std.Target.current.os.tag) {
        .macos => {
            exe.addFrameworkDir("/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks");
            exe.linkFramework("OpenGL");
            exe.linkSystemLibrary("glfw");
        },
        .windows => {
            exe.addIncludeDir("C:/ProgramData/chocolatey/lib/glfw3/tools/glfw-3.0.4.bin.WIN64/include");
            exe.addLibPath("C:/ProgramData/chocolatey/lib/glfw3/tools/glfw-3.0.4.bin.WIN64/lib-msvc120");
            exe.addSystemIncludeDir("C:/bin");
            exe.addSystemIncludeDir("C:/include");
            exe.addIncludeDir("C:/include/epoxy");
            exe.addLibPath("C:/lib");
            exe.linkSystemLibrary("glfw3");
            exe.linkSystemLibrary("opengl32");
            exe.linkSystemLibrary("user32");
            exe.linkSystemLibrary("gdi32");
            exe.linkSystemLibrary("shell32");
        },
        else => {
            @panic("don't know how to build on your system.");
        }
    }

    exe.linkSystemLibrary("epoxy");
    exe.linkSystemLibrary("c");
    
    exe.install();

    const play = b.step("play", "Play the game");
    const run = exe.run();
    run.step.dependOn(b.getInstallStep());
    play.dependOn(&run.step);

    var tests = b.addTest("src/loaders/obj.zig");
    tests.setBuildMode(mode);
    tests.linkSystemLibrary("c");
    tests.addPackagePath("zalgebra", "deps/zalgebra/src/main.zig");
    tests.addIncludeDir("deps/zalgebra");
    tests.addIncludeDir("src");

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&tests.step);
}
