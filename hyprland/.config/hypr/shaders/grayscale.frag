#version 300 es
precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;
// Grayscale: Rec.709 luma. Useful for judging contrast and hierarchy in a
// design, or for making a screen boring enough to stop scrolling.
void main() {
    vec4 c = texture(tex, v_texcoord);
    float y = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
    fragColor = vec4(vec3(y), c.a);
}
