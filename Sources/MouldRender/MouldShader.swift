// The Metal source lives in a Swift string so `swift build` needs no Xcode-only metal toolchain step;
// it is compiled at runtime (and in the tests) with `makeLibrary(source:)`.
enum MouldShader {
    static let vertexFunction = "mould_vertex"
    static let fragmentFunction = "mould_fragment"

    static let source = #"""
#include <metal_stdlib>
using namespace metal;

struct VOut { float4 position [[position]]; };

// One oversized triangle covering the whole viewport.
vertex VOut mould_vertex(uint vid [[vertex_id]]) {
    float2 uv = float2(float((vid << 1) & 2), float(vid & 2));
    VOut o;
    o.position = float4(uv * 2.0 - 1.0, 0.0, 1.0);
    return o;
}

struct Uniforms {
    float4 view;   // width (pt), height (pt), backing scale, time (s)
    float4 params; // wipe front (<0 = none), opacity, colony count, theme
};

struct Colony {
    float4 a; // x, y, radius, maturity
    float4 b; // species, noise seed, spore radius, stretch
    float4 c; // angle, cos(angle), sin(angle), -
};

// ---------------------------------------------------------------- noise

float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float2 hash22(float2 p) {
    float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

float vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash12(i);
    float b = hash12(i + float2(1, 0));
    float c = hash12(i + float2(0, 1));
    float d = hash12(i + float2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(float2 p, int octaves) {
    float sum = 0.0, amp = 0.5, norm = 0.0;
    const float2x2 rot = float2x2(1.6, 1.2, -1.2, 1.6);
    for (int i = 0; i < octaves; i++) {
        sum += amp * vnoise(p);
        norm += amp;
        p = rot * p + 17.3;
        amp *= 0.5;
    }
    return sum / norm;
}

// x: distance to nearest feature point, y: random id of that cell
float2 voronoi(float2 p) {
    float2 n = floor(p);
    float2 f = fract(p);
    float md = 8.0, id = 0.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            float2 g = float2(i, j);
            float2 o = hash22(n + g);
            float2 r = g + o - f;
            float d = dot(r, r);
            if (d < md) { md = d; id = hash12(n + g + 17.0); }
        }
    }
    return float2(sqrt(md), id);
}

// Premultiplied "over".
float4 over(float4 dst, float3 color, float alpha) {
    alpha = saturate(alpha);
    return float4(color * alpha, alpha) + dst * (1.0 - alpha);
}

// ---------------------------------------------------------------- fungi

struct Look {
    float3 spore;     // light tone of the spore mass
    float3 sporeDark; // dark tone of the spore mass
    float3 mycelium;  // hyphae
    float3 rot;       // water-soaked tissue under and around the colony
    float fuzz;       // how tall and hairy the colony is
    float pins;       // black sporangia (Rhizopus)
    float tufts;      // grey conidiophore clusters (Botrytis)
};

Look lookFor(uint species) {
    Look l;
    switch (species) {
    case 0: // Penicillium digitatum: olive-green powder, wide white margin
        l.spore = float3(0.66, 0.72, 0.38); l.sporeDark = float3(0.38, 0.47, 0.19);
        l.mycelium = float3(0.97, 0.97, 0.92); l.rot = float3(0.74, 0.58, 0.26);
        l.fuzz = 0.45; l.pins = 0.0; l.tufts = 0.0; break;
    case 1: // Penicillium italicum: blue-green powder, narrow margin
        l.spore = float3(0.42, 0.64, 0.60); l.sporeDark = float3(0.17, 0.38, 0.40);
        l.mycelium = float3(0.95, 0.97, 0.95); l.rot = float3(0.62, 0.52, 0.26);
        l.fuzz = 0.35; l.pins = 0.0; l.tufts = 0.0; break;
    case 2: // Botrytis cinerea: grey-brown velvet
        l.spore = float3(0.70, 0.67, 0.61); l.sporeDark = float3(0.36, 0.31, 0.25);
        l.mycelium = float3(0.88, 0.87, 0.84); l.rot = float3(0.42, 0.18, 0.12);
        l.fuzz = 0.9; l.pins = 0.0; l.tufts = 1.0; break;
    default: // Rhizopus stolonifer: cotton candy from hell
        l.spore = float3(0.86, 0.86, 0.82); l.sporeDark = float3(0.60, 0.60, 0.56);
        l.mycelium = float3(0.97, 0.97, 0.95); l.rot = float3(0.45, 0.20, 0.13);
        l.fuzz = 1.0; l.pins = 1.0; l.tufts = 0.0; break;
    }
    return l;
}

// The fruit the mould brings along: a halo of peel around each colony.
float3 peelColor(uint theme, float2 p, thread float &alphaScale) {
    alphaScale = 1.0;
    if (theme == 0) {
        // Orange: oil-gland dimples in a waxy, uneven orange.
        float2 v = voronoi(p / 4.5);
        float dimple = smoothstep(0.0, 0.55, v.x);
        float blotch = fbm(p / 40.0, 3);
        float3 base = mix(float3(0.93, 0.42, 0.04), float3(1.0, 0.62, 0.12), blotch);
        return base * (0.78 + 0.22 * dimple);
    }
    if (theme == 1) {
        // Strawberry: glossy red flesh with yellow achenes sitting in little pits.
        float2 cell = p / 17.0;
        float2 v = voronoi(cell);
        float blotch = fbm(p / 35.0, 3);
        float3 base = mix(float3(0.62, 0.03, 0.07), float3(0.86, 0.12, 0.13), blotch);
        float pit = 1.0 - smoothstep(0.12, 0.30, v.x);
        float seed = 1.0 - smoothstep(0.07, 0.13, v.x);
        base *= 1.0 - 0.35 * pit;
        return mix(base, float3(0.93, 0.78, 0.33), seed * 0.9);
    }
    // Compost: brown mush.
    alphaScale = 0.8;
    return mix(float3(0.30, 0.20, 0.10), float3(0.50, 0.36, 0.18), fbm(p / 25.0, 3));
}

// ---------------------------------------------------------------- the mould

fragment float4 mould_fragment(VOut in [[stage_in]],
                               constant Uniforms &u [[buffer(0)]],
                               constant Colony *colonies [[buffer(1)]],
                               texture2d<float> profiles [[texture(0)]]) {
    constexpr sampler profileSampler(address::repeat, filter::linear);
    const float scale = u.view.z;
    const float2 p = in.position.xy / scale; // points, origin top-left
    const int count = int(u.params.z);
    const uint theme = uint(u.params.w);

    // The wipe (hotkey): a cloth sweeping from the top-left. Anything behind it is gone, so bail early.
    float mask = 1.0;
    if (u.params.x >= 0.0) {
        float s = (p.x / u.view.x) * 0.55 + (p.y / u.view.y) * 0.45;
        float edgeN = (fbm(p / 45.0 + 2.0, 3) - 0.5) * 0.18;
        float front = u.params.x * 1.35 - 0.12;
        mask = smoothstep(front, front + 0.05, s + edgeN);
        if (mask <= 0.0) return float4(0.0);
    }

    // Cheap early-out before any noise: is any colony (plus warp slack) near this pixel at all?
    bool near = false;
    for (int i = 0; i < count && !near; i++) {
        float2 dv = abs(p - colonies[i].a.xy);
        float reach = colonies[i].a.z * 1.7 * colonies[i].b.w + 90.0;
        near = dv.x < reach && dv.y < reach;
    }
    if (!near) return float4(0.0);

    // Domain warp: colonies get lobed, organic outlines instead of circles.
    float2 wp = p / 220.0;
    float2 warp = float2(fbm(wp, 3), fbm(wp + float2(5.2, 1.3), 3)) - 0.5;
    float2 q = p + warp * 34.0;
    float fray = fbm(p / 6.0, 2) - 0.5;

    // Shadow sample point: light from the top-left, so shadows fall bottom-right.
    const float2 shadowOffset = float2(3.0, 4.0);

    float myc = 0.0, spore = 0.0, rot = 0.0, peel = 0.0, shadow = 0.0, hsum = 0.0;
    float3 sporeC = 0.0, sporeD = 0.0, mycC = 0.0, rotC = 0.0;
    float pins = 0.0, tufts = 0.0, fuzz = 0.0, wsum = 1e-5, mature = 0.0;
    float fibre = 0.0, sporeAge = 0.0, ring = 0.0;
    float depth1 = 1e4, depth2 = 1e4; // distance to the two nearest growth fronts (negative = inside)

    for (int i = 0; i < count; i++) {
        Colony c = colonies[i];
        float r = c.a.z;
        float2 dv = q - c.a.xy;
        float reach = r * 1.7 + 70.0;
        if (abs(dv.x) > reach || abs(dv.y) > reach) continue;

        float cs = c.c.y, sn = c.c.z;
        float2 e = float2(cs * dv.x + sn * dv.y, -sn * dv.x + cs * dv.y);
        e.x /= c.b.w;
        float dist = length(e);
        if (dist > reach) continue;

        float2 dir = e / max(dist, 1e-3);
        float seed = c.b.y * 97.0;
        float mat = c.a.w;
        Look L = lookFor(uint(c.b.x));

        // Per-colony outline profile, precomputed per angle: (lobes, fine lobes, spore wobble, hyphal reach).
        float angle = atan2(e.y, e.x) * (0.5 / M_PI_F) + 0.5;
        float4 prof = profiles.sample(profileSampler, float2(angle, (float(i) + 0.5) / float(profiles.get_height())));

        // Lobed outline, ragged at the finest scale.
        float lobes = prof.x * (0.11 * r + 3.0) + prof.y * (0.045 * r + 1.0);
        float edge = max(r + lobes + fray * min(6.0, r * 0.5), 0.0);
        float dEdge = dist - edge;
        float body = (1.0 - smoothstep(-4.0, 1.0, dEdge)) * smoothstep(0.3, 2.5, r);

        // Hyphae radiating past the edge: noise sampled on a big circle, slowly along the radius.
        // They wander a little as they grow outwards, and some reach much further than others.
        float sr = c.b.z;
        float fringeLen = 3.0 + (8.0 + 22.0 * L.fuzz) * (0.35 + 1.1 * prof.w)
                        * smoothstep(0.0, 0.5, mat) * smoothstep(2.0, 40.0, r);
        float strands = 0.5, fringe = 0.0;
        if (dEdge < fringeLen && dist > sr - 14.0) {
            float around = max(r, 10.0);
            float along = dist * 0.04;
            float2 perp = float2(-dir.y, dir.x);
            float2 hdir = dir + perp * (vnoise(float2(dist * 0.06, seed + dir.x * 3.0)) - 0.5) * (6.0 / around);
            strands = vnoise(hdir * around * 0.9 + float2(along, seed)) * 0.55
                    + vnoise(hdir * around * 2.2 + float2(along * 2.3, seed + 7.0)) * 0.45;
            fringe = smoothstep(0.5, 0.78, strands) * (1.0 - smoothstep(-2.0, fringeLen, dEdge)) * step(-6.0, dEdge);
        }
        float m = max(body, fringe * 0.8);

        // The coloured spore mass, with its own wobbly outline.
        float core = 0.0, sa = 0.0, rg = 0.0;
        if (sr > 0.5) {
            float dCore = dist - (sr + lobes * 0.8 + prof.z * sr * 0.22 + fray * 8.0);
            core = 1.0 - smoothstep(-12.0, 3.0, dCore);
            // 0 at the young, pale sporulating edge -> 1 at the old centre.
            sa = saturate(-dCore / max(sr * 0.8, 12.0));
            // Growth rings: the colony sporulates in flushes.
            rg = sin(dist * 0.21 + prof.z * 2.5 + fray * 3.0 + seed);
        }

        // Water-soaked rot and the fruit peel beyond it.
        float rotW = 5.0 + r * 0.07;
        float rz = (1.0 - smoothstep(-4.0, rotW, dEdge)) * smoothstep(0.05, 0.5, mat);
        float pz = (1.0 - smoothstep(rotW * 0.3, rotW + 10.0 + r * 0.12, dEdge)) * smoothstep(0.0, 0.35, mat);

        // Contact shadow: the colony as seen from a point nudged towards the light.
        float2 so = float2(cs * shadowOffset.x + sn * shadowOffset.y, -sn * shadowOffset.x + cs * shadowOffset.y);
        so.x /= c.b.w;
        float sd = length(e - so * (0.6 + L.fuzz));
        float sh = 1.0 - smoothstep(-3.0, 5.0, sd - edge);

        // Cushion-shaped height; spores sit on top.
        float dome = sqrt(saturate(1.0 - dist / max(edge, 1.0)));
        float h = body * (0.35 + 0.65 * dome) * (0.5 + L.fuzz) + core * 0.2;

        // Attributes come (almost) from the colony we're deepest inside, so neighbours don't blur together.
        float w = (m + rz * 0.25 + pz * 0.05) * exp(clamp(-dEdge, -40.0, 600.0) * 0.12);
        if (dEdge < depth1) { depth2 = depth1; depth1 = dEdge; }
        else if (dEdge < depth2) { depth2 = dEdge; }
        wsum += w;
        sporeC += L.spore * w;
        sporeD += L.sporeDark * w;
        mycC += L.mycelium * w;
        rotC += L.rot * w;
        pins += L.pins * smoothstep(0.3, 1.0, mat) * w;
        tufts += L.tufts * smoothstep(0.2, 0.8, mat) * w;
        fuzz += L.fuzz * w;
        mature += mat * w;
        fibre += strands * w;
        sporeAge += sa * w;
        ring += rg * w;

        myc = 1.0 - (1.0 - myc) * (1.0 - m);
        spore = 1.0 - (1.0 - spore) * (1.0 - core);
        rot = max(rot, rz);
        peel = max(peel, pz);
        shadow = max(shadow, sh);
        hsum += exp(6.0 * h) - 1.0;
    }

    if (myc + rot + peel + shadow < 0.003) return float4(0.0);

    float inv = 1.0 / wsum;
    sporeC *= inv; sporeD *= inv; mycC *= inv; rotC *= inv;
    pins *= inv; tufts *= inv; fuzz *= inv; mature *= inv;
    fibre *= inv; sporeAge *= inv; ring *= inv;
    // Where two growth fronts met, neither colony sporulates: a pale mycelium seam with a crease.
    float seamN = (fbm(p / 28.0 + 31.0, 2) - 0.5) * 8.0;
    float both = 1.0 - smoothstep(-6.0, 2.0, depth2);
    float gap = depth2 - depth1 + seamN;
    float seam = (1.0 - smoothstep(1.0, 9.0, gap)) * both;
    float crease = (1.0 - smoothstep(0.0, 2.0, gap)) * both;
    spore *= 1.0 - 0.6 * seam;
    hsum *= 1.0 - 0.5 * seam;
    float H = log(1.0 + hsum) / 6.0;

    // ---- surface detail
    const float ps = 0.9;
    float b0 = fbm(p * ps, 3);
    float bx = fbm((p + float2(0.5, 0.0)) * ps, 3);
    float by = fbm((p + float2(0.0, 0.5)) * ps, 3);
    float speck = vnoise(p * 1.9 + 3.0);
    float grain = hash12(floor(p * scale));
    float cotton = fbm(p * 0.12 + 11.0, 3);

    // Sporangia / conidia clusters.
    // Rhizopus sporangia: clustered, varying in size, white -> grey -> black as they ripen.
    float2 pv = float2(1.0, 0.0);
    float pinHead = 0.0, pinRipe = 0.0, pinHalo = 0.0;
    if (pins > 0.01) {
        pv = voronoi(p / 6.0);
        float cluster = smoothstep(0.35, 0.7, fbm(p / 60.0 + 21.0, 3));
        float headR = 0.08 + 0.12 * fract(pv.y * 7.13);
        float pinOn = step(pv.y, pins * (0.15 + 0.7 * cluster)) * myc;
        pinHead = (1.0 - smoothstep(headR, headR + 0.07, pv.x)) * pinOn;
        pinRipe = smoothstep(0.2, 0.9, fract(pv.y * 13.7) * 0.6 + mature * 0.6);
        pinHalo = (1.0 - smoothstep(headR + 0.05, headR + 0.35, pv.x)) * pinOn;
    }
    // Botrytis conidiophores: grape-like grey clumps on a velvety, mottled mat.
    float clump = 0.0, tuft = 0.0;
    if (tufts > 0.01) {
        float2 tv = voronoi(p / 4.0 + 40.0);
        float2 tv2 = voronoi(p / 11.0 + 7.0);
        clump = smoothstep(0.7, 0.1, tv2.x);
        tuft = smoothstep(0.6, 0.0, tv.x) * tufts * (0.35 + 0.65 * clump);
    }

    // ---- lighting
    float heightPt = H * (6.0 + 8.0 * fuzz);
    float2 gMacro = float2(dfdx(heightPt), dfdy(heightPt)) * scale;
    float microAmp = 0.12 + 0.55 * spore + tuft * 1.0;
    float2 gMicro = float2(bx - b0, by - b0) / 0.5 * microAmp;
    float3 n = normalize(float3(-(gMacro + gMicro), 1.0));
    const float3 light = normalize(float3(-0.55, -0.7, 0.85));
    float diff = saturate(dot(n, light));
    float ao = mix(0.72, 1.0, saturate(H * 2.2));
    float shade = (0.5 + 0.62 * diff) * ao;
    float sheen = pow(saturate(1.0 - n.z), 0.8) * 0.5 * (0.4 + fuzz);

    float4 o = float4(0.0);

    // Fruit peel halo.
    // (Hidden under dense mycelium, so skip the work there.)
    if (peel > 0.003 && myc < 0.98) {
        float peelScale;
        float3 peelC = peelColor(theme, p, peelScale);
        float peelN = fbm(p / 18.0 + 5.0, 3);
        o = over(o, peelC, peel * peelScale * (0.30 + 0.25 * peelN) * (1.0 - 0.5 * rot));
    }

    // Soft rot: water-soaked, blotchy, glossy.
    if (rot > 0.003 && myc < 0.98) {
        float rotN = fbm(p / 20.0 + 9.0, 3);
        float3 rotCol = rotC * (0.78 + 0.35 * rotN);
        o = over(o, rotCol, rot * (0.22 + 0.2 * rotN));
        float3 wetN = normalize(float3((float2(fbm(p / 11.0, 2), fbm(p / 11.0 + 4.0, 2)) - 0.5) * 1.4, 1.0));
        float spec = pow(saturate(dot(reflect(-light, wetN), float3(0, 0, 1))), 24.0);
        o = over(o, float3(1.0), spec * rot * (1.0 - myc) * 0.45);
    }

    // Shadow cast onto whatever is underneath.
    o = over(o, float3(0.05, 0.04, 0.02), shadow * (1.0 - myc) * (0.22 + 0.2 * fuzz));

    // Mycelium: white cotton, translucent where thin.
    // Radial fibres + soft cotton clumps; thin (translucent) at the growing edge, dense inside.
    float fib = smoothstep(0.25, 0.85, fibre);
    float3 mycCol = mycC * (0.86 + 0.12 * cotton + 0.08 * fib) * mix(1.0, shade, 0.6) + sheen * 0.3;
    float dense = smoothstep(0.02, 0.35, H);
    float mycA = myc * mix(0.35 + 0.5 * fib, 0.8 + 0.18 * cotton, dense);
    o = over(o, mycCol, mycA);
    o = over(o, mycC * 0.4, crease * 0.2);

    // Spores: powdery, speckled, a touch paler where the colony is oldest.
    float tone = saturate(0.25 + b0 * 0.6 + (speck - 0.5) * 0.3 + ring * 0.06);
    float3 sporeCol = mix(sporeD, sporeC, tone);
    // Young conidia at the sporulating front are pale, still half mycelium.
    sporeCol = mix(mycC * 0.95, sporeCol, smoothstep(0.0, 0.45, sporeAge) * 0.85 + 0.15);
    // The oldest centre darkens and dulls.
    sporeCol *= 1.0 - 0.18 * smoothstep(0.6, 1.0, sporeAge);
    sporeCol = mix(sporeCol, float3(0.93, 0.93, 0.88), tuft * 0.45);
    sporeCol *= shade * (0.9 + 0.2 * grain);
    sporeCol += sheen * 0.15;
    o = over(o, sporeCol, spore * (0.84 + 0.14 * tone));

    // Black pinheads with a tiny glint.
    // Botrytis: dark gaps between the clumps, pale dusty tops.
    o = over(o, sporeD * 0.7, tufts * spore * (1.0 - clump) * 0.35);
    o = over(o, float3(0.80, 0.78, 0.72) * shade, tuft * spore * 0.55);
    // Rhizopus: a wisp of white stalk-fluff around each head, then the head itself.
    o = over(o, float3(0.97), pinHalo * 0.25);
    float3 headCol = mix(float3(0.85, 0.85, 0.80), float3(0.05, 0.05, 0.045), pinRipe);
    o = over(o, headCol * (0.8 + 0.3 * diff), pinHead * 0.95);
    float2 hl = voronoi(p / 6.0 + float2(0.025, 0.025));
    o = over(o, float3(0.9), (1.0 - smoothstep(0.015, 0.05, hl.x)) * pinHead * pinRipe * 0.45);

    return o * u.params.y * mask;
}
"""#
}
