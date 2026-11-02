package tree

import (
    "image"
    "image/draw"
    "math"
    "math/geom"
    "math/noise"
    "math/rand"
)

/// Atlas paints the texture a species' trees are drawn from, 512 × 256
/// (sRGB, alpha where needles are): a needle spray on the left half (a
/// twig running left to right with needles both sides, transparent
/// between), bark next (furrowed, streaked up and down), and far foliage
/// at the right (needles seen from afar: dark, mottled, solid).
public func Atlas(s: Species, seed: uint64 = 1) -> image.RGBA {
    let w = 512, h = 256
    var img = image.RGBA(width: w, height: h)
    var g = rand.Xorshift128Plus(seed: seed)
    func unit() -> float32 { return float32(g.Float64()) }
    func rgb(c: geom.Vec3, k: float32) -> draw.Color {
        return draw.Color(uint8(math.Clamp(c.X * k, 0, 1) * 255), uint8(math.Clamp(c.Y * k, 0, 1) * 255), uint8(math.Clamp(c.Z * k, 0, 1) * 255), 255)
    }

    // Bark and far foliage: per pixel, from noise.
    let n = noise.Simplex(seed: uint32(seed & 0xFFFF) &+ 11)
    for y in 0..<h {
        for x in 0..<w {
            let fx = float32(x), fy = float32(y)
            let i = (y * w + x) * 4
            if x < 256 {
                // Transparent needle ground: pre-filled with needle RGB so
                // GPU mipmaps never bleed black into needle edges.
                img.Pixels[i] = uint8(math.Clamp(s.Needles.X * 0.82, 0, 1) * 255)
                img.Pixels[i + 1] = uint8(math.Clamp(s.Needles.Y * 0.82, 0, 1) * 255)
                img.Pixels[i + 2] = uint8(math.Clamp(s.Needles.Z * 0.82, 0, 1) * 255)
                img.Pixels[i + 3] = 0
                continue
            }
            var c: geom.Vec3
            if x < 384 {
                // Bark: long vertical furrows, plates between, flecks.
                let furrow = math.Abs(n.At(fx * 0.09, fy * 0.012))
                let plates = n.At(fx * 0.05, fy * 0.03) * 0.5 + 0.5
                let fleck = n.At(fx * 0.4, fy * 0.4) * 0.5 + 0.5
                let k = 0.55 + 0.6 * math.Pow(furrow, 0.6) * (0.7 + 0.3 * plates) + (fleck - 0.5) * 0.15
                c = s.Bark * k
            } else {
                // Far foliage: dark green mottled with lighter clumps.
                let clump = n.At(fx * 0.08, fy * 0.08) * 0.5 + 0.5
                let fine = n.At(fx * 0.35, fy * 0.35) * 0.5 + 0.5
                c = s.Needles * (0.75 + clump * 0.45 + (fine - 0.5) * 0.2)
            }
            img.Pixels[i] = uint8(math.Clamp(c.X, 0, 1) * 255)
            img.Pixels[i + 1] = uint8(math.Clamp(c.Y, 0, 1) * 255)
            img.Pixels[i + 2] = uint8(math.Clamp(c.Z, 0, 1) * 255)
            img.Pixels[i + 3] = 255
        }
    }

    // The spray: needles as lush strokes either side of a twig, and side
    // twigs off it, on a transparent ground.
    draw.WithCanvas(&img.Pixels, width: int32(w), height: int32(h)) { c in
        let mid: float32 = 128
        var twigs: [(float32, float32, float32, float32)] = [(4, mid, 236, mid)]
        // Side twigs: out from the main one, forward, both ways.
        var x: float32 = 10
        var flip: float32 = 1
        while x < 218 {
            // Long near the base, out toward the card's edges.
            let len = (232 - x) * 0.54 + 22
            let tx = x + len * 0.56
            let ty = mid - flip * len * 0.82
            twigs.append((x, mid, tx, ty))
            // Secondary shoot off longer side twigs for fuller bough volume.
            if len > 55 {
                let mx = x + (tx - x) * 0.45
                let my = mid + (ty - mid) * 0.45
                twigs.append((mx, my, mx + len * 0.34, my - flip * len * 0.28))
            }
            flip = -flip
            x += 7 + unit() * 5
        }
        for (k, t) in twigs.enumerated() {
            let dx = t.2 - t.0, dy = t.3 - t.1
            let len = math.Sqrt(dx * dx + dy * dy)
            let ux = dx / len, uy = dy / len
            let nx = -uy, ny = ux
            let main = k == 0
            // Needles along it, longest near its base, darker at the base
            // of each needle and warmer at the sunlit tips.
            var a: float32 = 0
            while a < len {
                let px = t.0 + ux * a, py = t.1 + uy * a
                let reach = (main ? 34 : 22) * (1 - a / len * 0.42) * (0.82 + unit() * 0.38)
                for side in [float32(1), -1] {
                    // Swept forward, toward the twig's tip.
                    let ex = px + (nx * side * 0.8 + ux * 0.6) * reach
                    let ey = py + (ny * side * 0.8 + uy * 0.6) * reach
                    let shade = 0.72 + (a / len) * 0.22 + unit() * 0.38
                    stroke(c, px, py, ex, ey, 2.0, rgb(s.Needles, shade))
                }
                a += main ? 1.5 : 1.7
            }
            stroke(c, t.0, t.1, t.2, t.3, main ? 2.6 : 1.5, rgb(s.Bark, 0.78))
        }
    }
    // Preserve needle RGB in low-alpha texels so mipmap filtering never darkens
    // semi-transparent borders toward black.
    let nr = uint8(math.Clamp(s.Needles.X * 0.82, 0, 1) * 255)
    let ng = uint8(math.Clamp(s.Needles.Y * 0.82, 0, 1) * 255)
    let nb = uint8(math.Clamp(s.Needles.Z * 0.82, 0, 1) * 255)
    for y in 0..<h {
        for x in 0..<256 {
            let i = (y * w + x) * 4
            let a = img.Pixels[i + 3]
            if a == 0 {
                img.Pixels[i] = nr
                img.Pixels[i + 1] = ng
                img.Pixels[i + 2] = nb
            } else if a < 250 {
                let inv = 255.0 / float32(a)
                img.Pixels[i] = uint8(math.Clamp(float32(img.Pixels[i]) * inv, 0, 255))
                img.Pixels[i + 1] = uint8(math.Clamp(float32(img.Pixels[i + 1]) * inv, 0, 255))
                img.Pixels[i + 2] = uint8(math.Clamp(float32(img.Pixels[i + 2]) * inv, 0, 255))
            }
        }
    }
    return img
}

// stroke fills a thin quad from (x0, y0) to (x1, y1).
func stroke(c: draw.Canvas, x0: float32, y0: float32, x1: float32, y1: float32, width: float32, color: draw.Color) {
    let dx = x1 - x0, dy = y1 - y0
    let len = math.Sqrt(dx * dx + dy * dy)
    if len < 0.01 { return }
    let nx = -dy / len * width / 2, ny = dx / len * width / 2
    var p = draw.Path()
    p.MoveTo(x0 + nx, y0 + ny)
    p.LineTo(x1 + nx, y1 + ny)
    p.LineTo(x1 - nx, y1 - ny)
    p.LineTo(x0 - nx, y0 - ny)
    p.Close()
    c.FillPath(p, color)
}
