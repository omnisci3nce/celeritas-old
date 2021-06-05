#version 330 core
out vec4 FragColor;

// inputs from vertex shader
in vec3 FragPos;
in vec3 Normal;

void main()
{    
    FragColor = vec4(vec3(gl_FragCoord.z), 1.0);
}