package tree

import (
    "math"
    "math/geom"
    "math/rand"
    "mesh"
)

/// Where things are in the atlas (see Atlas): needle sprays on the left
/// half, bark next, far foliage at the right.
public let NeedleRegion = mesh.Rect(0, 0, 0.5, 1)
public let BarkRegion = mesh.Rect(0.5, 0, 0.75, 1)
public let FarRegion = mesh.Rect(0.75, 0, 1, 1)

/// Tree is a grown tree, its base at the origin, standing up Y.
public struct Tree {
    public var Height: float32
    /// The crown's widest radius, meters.
    public var Width: float32
    /// The trunk to collide with: a radius, and how high it's bare (a
    /// capsule from the ground to there stops a walker; the crown above is
    /// needles and lets things through).
    public var TrunkRadius: float32
    public var TrunkHeight: float32
    /// Near to far: [0] every branch and spray, [1] sprays alone on fewer
    /// branches, [2] stacked cones painted with far foliage.
    public var LODs: [mesh.Mesh]
}

/// Grow grows a tree of a species; the same seed, the same tree.
public func Grow(_ s: Species, seed: uint64) -> Tree {
    var g = rand.Xorshift128Plus(seed: seed &* 0x9E3779B97F4A7C15 &+ 1)
    func unit() -> float32 { return float32(g.Float64()) }
    let h = s.MinHeight + (s.MaxHeight - s.MinHeight) * unit()
    let r0 = s.Trunk * h
    let base = s.CrownStart * h
    let width = s.CrownWidth * h

    // The trunk: a slight lean, tapering to nothing at the top.
    let lean = geom.Vec3(unit() - 0.5, 0, unit() - 0.5) * (h * 0.012)
    var spine: [geom.Vec3] = []
    var radii: [float32] = []
    for k in 0...6 {
        let t = float32(k) / 6
        spine.append(geom.Vec3(lean.X * t * t, h * t, lean.Z * t * t))
        radii.append(r0 * (1 - t) + 0.01 * (1 - t))
    }

    // The branches: whorl by whorl, shorter toward the top.
    var branches: [branch] = []
    var turn = unit() * 6.2832
    for w in 0..<s.Whorls {
        let t = (float32(w) + unit() * 0.5) / float32(s.Whorls)
        let y = base + (h - base) * t
        let length = width * math.Pow(1 - t, 0.85) + h * 0.015
        let n = s.MinBranches + int(g.Below(uint64(s.MaxBranches - s.MinBranches + 1)))
        turn += 2.39996   // the golden angle: whorls don't line up
        for b in 0..<n {
            let a = turn + float32(b) / float32(n) * 6.2832 + (unit() - 0.5) * 0.5
            let l = length * (0.8 + unit() * 0.35)
            let at = trunkPoint(spine, y)
            // Low branches droop only as far as keeps their sprays off the ground.
            var droop = s.Droop * (0.7 + unit() * 0.6)
            let room = (y - 0.25 - l * s.SprayWidth * 0.45) / l
            droop = math.Min(droop, math.Asin(math.Clamp(room, -1, 1)))
            branches.append(branch(from: at, angle: a, length: l, rise: s.Rise, droop: droop, whorl: w))
        }
    }

    var lod0 = mesh.Sweep(spine, radii: radii, sides: 8, uv: BarkRegion, capStart: true)
    var lod1 = mesh.Sweep([spine[0], spine[3], spine[6]], radii: [radii[0], radii[3], radii[6]], sides: 5, uv: BarkRegion)
    for (i, b) in branches.enumerated() {
        let path = b.path()
        // Near: the branch's own wood, and every spray along it.
        lod0.Append(mesh.Sweep(path, radii: [b.length * 0.02 + 0.008, b.length * 0.012, 0.003], sides: 3, uv: BarkRegion))
        for k in 0..<s.Sprays {
            let f = (float32(k) + 0.6) / float32(s.Sprays)
            lod0.Append(spray(b, from: f - 0.5 / float32(s.Sprays), to: f + 0.6 / float32(s.Sprays), width: b.length * s.SprayWidth * (1 - f * 0.35)))
        }
        // Middle: three in four branches, each one long spray.
        if i % 4 != 3 { lod1.Append(spray(b, from: 0.04, to: 1.12, width: b.length * s.SprayWidth * 1.25)) }
    }
    // The leader at the top: a short upright spray.
    let tip = geom.Vec3(lean.X, h, lean.Z)
    let leader = branch(from: tip - geom.Vec3(0, h * 0.06, 0), angle: 0, length: h * 0.06, rise: 1.5, droop: 0, whorl: s.Whorls)
    lod0.Append(spray(leader, from: 0, to: 1, width: h * 0.04))
    lod1.Append(spray(leader, from: 0, to: 1, width: h * 0.05))

    // Inner crown core: 3 stacked cones painted with mottled FarRegion foliage
    // tucked inside the boughs so low-angle views never see sky/hill gaps
    // through the middle of the tree.
    var innerCore = mesh.Mesh()
    for tier in 0..<3 {
        let f0 = float32(tier) * 0.28
        let f1 = math.Min(1.0, f0 + 0.46)
        let y0 = base + (h - base) * f0
        let y1 = base + (h - base) * f1
        let rTier = width * math.Pow(1 - f0 * 0.82, 0.85) * 0.62
        innerCore.Append(cone(trunkPoint(spine, y0), height: y1 - y0, radius: rTier, sides: 6))
    }
    lod0.Append(innerCore)
    lod1.Append(innerCore)

    // Far: trunk, inner foliage core, plus half the branches as needle sprays
    // so distant trees keep organic conifer silhouettes with a solid core.
    var lod2 = mesh.Sweep([spine[0], spine[3], spine[6]], radii: [r0, radii[3], radii[6]], sides: 4, uv: BarkRegion)
    lod2.Append(innerCore)
    for (i, b) in branches.enumerated() {
        if i % 2 == 0 {
            lod2.Append(spray(b, from: 0.02, to: 1.14, width: b.length * s.SprayWidth * 1.38))
        }
    }
    lod2.Append(spray(leader, from: 0, to: 1.05, width: h * 0.055))

    lod0 = shadeCanopy(lod0, base: base, height: h, width: width, lean: lean)
    lod1 = shadeCanopy(lod1, base: base, height: h, width: width, lean: lean)
    lod2 = shadeCanopy(lod2, base: base, height: h, width: width, lean: lean)
    return Tree(Height: h, Width: width, TrunkRadius: r0 + 0.02, TrunkHeight: math.Max(base, 1), LODs: [lod0, lod1, lod2])
}

