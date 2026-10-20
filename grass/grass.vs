// Package grass builds 3D grass clumps and blade atlases for instanced
// ground cover near a camera.
//
// Each Tuft is a small cluster of arched, intersecting grass cards with
// upward-softened normals (so the clump blends seamlessly into the terrain
// beneath it) and root-to-tip vertex color shading (darker at the soil,
// warmer at the sunlit tips).
package grass

import (
    "image"
    "image/draw"
    "math"
    "math/geom"
    "math/rand"
    "mesh"
)

/// Atlas paints a 256 × 128 sRGB alpha-masked grass-blade strip: dense
/// overlapping blades rising from the bottom edge, feathered at the top,
/// with non-black transparent texels so mipmaps preserve blade color.
public func Atlas(base: geom.Vec3 = geom.Vec3(0.42, 0.52, 0.28), seed: uint64 = 1) -> image.RGBA {
    let w = 256, h = 128
    var img = image.RGBA(width: w, height: h)
    let br = uint8(math.Clamp(base.X * 0.85, 0, 1) * 255)
    let bg = uint8(math.Clamp(base.Y * 0.85, 0, 1) * 255)
    let bb = uint8(math.Clamp(base.Z * 0.85, 0, 1) * 255)
    for i in 0..<(w * h) {
        let k = i * 4
        img.Pixels[k] = br
        img.Pixels[k + 1] = bg
        img.Pixels[k + 2] = bb
        img.Pixels[k + 3] = 0
    }
    var g = rand.Xorshift128Plus(seed: seed &* 0x9E3779B97F4A7C15 &+ 7)
    func unit() -> float32 { return float32(g.Float64()) }

    draw.WithCanvas(&img.Pixels, width: int32(w), height: int32(h)) { c in
        for i in 0..<210 {
            let x0 = (float32(i) + unit() * 0.8) / 210.0 * float32(w - 8) + 4
            let y0 = float32(h)
            let bh = float32(h) * (0.48 + 0.46 * unit())
            let lean = (unit() - 0.5) * 26.0
            let x1 = math.Clamp(x0 + lean, 2, float32(w - 2))
            let y1 = float32(h) - bh
            let xm = (x0 + x1) * 0.5 + lean * 0.22
            let ym = (y0 + y1) * 0.5
            let w0 = 2.8 + unit() * 1.6
            let wMid = w0 * 0.65
            let shade = 0.78 + unit() * 0.38
            let dry = unit() > 0.75 ? float32(0.16) : float32(0)
            let cr = uint8(math.Clamp((base.X * (1 + dry) * shade), 0, 1) * 255)
            let cg = uint8(math.Clamp((base.Y * shade), 0, 1) * 255)
            let cb = uint8(math.Clamp((base.Z * (1 - dry * 0.5) * shade), 0, 1) * 255)
            var p = draw.Path()
            p.MoveTo(x0 - w0, y0)
            p.LineTo(xm - wMid, ym)
            p.LineTo(x1, y1)
            p.LineTo(xm + wMid, ym)
            p.LineTo(x0 + w0, y0)
            p.Close()
            c.FillPath(p, draw.Color(cr, cg, cb, 255))
        }
    }
    for i in 0..<(w * h) {
        let k = i * 4
        let a = img.Pixels[k + 3]
        if a == 0 {
            img.Pixels[k] = br
            img.Pixels[k + 1] = bg
            img.Pixels[k + 2] = bb
        } else if a < 250 {
            let inv = 255.0 / float32(a)
            img.Pixels[k] = uint8(math.Clamp(float32(img.Pixels[k]) * inv, 0, 255))
            img.Pixels[k + 1] = uint8(math.Clamp(float32(img.Pixels[k + 1]) * inv, 0, 255))
            img.Pixels[k + 2] = uint8(math.Clamp(float32(img.Pixels[k + 2]) * inv, 0, 255))
        }
    }
    return img
}

/// Tuft builds a 3D grass clump mesh of `ribbons` arched blade cards across
/// `radius` meters, standing `height` meters tall.
public func Tuft(seed: uint64, radius: float32 = 0.65, height: float32 = 0.24, ribbons: int = 7) -> mesh.Mesh {
    var g = rand.Xorshift128Plus(seed: seed &* 0x9E3779B97F4A7C15 &+ 13)
    func unit() -> float32 { return float32(g.Float64()) }
    var m = mesh.Mesh()
    for k in 0..<ribbons {
        let a = (float32(k) / float32(ribbons) + (unit() - 0.5) * 0.15) * 6.2832
        let dist = radius * 0.45 * math.Sqrt(unit())
        let cx = math.Cos(a) * dist, cz = math.Sin(a) * dist
        let yaw = a + 1.05 + (unit() - 0.5) * 0.8
        let dx = math.Cos(yaw), dz = math.Sin(yaw)
        let nx = -dz, nz = dx
        let w = radius * (0.48 + 0.28 * unit())
        let h = height * (0.72 + 0.42 * unit())
        let droop = h * (0.18 + 0.18 * unit())
        let p0 = geom.Vec3(cx - dx * w, -0.02, cz - dz * w)
        let p1 = geom.Vec3(cx + dx * w, -0.02, cz + dz * w)
        let p2 = geom.Vec3(cx + dx * w + nx * droop, h, cz + dz * w + nz * droop)
        let p3 = geom.Vec3(cx - dx * w + nx * droop, h, cz - dz * w + nz * droop)
        let nBot = geom.Vec3(nx * 0.12, 0.99, nz * 0.12).Normalized()
        let nTop = geom.Vec3(nx * 0.22, 0.97, nz * 0.22).Normalized()
        let v = uint32(m.Positions.count)
        m.Positions += [p0, p1, p2, p3]
        m.Normals += [nBot, nBot, nTop, nTop]
        // UV: V=1 at bottom, V=0 at top of the blade strip.
        m.UVs += [geom.Vec2(0, 0.98), geom.Vec2(1, 0.98), geom.Vec2(1, 0.02), geom.Vec2(0, 0.02)]
        let tint = 0.94 + unit() * 0.12
        let cBot = geom.Vec4(0.68 * tint, 0.70 * tint, 0.62 * tint, 1)
        let cTop = geom.Vec4(1.06 * tint, 1.08 * tint, 0.96 * tint, 1)
        m.Colors += [cBot, cBot, cTop, cTop]
        m.Indices += [v, v + 1, v + 2, v, v + 2, v + 3]
    }
    return m
}
