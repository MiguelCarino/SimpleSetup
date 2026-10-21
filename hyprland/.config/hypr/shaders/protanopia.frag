#version 300 es
precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;
// Protanopia (no red cones) correction.
// Daltonization (Fidaner et al.): simulate what this kind of colour vision
// loses, then shift that lost difference into the channels it can still see,
// so colours that would collapse into one stay apart. It corrects, it does not
// simulate -- the screen will look slightly off to normal colour vision.
const mat3 RGB2LMS = mat3(17.8824, 3.45565, 0.0299566,
                          43.5161, 27.1554, 0.184309,
                          4.11935, 3.86714, 1.46709);
const mat3 LMS2RGB = mat3(0.0809444479, -0.0102485335, -0.000365296938,
                          -0.130504409, 0.0540193266, -0.00412161469,
                          0.116721066, -0.113614708, 0.693511405);
const mat3 SIM = mat3(0.0, 0.0, 0.0,  2.02344, 1.0, 0.0,  -2.52581, 0.0, 1.0);
const mat3 SHIFT = mat3(0.0, 0.7, 0.7,
                        0.0, 1.0, 0.0,
                        0.0, 0.0, 1.0);
void main() {
    vec4 c = texture(tex, v_texcoord);
    vec3 sim = LMS2RGB * (SIM * (RGB2LMS * c.rgb));
    vec3 rgb = c.rgb + SHIFT * (c.rgb - sim);
    fragColor = vec4(clamp(rgb, 0.0, 1.0), c.a);
}
