import Cocoa
import MetalKit
import ServiceManagement

// Drift — a collection of near-black live wallpapers. Each one is a small Metal
// fragment shader, drawn at a low frame rate, paused whenever the desktop is
// covered, and drawn exactly once when "Animated" is switched off.

// ---- Look controls ---------------------------------------------------------
let SPEED: Float = 2.3        // 0.5 = half speed, 2 = double
let BRIGHTNESS: Float = 1.0   // 0.6 = dimmer, 1.5 = brighter
let TINT: (Float, Float, Float) = (0.90, 0.94, 1.00)  // colour of the highlights
let FPS = 30
// ----------------------------------------------------------------------------

/// Menu name and the fragment function that draws it.
let WALLPAPERS: [(name: String, function: String)] = [
    ("Silk", "f_silk"),
    ("Rings", "f_rings"),
    ("Dots", "f_dots"),
    ("Honeycomb", "f_honeycomb"),
    ("Waves", "f_waves"),
    ("Facets", "f_facets"),
    ("Orbits", "f_orbits"),
    ("Tunnel", "f_tunnel"),
    ("Cubes", "f_cubes"),
]

let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct VOut { float4 pos [[position]]; float2 uv; };
struct Uniforms { float time; float aspect; float brightness; float pad; float4 tint; float2 res; float2 pad2; };

vertex VOut vmain(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    VOut o; o.pos = float4(p * 2.0 - 1.0, 0.0, 1.0); o.uv = p; return o;
}

