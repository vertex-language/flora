// Package tree grows trees from species: a few numbers saying what kind
// of tree (how tall, how wide, how its branches grow) and a seed saying
// which one. A grown Tree is meshes at three levels of detail, all
// textured from one atlas this package also makes (needles, bark, far
// foliage), so a whole tree is one draw; and a trunk to collide with.
//
//     let spruce = try tree.DecodeSpecies(text)
//     let t = tree.Grow(spruce, seed: 7)       // t.LODs[0] near … [2] far
//     let atlas = tree.Atlas()                 // image.RGBA, 512 × 256
//
// It grows conifers now: whorls of branches round a straight trunk,
// shorter toward the top, each branch a droop of needle sprays (cards).
// Broadleaf trees (space colonization) come later. Pure Vertex, no gpu.
package tree

import (
    "encoding/json"
    "math"
    "math/geom"
)

/// Species is a kind of tree.
public struct Species {
    public var Name = ""
    /// Meters, the shortest and tallest a tree grows.
    public var MinHeight: float32 = 12
    public var MaxHeight: float32 = 20
    /// The trunk's radius at the ground, as a fraction of the height.
    public var Trunk: float32 = 0.017
    /// Where the lowest branches are, as a fraction of the height.
    public var CrownStart: float32 = 0.12
    /// The crown's radius at its widest, as a fraction of the height.
    public var CrownWidth: float32 = 0.2
    /// Whorls of branches up the trunk, and branches in each.
    public var Whorls = 16
    public var MinBranches = 5
    public var MaxBranches = 7
    /// Radians: how far a branch rises leaving the trunk, and how far its
    /// tip droops below level.
    public var Rise: float32 = 0.25
    public var Droop: float32 = 0.35
    /// Needle sprays along a branch, and how wide each is (a fraction of
    /// the branch's length).
    public var Sprays = 4
    public var SprayWidth: float32 = 0.55
    /// Colors (sRGB, 0…1) the atlas paints: needles and bark.
    public var Needles = geom.Vec3(0.17, 0.27, 0.19)
    public var Bark = geom.Vec3(0.33, 0.26, 0.21)

    public init() {}
}

extension Species {
    /// Encode writes the species as JSON.
    public func Encode() -> string {
        var o = json.Object()
        o["version"] = .number("1")
        o["name"] = .string(Name)
        o["minHeight"] = num(MinHeight)
        o["maxHeight"] = num(MaxHeight)
        o["trunk"] = num(Trunk)
        o["crownStart"] = num(CrownStart)
        o["crownWidth"] = num(CrownWidth)
        o["whorls"] = .number("\(Whorls)")
        o["minBranches"] = .number("\(MinBranches)")
        o["maxBranches"] = .number("\(MaxBranches)")
        o["rise"] = num(Rise)
        o["droop"] = num(Droop)
        o["sprays"] = .number("\(Sprays)")
        o["sprayWidth"] = num(SprayWidth)
        o["needles"] = .array([num(Needles.X), num(Needles.Y), num(Needles.Z)])
        o["bark"] = .array([num(Bark.X), num(Bark.Y), num(Bark.Z)])
        return json.Encode(.object(o), indent: "  ")
    }
}

/// DecodeSpecies reads a species written by Encode (or by hand; what's
/// missing keeps its default).
public func DecodeSpecies(text: string) throws -> Species {
    let v = try json.Parse(text)
    var s = Species()
    s.Name = v["name"]?.String ?? ""
    s.MinHeight = f32(v["minHeight"], s.MinHeight)
    s.MaxHeight = math.Max(s.MinHeight, f32(v["maxHeight"], s.MaxHeight))
    s.Trunk = f32(v["trunk"], s.Trunk)
    s.CrownStart = math.Clamp(f32(v["crownStart"], s.CrownStart), 0, 0.9)
    s.CrownWidth = f32(v["crownWidth"], s.CrownWidth)
    s.Whorls = max(1, int(v["whorls"]?.Int ?? int64(s.Whorls)))
    s.MinBranches = max(1, int(v["minBranches"]?.Int ?? int64(s.MinBranches)))
    s.MaxBranches = max(s.MinBranches, int(v["maxBranches"]?.Int ?? int64(s.MaxBranches)))
    s.Rise = f32(v["rise"], s.Rise)
    s.Droop = f32(v["droop"], s.Droop)
    s.Sprays = max(1, int(v["sprays"]?.Int ?? int64(s.Sprays)))
    s.SprayWidth = f32(v["sprayWidth"], s.SprayWidth)
    if let c = color(v["needles"]) { s.Needles = c }
    if let c = color(v["bark"]) { s.Bark = c }
    return s
}

func f32(v: json.Value?, fallback: float32) -> float32 {
    guard let d = v?.Double else { return fallback }
    return float32(d)
}

func num(x: float32) -> json.Value {
    return .number("\(Double(Int((x * 10000).rounded())) / 10000)")
}

func color(v: json.Value?) -> geom.Vec3? {
    guard let a = v?.Array, a.count == 3 else { return nil }
    return geom.Vec3(float32(a[0].Double ?? 0), float32(a[1].Double ?? 0), float32(a[2].Double ?? 0))
}
