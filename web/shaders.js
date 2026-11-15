// GLSL ES 3.00 (WebGL2) ports of the nine Metal fragment shaders in ../main.swift.
// The math, constants and palette are copied line for line. The only changes are
// syntax: float2 -> vec2, atan2 -> atan, fmod -> mod (all arguments are >= 0, so
// the result is the same), round(x) -> floor(x + 0.5) for x >= -0.5, and the
// reversed smoothstep in vignette() written as 1 - smoothstep(lo, hi, x), which
// is the same curve but defined behaviour in GLSL.

export const VERTEX = `#version 300 es
out vec2 v_uv;
void main() {
    // Same full-screen triangle as vmain() in the Metal source.
    vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
    v_uv = p;
    gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}`;

const PRELUDE = `#version 300 es
precision highp float;
precision highp int;

in vec2 v_uv;
out vec4 outColor;

uniform float u_time;
uniform float u_aspect;
uniform float u_brightness;
uniform vec4  u_tint;
uniform vec2  u_res;

// ---- shared helpers --------------------------------------------------------
float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x),
               mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    const mat2 m = mat2(0.8, 0.6, -0.6, 0.8);
    for (int i = 0; i < 4; i++) { v += a * vnoise(p); p = m * p * 2.03 + 11.7; a *= 0.47; }
    return v;
}
vec2 rot(vec2 p, float a) {
    float c = cos(a), s = sin(a);
    return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}
// Anti-aliased line: d = distance from the line, w = half width, px = one pixel.
float stroke(float d, float w, float px) {
    return 1.0 - smoothstep(w, w + 1.5 * px, abs(d));
}
// Soft darkening toward the screen edges.
float vignette(vec2 uv, float amount) {
    float d = length((uv - 0.5) * vec2(1.25, 1.0)) * 1.6;
    return mix(1.0 - amount, 1.0, 1.0 - smoothstep(0.25, 1.55, d));
}
vec4 finish(float v, vec2 fragPos, float brightness, vec3 tint, float time) {
    vec3 col = v * brightness * tint;
    col += (hash(fragPos + fract(time)) - 0.5) / 255.0;   // dither out banding
    return vec4(max(col, 0.0), 1.0);
}
// Hexagon tiling (pointy-top, one unit wide). xy = position in the cell, zw = cell id.
vec4 hexCell(vec2 p) {
    const vec2 s = vec2(1.0, 1.7320508);
    vec4 c = floor(vec4(p, p - vec2(0.5, 1.0)) / vec4(s, s)) + 0.5;
    vec2 a = p - c.xy * s;
    vec2 b = p - (c.zw + 0.5) * s;
    return dot(a, a) < dot(b, b) ? vec4(a, c.xy) : vec4(b, c.zw + 0.5);
}
float hexDist(vec2 p) {            // 0 at the centre, 0.5 on the edge
    p = abs(p);
    return max(dot(p, vec2(0.5, 0.8660254)), p.x);
}

vec4 wallpaper(vec2 uv, vec2 fragPos);

void main() {
    // Metal's [[position]] has its origin at the top left; GL's is bottom left.
    vec2 fragPos = vec2(gl_FragCoord.x, u_res.y - gl_FragCoord.y);
    outColor = wallpaper(v_uv, fragPos);
}
`;

