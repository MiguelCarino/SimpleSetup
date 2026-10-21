#version 300 es
precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;
// Reading: warm paper. Desaturates most of the way and tints towards a soft
// sepia, with the whites pulled down a little -- long pages of text on a white
// background stop glaring without the image turning orange like night light.
void main() {
    vec4 c = texture(tex, v_texcoord);
    float y = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
    vec3 paper = vec3(y) * vec3(1.00, 0.93, 0.80);
    vec3 rgb = mix(c.rgb, paper, 0.75) * 0.92;
    fragColor = vec4(rgb, c.a);
}