// shadeCanopy bakes volumetric ambient occlusion into vertex colors: darker
// deep inside the lower crown near the trunk, brighter at outer bough tips
// and the crown's top.
func shadeCanopy(_ m: mesh.Mesh, base: float32, height: float32, width: float32, lean: geom.Vec3) -> mesh.Mesh {
    var out = m
    out.Colors = []
    let crownH = math.Max(height - base, 0.5)
    for i in 0..<out.Positions.count {
        let p = out.Positions[i]
        let uv = i < out.UVs.count ? out.UVs[i] : geom.Vec2.Zero
        let t = math.Clamp(p.Y / math.Max(height, 0.5), 0, 1)
        if uv.X >= BarkRegion.U0 && uv.X <= BarkRegion.U1 {
            let k = 0.72 + 0.28 * t
            out.Colors.append(geom.Vec4(k, k, k, 1))
        } else {
            let ct = math.Clamp((p.Y - base) / crownH, 0, 1)
            let axisX = lean.X * t * t, axisZ = lean.Z * t * t
            let dx = p.X - axisX, dz = p.Z - axisZ
            let r = math.Sqrt(dx * dx + dz * dz)
            let expectedR = math.Max(width * math.Pow(1 - ct * 0.85, 0.85), 0.25)
            let radial = math.Clamp(r / expectedR, 0, 1)
            let ao = 0.50 + 0.32 * radial + 0.22 * ct
            out.Colors.append(geom.Vec4(ao * 0.96, ao, ao * 0.94, 1))
        }
    }
    return out
}

// branch is one branch: from a point on the trunk, out at an angle round
// it, rising then drooping.
struct branch {
    let from: geom.Vec3
    let angle: float32
    let length: float32
    let rise: float32
    let droop: float32
    let whorl: int

    var out: geom.Vec3 { return geom.Vec3(math.Sin(angle), 0, math.Cos(angle)) }

    // path is the branch's curve, base to tip.
    func path() -> [geom.Vec3] {
        let o = out
        var pts: [geom.Vec3] = []
        for k in 0...4 {
            let t = float32(k) / 4
            // Up at first, then down toward the tip: a gentle arc.
            let y = length * (math.Sin(rise) * t * (1 - t) * 1.6 - math.Sin(droop) * t * t)
            pts.append(from + o * (length * t) + geom.Vec3(0, y, 0))
        }
        return pts
    }