const BODIES = {
  // ---- 1. Silk: slow black-on-black swirls -----------------------------------
  silk: `
vec4 wallpaper(vec2 uv, vec2 fragPos) {
    vec2 p = (uv - 0.5) * vec2(u_aspect, 1.0) * 1.4;
    float t = u_time * 0.012;

    vec2 c1 = vec2(-0.55, 0.18) + 0.10 * vec2(sin(t * 0.9), cos(t * 0.7));
    vec2 c2 = vec2(0.70, -0.25) + 0.10 * vec2(cos(t * 0.6), sin(t * 0.8));
    vec2 c3 = vec2(0.15, 0.42) + 0.06 * vec2(sin(t * 1.1), cos(t * 0.5));
    p = c1 + rot(p - c1, 3.0 * exp(-1.5 * length(p - c1)) + t * 0.5);
    p = c2 + rot(p - c2, -2.2 * exp(-2.2 * length(p - c2)) - t * 0.4);
    p = c3 + rot(p - c3, 1.6 * exp(-5.0 * length(p - c3)));

    vec2 q = vec2(fbm(p + vec2(0.0, t)), fbm(p + vec2(5.2, 1.3 - t)));
    vec2 r = vec2(fbm(p + 2.2 * q + vec2(1.7 + t, 9.2)),
                  fbm(p + 2.2 * q + vec2(8.3, 2.8 - t)));
    float f = fbm(p * 0.7 + 2.4 * r);

    float band = f * 3.5 + length(r) * 1.4;
    float w = abs(fract(band) - 0.5) * 2.0;
    float fold = pow(1.0 - w, 2.2);
    float edge = pow(1.0 - w, 14.0);

    float light = smoothstep(0.25, 0.80, length(q));
    float v = 0.008 + 0.105 * fold * mix(0.62, 1.0, light) + 0.10 * edge * mix(0.50, 1.0, light)
            + 0.030 * smoothstep(0.35, 0.8, f);

    float w2 = abs(fract((q.x - q.y) * 2.4 + r.x * 1.6 + 0.37) - 0.5) * 2.0;
    float calm = 1.0 - 0.75 * fold;
    v += (0.060 * pow(1.0 - w2, 2.6) + 0.055 * pow(1.0 - w2, 14.0)) * calm;

    v = max(v - 0.012, 0.0) * 0.62;
    v *= vignette(uv, 0.20);
    return finish(v, fragPos, u_brightness, u_tint.rgb, u_time);
}`,

  // ---- 2. Rings: concentric rings, each carrying a slowly turning arc of light
  rings: `
vec4 wallpaper(vec2 uv, vec2 fragPos) {
    vec2 p = (uv - 0.5) * vec2(u_aspect, 1.0);
    float px = 1.0 / u_res.y;
    float r = length(p);
    float a = atan(p.y, p.x);

    const float first = 0.055, gap = 0.058;
    float idx = max(floor((r - first) / gap + 0.5), 0.0);
    float d = r - (first + idx * gap);

    float h1 = hash(vec2(idx, 3.1)), h2 = hash(vec2(idx, 7.7));
    float dir = mod(idx, 2.0) < 0.5 ? 1.0 : -1.0;
    float turn = u_time * 0.018 * dir * (0.35 + h1) + h2 * 6.2831853;
    float ang = fract((a + turn) / 6.2831853);
    float len = 0.16 + 0.42 * h1;
    float arc = ang < len ? pow(ang / len, 1.6) : 0.0;
    arc *= 1.0 - smoothstep(len - 0.003, len, ang);

    float v = stroke(d, 0.0011, px) * (0.050 + 0.26 * arc);
    v += 0.05 * arc * exp(-d * d / 0.00006);
    v *= vignette(uv, 0.45);
    return finish(v, fragPos, u_brightness, u_tint.rgb, u_time);
}`,

  // ---- 3. Dots: a grid of dots that swell as two slow waves pass through ------
  dots: `
vec4 wallpaper(vec2 uv, vec2 fragPos) {
    vec2 p = (uv - 0.5) * vec2(u_aspect, 1.0);
    float px = 1.0 / u_res.y;
    float t = u_time * 0.22;

    const float s = 0.036;
    vec2 id = floor(p / s) + 0.5;
    vec2 c = id * s;
    float w1 = sin(length(c - vec2(-0.55, -0.30)) * 8.0 - t * 0.6);
    float w2 = sin(dot(c, vec2(0.8, 0.6)) * 6.0 + t * 0.4);
    float w = smoothstep(-0.3, 1.0, 0.5 * (w1 + w2));

    float rad = s * (0.045 + 0.215 * w);
    float d = length(p - c);
    float v = (1.0 - smoothstep(rad - px, rad + px, d)) * (0.055 + 0.24 * w);
    v *= vignette(uv, 0.35);
    return finish(v, fragPos, u_brightness, u_tint.rgb, u_time);
}`,

  // ---- 4. Honeycomb: hexagon outlines, single cells glowing on and off --------
  honeycomb: `
vec4 wallpaper(vec2 uv, vec2 fragPos) {
    vec2 p = (uv - 0.5) * vec2(u_aspect, 1.0);
    float px = 1.0 / u_res.y;

    const float sc = 8.5;
    vec4 h = hexCell(p * sc);
    float ed = (0.5 - hexDist(h.xy)) / sc;
    float hs = hash(h.zw * 2.0 + 17.0);
    float pulse = pow(max(0.0, sin(u_time * 0.11 * (0.6 + 0.8 * hs) + hs * 6.2831853)), 7.0);
    float drift = vnoise(p * 1.4 + vec2(u_time * 0.012, 3.0));

    float line = stroke(ed, 0.0010, px);
    float inner = smoothstep(0.0085, 0.0085 + 1.5 * px, ed);
    float v = line * (0.055 + 0.05 * drift + 0.16 * pulse) + inner * (0.004 + 0.070 * pulse);
    v *= vignette(uv, 0.40);
    return finish(v, fragPos, u_brightness, u_tint.rgb, u_time);
}`,

  // ---- 5. Waves: stacked lines flowing like a ribbon --------------------------
  waves: `
vec4 wallpaper(vec2 uv, vec2 fragPos) {
    vec2 p = (uv - 0.5) * vec2(u_aspect, 1.0);
    float px = 1.0 / u_res.y;
    float t = u_time * 0.10;

    float env = 0.35 + 0.65 * exp(-p.x * p.x * 2.2);
    float v = 0.0;
    for (int i = 0; i < 30; i++) {
        float fi = float(i);
        float ph = fi * 0.21;
        float a1 = p.x * 4.6 + ph + t, a2 = p.x * 10.0 - ph * 1.7 - t * 1.3;
        float y = -0.44 + fi * (0.88 / 29.0) + env * (0.048 * sin(a1) + 0.020 * sin(a2));
        float slope = env * (0.048 * 4.6 * cos(a1) + 0.020 * 10.0 * cos(a2));
        float d = (p.y - y) / sqrt(1.0 + slope * slope);
        float b = 0.050 + 0.19 * pow(0.5 + 0.5 * sin(ph * 1.3 + p.x * 2.0 - t * 0.7), 2.0);
        v = max(v, stroke(d, 0.0010, px) * b);
    }
    v *= vignette(uv, 0.45);
    return finish(v, fragPos, u_brightness, u_tint.rgb, u_time);
}`,

  // ---- 6. Facets: a field of triangles, each catching the light in turn -------
  facets: `
vec4 wallpaper(vec2 uv, vec2 fragPos) {
    vec2 p = (uv - 0.5) * vec2(u_aspect, 1.0);
    float px = 1.0 / u_res.y;

    const float s = 0.105;
    vec2 g = vec2(p.x - p.y * 0.5773503, p.y * 1.1547005) / s;
    vec2 id = floor(g), f = fract(g);
    float up = step(1.0, f.x + f.y);
    float d = (up > 0.5 ? min(min(1.0 - f.x, 1.0 - f.y), f.x + f.y - 1.0)
                        : min(min(f.x, f.y), 1.0 - f.x - f.y)) * 0.8660254 * s;

    float h = hash(id * 2.0 + vec2(up * 7.0 + 3.0, up * 13.0));
    float tw = 0.5 + 0.5 * sin(u_time * 0.09 * (0.5 + h) + h * 40.0);
    float big = vnoise(p * 1.25 + vec2(u_time * 0.010, 0.0));
    float shade = 0.012 + 0.085 * tw * tw * smoothstep(0.25, 0.95, big + 0.40 * h);

    float v = shade * smoothstep(0.0009, 0.0009 + 1.5 * px, d);
    v *= vignette(uv, 0.30);
    return finish(v, fragPos, u_brightness, u_tint.rgb, u_time);
}`,

  // ---- 7. Orbits: tilted ellipses with small bodies travelling along them -----
  orbits: `
vec4 wallpaper(vec2 uv, vec2 fragPos) {
    vec2 p = (uv - 0.5) * vec2(u_aspect, 1.0);
    float px = 1.0 / u_res.y;
    const float tilt = 0.30, squash = 0.40;

    vec2 q = rot(p, -tilt);
    q.y /= squash;
    float r = length(q);
    float fw = max(fwidth(r), 1e-5);

    float v = 0.0;
    for (int i = 0; i < 7; i++) {
        float fi = float(i);
        float R = 0.17 + 0.125 * fi;
        v = max(v, (1.0 - smoothstep(0.7, 2.2, abs(r - R) / fw)) * 0.075);

        float th = u_time * 0.045 * (1.7 / (1.0 + 0.8 * fi)) + fi * 2.4;
        vec2 body = rot(vec2(R * cos(th), R * sin(th) * squash), tilt);
        float d = length(p - body);
        float size = 0.0045 + 0.0015 * mod(fi * 3.0, 4.0);
        v += (1.0 - smoothstep(size - px, size + px, d)) * 0.50 + 0.10 * exp(-d * d / 0.0006);
    }
    float d0 = length(p);
    v += (1.0 - smoothstep(0.020 - px, 0.020 + px, d0)) * 0.26 + 0.11 * exp(-d0 * d0 / 0.006);
    v *= vignette(uv, 0.35);
    return finish(v, fragPos, u_brightness, u_tint.rgb, u_time);
}`,

  // ---- 8. Tunnel: nested squares, slowly twisting, light pulsing inward -------
  tunnel: `
vec4 wallpaper(vec2 uv, vec2 fragPos) {
    vec2 p = (uv - 0.5) * vec2(u_aspect, 1.0);
    float px = 1.0 / u_res.y;
    float twist = 0.060 + 0.030 * sin(u_time * 0.028);

    float v = 0.0;
    for (int i = 0; i < 34; i++) {
        float fi = float(i);
        float s = 1.30 * pow(0.875, fi);
        vec2 q = abs(rot(p, fi * twist + u_time * 0.008));
        float d = max(q.x, q.y) - s;
        float b = 0.045 + 0.17 * pow(0.5 + 0.5 * sin(fi * 0.55 - u_time * 0.14), 2.0);
        v = max(v, stroke(d, 0.0010, px) * b);
    }
    v *= vignette(uv, 0.30);
    return finish(v, fragPos, u_brightness, u_tint.rgb, u_time);
}`,

  // ---- 9. Cubes: isometric columns of cubes slowly rising and sinking ---------
  cubes: `
float cubeHeight(vec2 cell, float t) {
    float h = hash(cell + 5.0);
    return 1.0 + 0.70 * sin(t * (0.6 + 0.8 * h) + h * 6.2831853);
}
vec4 wallpaper(vec2 uv, vec2 fragPos) {
    vec2 p = (uv - 0.5) * vec2(u_aspect, 1.0);
    const float sc = 10.5;
    float aa = 1.5 * sc / u_res.y;
    float t = u_time * 0.115;

    // Isometric view: follow this pixel's line of sight down through the grid
    // of columns, from above the tallest one, until it lands on a face.
    vec2 s = p * sc;
    const float z0 = 1.75;
    float sum = 2.0 * (z0 - s.y), dif = s.x / 0.8660254;
    vec3 pos = vec3(0.5 * (sum + dif), 0.5 * (sum - dif), z0);

    float shade = 0.0, ed = 1.0;
    int face = 0;
    for (int i = 0; i < 12; i++) {
        vec2 c = floor(pos.xy);
        float h = cubeHeight(c, t);
        vec2 f = pos.xy - c;
        if (face != 0 && pos.z <= h) {
            float along = face == 1 ? f.y : f.x;
            float depth = h - pos.z;
            ed = min(min(along, 1.0 - along), depth);
            shade = (face == 1 ? 0.066 : 0.026) * exp(-depth * 0.55);
            break;
        }
        float stp = min(f.x, f.y);
        if (pos.z - stp <= h) {
            vec2 q = f - (pos.z - h);
            ed = min(min(q.x, 1.0 - q.x), min(q.y, 1.0 - q.y));
            shade = 0.100 + 0.060 * (h - 0.3) / 1.4;
            break;
        }
        face = f.x < f.y ? 1 : 2;
        pos -= stp + 1e-4;
    }

    float sweep = vnoise(p * 1.2 + vec2(u_time * 0.014, 0.0));
    float v = shade * mix(0.50, 1.0, sweep) * smoothstep(0.012, 0.012 + aa, ed);
    v *= vignette(uv, 0.35);
    return finish(v, fragPos, u_brightness, u_tint.rgb, u_time);
}`,
};