// ---- shared helpers --------------------------------------------------------
static float hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
static float noise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    return mix(mix(hash(i), hash(i + float2(1, 0)), u.x),
               mix(hash(i + float2(0, 1)), hash(i + float2(1, 1)), u.x), u.y);
}
static float fbm(float2 p) {
    float v = 0.0, a = 0.5;
    const float2x2 m = float2x2(0.8, 0.6, -0.6, 0.8);
    for (int i = 0; i < 4; i++) { v += a * noise(p); p = m * p * 2.03 + 11.7; a *= 0.47; }
    return v;
}
static float2 rot(float2 p, float a) {
    float c = cos(a), s = sin(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}
// Anti-aliased line: d = distance from the line, w = half width, px = one pixel.
static float stroke(float d, float w, float px) {
    return 1.0 - smoothstep(w, w + 1.5 * px, abs(d));
}
// Soft darkening toward the screen edges.
static float vignette(float2 uv, float amount) {
    float d = length((uv - 0.5) * float2(1.25, 1.0)) * 1.6;
    return mix(1.0 - amount, 1.0, smoothstep(1.55, 0.25, d));
}
static float4 finish(float v, float2 fragPos, float brightness, float3 tint, float time) {
    float3 col = v * brightness * tint;
    col += (hash(fragPos + fract(time)) - 0.5) / 255.0;   // dither out banding
    return float4(max(col, 0.0), 1.0);
}
// Hexagon tiling (pointy-top, one unit wide). xy = position in the cell, zw = cell id.
static float4 hexCell(float2 p) {
    const float2 s = float2(1.0, 1.7320508);
    float4 c = floor(float4(p, p - float2(0.5, 1.0)) / float4(s, s)) + 0.5;
    float2 a = p - c.xy * s;
    float2 b = p - (c.zw + 0.5) * s;
    return dot(a, a) < dot(b, b) ? float4(a, c.xy) : float4(b, c.zw + 0.5);
}
static float hexDist(float2 p) {            // 0 at the centre, 0.5 on the edge
    p = abs(p);
    return max(dot(p, float2(0.5, 0.8660254)), p.x);
}

// ---- 1. Silk: slow black-on-black swirls -----------------------------------
fragment float4 f_silk(VOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float2 p = (in.uv - 0.5) * float2(u.aspect, 1.0) * 1.4;
    float t = u.time * 0.012;

    float2 c1 = float2(-0.55, 0.18) + 0.10 * float2(sin(t * 0.9), cos(t * 0.7));
    float2 c2 = float2(0.70, -0.25) + 0.10 * float2(cos(t * 0.6), sin(t * 0.8));
    float2 c3 = float2(0.15, 0.42) + 0.06 * float2(sin(t * 1.1), cos(t * 0.5));
    p = c1 + rot(p - c1, 3.0 * exp(-1.5 * length(p - c1)) + t * 0.5);   // large
    p = c2 + rot(p - c2, -2.2 * exp(-2.2 * length(p - c2)) - t * 0.4);  // medium
    p = c3 + rot(p - c3, 1.6 * exp(-5.0 * length(p - c3)));             // small

    float2 q = float2(fbm(p + float2(0.0, t)), fbm(p + float2(5.2, 1.3 - t)));
    float2 r = float2(fbm(p + 2.2 * q + float2(1.7 + t, 9.2)),
                      fbm(p + 2.2 * q + float2(8.3, 2.8 - t)));
    float f = fbm(p * 0.7 + 2.4 * r);

    float band = f * 3.5 + length(r) * 1.4;
    float w = abs(fract(band) - 0.5) * 2.0;
    float fold = pow(1.0 - w, 2.2);
    float edge = pow(1.0 - w, 14.0);

    float light = smoothstep(0.25, 0.80, length(q));
    float v = 0.008 + 0.105 * fold * mix(0.62, 1.0, light) + 0.10 * edge * mix(0.50, 1.0, light)
            + 0.030 * smoothstep(0.35, 0.8, f);

    // A softer second set of folds fills the calm areas the first set leaves empty.
    float w2 = abs(fract((q.x - q.y) * 2.4 + r.x * 1.6 + 0.37) - 0.5) * 2.0;
    float calm = 1.0 - 0.75 * fold;
    v += (0.060 * pow(1.0 - w2, 2.6) + 0.055 * pow(1.0 - w2, 14.0)) * calm;

    v = max(v - 0.012, 0.0) * 0.62;                  // deeper blacks, quieter highlights
    v *= vignette(in.uv, 0.20);
    return finish(v, in.pos.xy, u.brightness, u.tint.rgb, u.time);
}

// ---- 2. Rings: concentric rings, each carrying a slowly turning arc of light
fragment float4 f_rings(VOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float2 p = (in.uv - 0.5) * float2(u.aspect, 1.0);
    float px = 1.0 / u.res.y;
    float r = length(p);
    float a = atan2(p.y, p.x);

    const float first = 0.055, gap = 0.058;
    float idx = max(round((r - first) / gap), 0.0);
    float d = r - (first + idx * gap);

    float h1 = hash(float2(idx, 3.1)), h2 = hash(float2(idx, 7.7));
    float dir = fmod(idx, 2.0) < 0.5 ? 1.0 : -1.0;
    float turn = u.time * 0.018 * dir * (0.35 + h1) + h2 * 6.2831853;
    float ang = fract((a + turn) / 6.2831853);
    float len = 0.16 + 0.42 * h1;                         // share of the ring that is lit
    float arc = ang < len ? pow(ang / len, 1.6) : 0.0;    // fades in, ends in a bright tip
    arc *= 1.0 - smoothstep(len - 0.003, len, ang);

    float v = stroke(d, 0.0011, px) * (0.050 + 0.26 * arc);
    v += 0.05 * arc * exp(-d * d / 0.00006);              // faint bloom around the lit arc
    v *= vignette(in.uv, 0.45);
    return finish(v, in.pos.xy, u.brightness, u.tint.rgb, u.time);
}

// ---- 3. Dots: a grid of dots that swell as two slow waves pass through ------
fragment float4 f_dots(VOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float2 p = (in.uv - 0.5) * float2(u.aspect, 1.0);
    float px = 1.0 / u.res.y;
    float t = u.time * 0.22;

    const float s = 0.036;
    float2 id = floor(p / s) + 0.5;
    float2 c = id * s;                                    // centre of this dot
    float w1 = sin(length(c - float2(-0.55, -0.30)) * 8.0 - t * 0.6);
    float w2 = sin(dot(c, float2(0.8, 0.6)) * 6.0 + t * 0.4);
    float w = smoothstep(-0.3, 1.0, 0.5 * (w1 + w2));

    float rad = s * (0.045 + 0.215 * w);
    float d = length(p - c);
    float v = (1.0 - smoothstep(rad - px, rad + px, d)) * (0.055 + 0.24 * w);
    v *= vignette(in.uv, 0.35);
    return finish(v, in.pos.xy, u.brightness, u.tint.rgb, u.time);
}

// ---- 4. Honeycomb: hexagon outlines, single cells glowing on and off --------
fragment float4 f_honeycomb(VOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float2 p = (in.uv - 0.5) * float2(u.aspect, 1.0);
    float px = 1.0 / u.res.y;

    const float sc = 8.5;
    float4 h = hexCell(p * sc);
    float ed = (0.5 - hexDist(h.xy)) / sc;                // distance to the cell edge
    float hs = hash(h.zw * 2.0 + 17.0);
    float pulse = pow(max(0.0, sin(u.time * 0.11 * (0.6 + 0.8 * hs) + hs * 6.2831853)), 7.0);
    float drift = noise(p * 1.4 + float2(u.time * 0.012, 3.0));

    float line = stroke(ed, 0.0010, px);
    float inner = smoothstep(0.0085, 0.0085 + 1.5 * px, ed);   // inset fill
    float v = line * (0.055 + 0.05 * drift + 0.16 * pulse) + inner * (0.004 + 0.070 * pulse);
    v *= vignette(in.uv, 0.40);
    return finish(v, in.pos.xy, u.brightness, u.tint.rgb, u.time);
}

// ---- 5. Waves: stacked lines flowing like a ribbon --------------------------
fragment float4 f_waves(VOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float2 p = (in.uv - 0.5) * float2(u.aspect, 1.0);
    float px = 1.0 / u.res.y;
    float t = u.time * 0.10;

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
    v *= vignette(in.uv, 0.45);
    return finish(v, in.pos.xy, u.brightness, u.tint.rgb, u.time);
}

// ---- 6. Facets: a field of triangles, each catching the light in turn -------
fragment float4 f_facets(VOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float2 p = (in.uv - 0.5) * float2(u.aspect, 1.0);
    float px = 1.0 / u.res.y;

    const float s = 0.105;
    float2 g = float2(p.x - p.y * 0.5773503, p.y * 1.1547005) / s;
    float2 id = floor(g), f = fract(g);
    float up = step(1.0, f.x + f.y);
    float d = (up > 0.5 ? min(min(1.0 - f.x, 1.0 - f.y), f.x + f.y - 1.0)
                        : min(min(f.x, f.y), 1.0 - f.x - f.y)) * 0.8660254 * s;

    float h = hash(id * 2.0 + float2(up * 7.0 + 3.0, up * 13.0));
    float tw = 0.5 + 0.5 * sin(u.time * 0.09 * (0.5 + h) + h * 40.0);
    float big = noise(p * 1.25 + float2(u.time * 0.010, 0.0));
    float shade = 0.012 + 0.085 * tw * tw * smoothstep(0.25, 0.95, big + 0.40 * h);

    float v = shade * smoothstep(0.0009, 0.0009 + 1.5 * px, d);   // thin dark seams
    v *= vignette(in.uv, 0.30);
    return finish(v, in.pos.xy, u.brightness, u.tint.rgb, u.time);
}

// ---- 7. Orbits: tilted ellipses with small bodies travelling along them -----
fragment float4 f_orbits(VOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float2 p = (in.uv - 0.5) * float2(u.aspect, 1.0);
    float px = 1.0 / u.res.y;
    const float tilt = 0.30, squash = 0.40;

    float2 q = rot(p, -tilt);
    q.y /= squash;
    float r = length(q);
    float fw = max(fwidth(r), 1e-5);

    float v = 0.0;
    for (int i = 0; i < 7; i++) {
        float fi = float(i);
        float R = 0.17 + 0.125 * fi;
        v = max(v, (1.0 - smoothstep(0.7, 2.2, abs(r - R) / fw)) * 0.075);

        float th = u.time * 0.045 * (1.7 / (1.0 + 0.8 * fi)) + fi * 2.4;
        float2 body = rot(float2(R * cos(th), R * sin(th) * squash), tilt);
        float d = length(p - body);
        float size = 0.0045 + 0.0015 * fmod(fi * 3.0, 4.0);
        v += (1.0 - smoothstep(size - px, size + px, d)) * 0.50 + 0.10 * exp(-d * d / 0.0006);
    }
    float d0 = length(p);
    v += (1.0 - smoothstep(0.020 - px, 0.020 + px, d0)) * 0.26 + 0.11 * exp(-d0 * d0 / 0.006);
    v *= vignette(in.uv, 0.35);
    return finish(v, in.pos.xy, u.brightness, u.tint.rgb, u.time);
}

// ---- 8. Tunnel: nested squares, slowly twisting, light pulsing inward -------
fragment float4 f_tunnel(VOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float2 p = (in.uv - 0.5) * float2(u.aspect, 1.0);
    float px = 1.0 / u.res.y;
    float twist = 0.060 + 0.030 * sin(u.time * 0.028);

    float v = 0.0;
    for (int i = 0; i < 34; i++) {
        float fi = float(i);
        float s = 1.30 * pow(0.875, fi);
        float2 q = abs(rot(p, fi * twist + u.time * 0.008));
        float d = max(q.x, q.y) - s;
        float b = 0.045 + 0.17 * pow(0.5 + 0.5 * sin(fi * 0.55 - u.time * 0.14), 2.0);
        v = max(v, stroke(d, 0.0010, px) * b);
    }
    v *= vignette(in.uv, 0.30);
    return finish(v, in.pos.xy, u.brightness, u.tint.rgb, u.time);
}

// ---- 9. Cubes: isometric columns of cubes slowly rising and sinking ---------
static float cubeHeight(float2 cell, float t) {
    float h = hash(cell + 5.0);
    return 1.0 + 0.70 * sin(t * (0.6 + 0.8 * h) + h * 6.2831853);
}
fragment float4 f_cubes(VOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float2 p = (in.uv - 0.5) * float2(u.aspect, 1.0);
    const float sc = 10.5;
    float aa = 1.5 * sc / u.res.y;                 // one and a half pixels, in cube units
    float t = u.time * 0.115;

    // Isometric view: follow this pixel's line of sight down through the grid
    // of columns, from above the tallest one, until it lands on a face.
    float2 s = p * sc;
    const float z0 = 1.75;
    float sum = 2.0 * (z0 - s.y), dif = s.x / 0.8660254;
    float3 pos = float3(0.5 * (sum + dif), 0.5 * (sum - dif), z0);

    float shade = 0.0, ed = 1.0;
    int face = 0;                                   // side we entered the current cell through
    for (int i = 0; i < 12; i++) {
        float2 c = floor(pos.xy);
        float h = cubeHeight(c, t);
        float2 f = pos.xy - c;
        if (face != 0 && pos.z <= h) {              // landed on a side wall
            float along = face == 1 ? f.y : f.x;
            float depth = h - pos.z;
            ed = min(min(along, 1.0 - along), depth);
            shade = (face == 1 ? 0.066 : 0.026) * exp(-depth * 0.55);
            break;
        }
        float step = min(f.x, f.y);
        if (pos.z - step <= h) {                    // landed on the top
            float2 q = f - (pos.z - h);
            ed = min(min(q.x, 1.0 - q.x), min(q.y, 1.0 - q.y));
            shade = 0.100 + 0.060 * (h - 0.3) / 1.4;   // higher cubes catch more light
            break;
        }
        face = f.x < f.y ? 1 : 2;
        pos -= step + 1e-4;
    }

    float sweep = noise(p * 1.2 + float2(u.time * 0.014, 0.0));
    float v = shade * mix(0.50, 1.0, sweep) * smoothstep(0.012, 0.012 + aa, ed);
    v *= vignette(in.uv, 0.35);
    return finish(v, in.pos.xy, u.brightness, u.tint.rgb, u.time);
}
"""

struct Uniforms {
    var time: Float
    var aspect: Float
    var brightness: Float
    var pad: Float = 0
    var tint: SIMD4<Float>
    var res: SIMD2<Float>
    var pad2: SIMD2<Float> = .zero
}

final class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let queue: MTLCommandQueue
    var pipelines: [MTLRenderPipelineState] = []
    var style = 0
    /// When set, every frame is drawn at this moment (the "still" option).
    var frozenTime: Float?
    let start = CACurrentMediaTime()
    // Start somewhere different each launch so it never looks the same twice.
    let offset = Float.random(in: 0...4000)

    var now: Float { frozenTime ?? offset + Float(CACurrentMediaTime() - start) * SPEED }

    init?(device: MTLDevice) {
        self.device = device
        guard let q = device.makeCommandQueue() else { return nil }
        queue = q
        let lib: MTLLibrary
        do { lib = try device.makeLibrary(source: shaderSource, options: nil) }
        catch { FileHandle.standardError.write("Shader error: \(error)\n".data(using: .utf8)!); return nil }
        for w in WALLPAPERS {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: "vmain")
            d.fragmentFunction = lib.makeFunction(name: w.function)
            d.colorAttachments[0].pixelFormat = .bgra8Unorm
            guard let p = try? device.makeRenderPipelineState(descriptor: d) else { return nil }
            pipelines.append(p)
        }
    }

    func encode(_ pass: MTLRenderPassDescriptor, size: CGSize, time: Float, buffer: MTLCommandBuffer) {
        var u = Uniforms(time: time, aspect: Float(size.width / max(size.height, 1)),
                         brightness: BRIGHTNESS, tint: SIMD4(TINT.0, TINT.1, TINT.2, 1),
                         res: SIMD2(Float(size.width), Float(size.height)))
        guard let enc = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(pipelines[min(max(style, 0), pipelines.count - 1)])
        enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    func draw(in view: MTKView) {
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let buf = queue.makeCommandBuffer() else { return }
        encode(pass, size: view.drawableSize, time: now, buffer: buf)
        buf.present(drawable)
        buf.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func snapshot(width: Int, height: Int, time: Float, to path: String) {
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width,
                                                          height: height, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .shared
        let tex = device.makeTexture(descriptor: td)!
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = tex
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let buf = queue.makeCommandBuffer()!
        encode(pass, size: CGSize(width: width, height: height), time: time, buffer: buf)
        buf.commit()
        buf.waitUntilCompleted()
        var px = [UInt8](repeating: 0, count: width * height * 4)
        tex.getBytes(&px, bytesPerRow: width * 4,
                     from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let ctx = CGContext(data: &px, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                                | CGImageAlphaInfo.premultipliedFirst.rawValue)!
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []
    var statusItem: NSStatusItem!
    var loginItem: NSMenuItem!
    var animatedItem: NSMenuItem!
    var styleItems: [NSMenuItem] = []
    let renderer: Renderer
    let defaults = UserDefaults.standard
    var animated = true

    init(renderer: Renderer) { self.renderer = renderer }

    func applicationDidFinishLaunching(_ note: Notification) {
        defaults.register(defaults: ["animated": true, "style": 0])
        animated = defaults.bool(forKey: "animated")
        renderer.style = min(max(defaults.integer(forKey: "style"), 0), WALLPAPERS.count - 1)
        renderer.frozenTime = animated ? nil : renderer.now

        rebuild()
        NotificationCenter.default.addObserver(
            self, selector: #selector(rebuild),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(occlusionChanged(_:)),
            name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(rebuild), name: NSWorkspace.didWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(rebuild),
                       name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "moon.fill", accessibilityDescription: "Drift")
        statusItem.button?.image?.isTemplate = true
        let menu = NSMenu()
        let title = NSMenuItem(title: "Wallpaper", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        for (i, w) in WALLPAPERS.enumerated() {
            let item = NSMenuItem(title: w.name, action: #selector(pickStyle(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            menu.addItem(item)
            styleItems.append(item)
        }
        menu.addItem(.separator())
        animatedItem = NSMenuItem(title: "Animated", action: #selector(toggleAnimated), keyEquivalent: "")
        animatedItem.target = self
        menu.addItem(animatedItem)
        loginItem = NSMenuItem(title: "Start at login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Drift", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
        refreshMenu()
    }

    func refreshMenu() {
        for item in styleItems { item.state = item.tag == renderer.style ? .on : .off }
        animatedItem.state = animated ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    /// Animated: draw continuously while visible. Still: draw one frame and stop.
    func applyMode(to window: NSWindow) {
        guard let v = window.contentView as? MTKView else { return }
        if animated {
            v.enableSetNeedsDisplay = false
            v.isPaused = !window.occlusionState.contains(.visible)
        } else {
            v.isPaused = true
            v.enableSetNeedsDisplay = true
            v.needsDisplay = true
        }
    }

    @objc func pickStyle(_ sender: NSMenuItem) {
        renderer.style = sender.tag
        defaults.set(sender.tag, forKey: "style")
        windows.forEach(applyMode)
        refreshMenu()
    }

    @objc func toggleAnimated() {
        animated.toggle()
        defaults.set(animated, forKey: "animated")
        renderer.frozenTime = animated ? nil : renderer.now
        windows.forEach(applyMode)
        refreshMenu()
    }

    @objc func occlusionChanged(_ note: Notification) {
        guard let w = note.object as? NSWindow, windows.contains(w) else { return }
        applyMode(to: w)
    }

    @objc func rebuild() {
        let frames = NSScreen.screens.map { $0.frame }
        if frames == windows.map({ $0.frame }) && !windows.isEmpty {
            windows.forEach { $0.orderFront(nil) }
            return
        }
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map { screen in
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                             backing: .buffered, defer: false)
            // Above the system wallpaper, below desktop icons.
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            w.ignoresMouseEvents = true
            w.isOpaque = true
            w.hasShadow = false
            w.backgroundColor = .black
            w.isReleasedWhenClosed = false
            let view = MTKView(frame: CGRect(origin: .zero, size: screen.frame.size),
                               device: renderer.device)
            view.colorPixelFormat = .bgra8Unorm
            view.preferredFramesPerSecond = FPS
            view.delegate = renderer
            w.contentView = view
            w.setFrame(screen.frame, display: true)
            w.orderFront(nil)
            return w
        }
        windows.forEach(applyMode)
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let a = NSAlert()
            a.messageText = "Couldn't change the login setting"
            a.informativeText = "Move Drift into your Applications folder, open it from there, and try again.\n\n\(error.localizedDescription)"
            NSApp.activate(ignoringOtherApps: true)
            a.runModal()
        }
        refreshMenu()
    }
}

guard let device = MTLCreateSystemDefaultDevice(), let renderer = Renderer(device: device) else {
    FileHandle.standardError.write("Drift: could not set up Metal\n".data(using: .utf8)!)
    exit(1)
}

// `Drift --snapshot out.png [width height time style]` renders one still frame and exits.
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--snapshot"), args.count > i + 1 {
    let w = args.count > i + 3 ? Int(args[i + 2]) ?? 2560 : 2560
    let h = args.count > i + 3 ? Int(args[i + 3]) ?? 1664 : 1664
    let t = args.count > i + 4 ? Float(args[i + 4]) ?? 0 : 0
    renderer.style = args.count > i + 5 ? Int(args[i + 5]) ?? 0 : 0
    renderer.snapshot(width: w, height: h, time: t, to: args[i + 1])
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate(renderer: renderer)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