    // at is the point a fraction f along the branch, and its direction.
    func at(_ f: float32) -> (geom.Vec3, geom.Vec3) {
        let p = path()
        let x = math.Clamp(f, 0, 1) * 4
        let i = min(3, int(x))
        let t = x - float32(i)
        return (geom.Lerp(p[i], p[i + 1], t), (p[i + 1] - p[i]).Normalized())
    }
}

// spray is a branch's needles from f0 to f1 along it: a flat card laid
// along the branch, and a second tilted card crossing it, so it has body
// from the side. Normals lean out from the trunk and up, so the crown
// shades as a whole rather than card by card.
func spray(_ b: branch, from f0: float32, to f1: float32, width: float32) -> mesh.Mesh {
    let (a, _) = b.at(f0)
    let (c, dir) = b.at(math.Min(f1, 1))
    let end = f1 > 1 ? c + dir * (b.length * (f1 - 1)) : c
    var along = end - a
    if along.LengthSquared() < 1e-6 { along = b.out * 0.1 }
    let fwd = along.Normalized()
    var side = fwd.Cross(geom.Vec3.UnitY)
    if side.LengthSquared() < 1e-6 { side = geom.Vec3.UnitX }
    side = side.Normalized()
    let flatUp = side.Cross(fwd).Normalized()
    let soft = (b.out * 0.55 + geom.Vec3(0, 0.75, 0)).Normalized()
    var m = mesh.Mesh()
    // Two cards: flat, and turned 60° about the branch.
    let tilt = (flatUp * 0.5 + side * 0.866).Normalized()
    for (k, across) in [side, tilt].enumerated() {
        let w = across * (width / 2)
        let lift = k == 0 ? geom.Vec3(0, width * 0.06, 0) : geom.Vec3.Zero
        var card = mesh.Quad(a - w + lift, end - w + lift, end + w + lift, a + w + lift, uv: NeedleRegion)
        // The card's own facing, softened toward out-and-up.
        let face = across.Cross(fwd).Normalized()
        let n = (face * (face.Y < 0 ? -0.35 : 0.35) + soft).Normalized()
        card.Normals = [n, n, n, n]
        // Along the card is U in the texture (the twig runs left to right).
        card.UVs = [geom.Vec2(NeedleRegion.U0, NeedleRegion.V1), geom.Vec2(NeedleRegion.U1, NeedleRegion.V1),
                    geom.Vec2(NeedleRegion.U1, NeedleRegion.V0), geom.Vec2(NeedleRegion.U0, NeedleRegion.V0)]
        m.Append(card)
    }
    return m
}

// cone is a cone's side from a base center up `height`, open at the
// bottom, painted with far foliage.
func cone(_ at: geom.Vec3, height: float32, radius: float32, sides: int) -> mesh.Mesh {
    var m = mesh.Mesh()
    let top = at + geom.Vec3(0, height, 0)
    let slope = radius / math.Max(height, 0.01)
    for s in 0...sides {
        let a = float32(s) / float32(sides) * 6.2832
        let o = geom.Vec3(math.Sin(a), 0, math.Cos(a))
        let n = (o + geom.Vec3(0, slope, 0)).Normalized()
        let u = FarRegion.U0 + (FarRegion.U1 - FarRegion.U0) * float32(s) / float32(sides)
        m.Positions.append(at + o * radius)
        m.Normals.append(n)
        m.UVs.append(geom.Vec2(u, FarRegion.V1))
        m.Positions.append(top)
        m.Normals.append(n)
        m.UVs.append(geom.Vec2(u, FarRegion.V0))
    }
    for s in 0..<sides {
        let a = uint32(s * 2)
        m.Indices += [a, a + 2, a + 1, a + 1, a + 2, a + 3]
    }
    return m
}

// trunkPoint is the point on the trunk's spine at height y.
func trunkPoint(_ spine: [geom.Vec3], _ y: float32) -> geom.Vec3 {
    for i in 1..<spine.count where spine[i].Y >= y {
        let a = spine[i - 1], b = spine[i]
        return geom.Lerp(a, b, (y - a.Y) / math.Max(b.Y - a.Y, 1e-6))
    }
    return spine[spine.count - 1]
}