// Same order and names as WALLPAPERS in main.swift.
export const WALLPAPERS = [
  { id: 'silk', name: 'Silk', blurb: 'Slow black-on-black swirls' },
  { id: 'rings', name: 'Rings', blurb: 'Concentric rings, each with a slowly turning arc of light' },
  { id: 'dots', name: 'Dots', blurb: 'A grid of dots that swell as two slow waves pass through' },
  { id: 'honeycomb', name: 'Honeycomb', blurb: 'Hexagon outlines, single cells glowing on and off' },
  { id: 'waves', name: 'Waves', blurb: 'Stacked lines flowing like a ribbon' },
  { id: 'facets', name: 'Facets', blurb: 'A field of triangles, each catching the light in turn' },
  { id: 'orbits', name: 'Orbits', blurb: 'Tilted ellipses with small bodies travelling along them' },
  { id: 'tunnel', name: 'Tunnel', blurb: 'Nested squares, slowly twisting, light pulsing inward' },
  { id: 'cubes', name: 'Cubes', blurb: 'Isometric columns of cubes slowly rising and sinking' },
];

export function fragmentSource(id) {
  return PRELUDE + BODIES[id];
}

// Look controls, same values as the top of main.swift.
export const SPEED = 2.3;
export const BRIGHTNESS = 1.0;
export const TINT = [0.90, 0.94, 1.00];
export const FPS = 30;
