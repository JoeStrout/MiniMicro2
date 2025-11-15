#version 330

// Input vertex attributes (from vertex shader)
in vec2 fragTexCoord;
in vec4 fragColor;

// Input uniform values
uniform sampler2D texture0;
uniform vec4 colDiffuse;

// Custom uniforms
uniform vec4 foreColor;
uniform vec4 backColor;

// Output fragment color
out vec4 finalColor;

void main()
{
    // Sample the texture
    vec4 texelColor = texture(texture0, fragTexCoord);

    // Use the texture's alpha channel as a mask
	float mask = texelColor.a;

    // Switch (or interpolate) between background and foreground based on mask
    finalColor = mix(backColor, foreColor, mask);
}
