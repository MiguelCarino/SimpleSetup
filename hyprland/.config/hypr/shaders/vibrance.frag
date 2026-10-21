#version 300 es
precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;
// Vibrance: boost saturation, more for colours that are dull than for those
// that are already saturated, so skin tones and the neon UI do not clip.
void main() {
    vec4 c = texture(tex, v_texcoord);
    float mx = max(c.r, max(c.g, c.b));
    float mn = min(c.r, min(c.g, c.b));
    float sat = mx - mn;
    float y = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
    float amount = 0.45 * (1.0 - sat);
    vec3 rgb = mix(vec3(y), c.rgb, 1.0 + amount);
    fragColor = vec4(clamp(rgb, 0.0, 1.0), c.a);
}
