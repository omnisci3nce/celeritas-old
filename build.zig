const Builder = @import("std").build.Builder;
const builtin = @import("builtin");

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    // const windows = b.option(bool, "windows", "create windows build") orelse false;

    var exe = b.addExecutable("tetris", "src/main.zig");
    // exe.addCSourceFile("stb_image-2.22/stb_image_impl.c", &[_][]const u8{"-std=c99"});
    exe.setBuildMode(mode);

    // if (windows) {
        // exe.setTarget(.{
            // .cpu_arch = .x86_64,
            // .os_tag = .windows,
            // .abi = .gnu,
        // });
    // }

    // exe.addIncludeDir("stb_image-2.22");

    exe.addIncludeDir("/usr/local/include");
    exe.addIncludeDir("/usr/local/lib");
    exe.addIncludeDir("/opt/homebrew/include");
    exe.addFrameworkDir("/opt/homebrew/include");
    exe.addIncludeDir("/opt/homebrew/lib");
    exe.addIncludeDir("/opt/homebrew/include/GLFW");
    exe.addFrameworkDir("/opt/homebrew/lib");
    exe.addFrameworkDir("/usr/local/lib");
    exe.linkSystemLibrary("c");
    exe.addFrameworkDir("/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks");
            exe.linkFramework("OpenGL");
    exe.linkSystemLibrary("glfw");
    exe.linkSystemLibrary("epoxy");
    exe.install();

    const play = b.step("play", "Play the game");
    const run = exe.run();
    run.step.dependOn(b.getInstallStep());
    play.dependOn(&run.step);
}
