#version 300 es
precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;
// CRT: faint scanlines and a slight vignette -- a nod to a tube, not a
// simulation of one. No curvature, no chromatic fringing, no flicker: those
// move or blur text, and this has to stay readable for hours. An ordinary
// optional filter (display panel, SUPER+SHIFT+F); no theme forces it, a theme
// may only suggest it (crt_suggest in ~/.config/themes/<name>/theme.conf).
//
// Scanlines: every SCAN_PERIOD output pixels, a cosine dip of SCAN_DEPTH. A
// cosine rather than a hard dark row, so the lines do not alias into a moire
// over text. gl_FragCoord is in framebuffer pixels, so the period is the same
// on every monitor whatever its scale.
// Vignette: the corners lose at most VIGNETTE (radial, from the centre).
// Both are multipliers, so they only ever DARKEN -- nothing on the HDR panel
// gets brighter than it already was.
const float SCAN_PERIOD = 3.0;
const float SCAN_DEPTH  = 0.10;
const float VIGNETTE    = 0.12;
void main() {
    vec4 c = texture(tex, v_texcoord);
    float scan = 1.0 - SCAN_DEPTH * (0.5 + 0.5 * cos(gl_FragCoord.y * 6.2831853 / SCAN_PERIOD));
    vec2 d = v_texcoord - 0.5;
    float vig = 1.0 - VIGNETTE * 2.0 * dot(d, d);     // dot(d, d) is 0.5 in a corner
    fragColor = vec4(c.rgb * scan * vig, c.a);
}
