pub usingnamespace @cImport({
    @cInclude("epoxy/gl.h");
    @cInclude("GLFW/glfw3.h");
    @cDefine("STBI_NO_STDIO", "");
    @cInclude("stb_image.h");
    // TODO: @cInclude("./unused/model_loader.h");
});