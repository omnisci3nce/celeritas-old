#version 330 core
out vec4 FragColor;

// inputs from vertex shader
in vec3 FragPos;
in vec3 Normal;

void main()
{    
    FragColor = vec4(vec3(1.0), 1.0);
}