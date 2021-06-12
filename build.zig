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
    exe.addIncludeDir("C:/ProgramData/chocolatey/lib/glfw3/tools/glfw-3.0.4.bin.WIN64/include");
    exe.addLibPath("C:/ProgramData/chocolatey/lib/glfw3/tools/glfw-3.0.4.bin.WIN64/lib-msvc120");

    exe.linkSystemLibrary("c");
    // exe.addFrameworkDir("/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks");
    // exe.linkFramework("OpenGL");
    exe.linkSystemLibrary("glfw3");
    
    exe.addIncludeDir("C:/include");
    exe.linkSystemLibrary("epoxy");
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
