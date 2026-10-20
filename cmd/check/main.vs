// flora/tree: species from JSON, trees grown the same for the same seed,
// three levels of detail getting lighter, an atlas with needles and gaps.
//
//     vsc run check [atlas.png]
package main

import (
    "flora/tree"
    "fs"
    "image/png"
    "math"
    "time"
)

var failures = 0

func check(_ ok: bool, _ what: string) {
    print(ok ? "ok    \(what)" : "FAIL  \(what)")
    if !ok { failures += 1 }
}

func main() -> int32 {
    let s: tree.Species
    do {
        s = try tree.DecodeSpecies(try fs.ReadText(fs.Path("data/spruce.json")))
    } catch {
        print("check: \(error)")
        return 1
    }
    check(s.Name == "spruce" && s.Whorls == 22 && abs(s.Droop - 0.45) < 1e-4, "a species reads from JSON")
    let again = try? tree.DecodeSpecies(s.Encode())
    check(again != nil && again!.Whorls == s.Whorls && again!.Needles == s.Needles, "and survives being written back")

    let t0 = time.Instant.Now()
    let a = tree.Grow(s, seed: 7)
    let ms = t0.Elapsed().AsMilliseconds()
    let b = tree.Grow(s, seed: 7), c = tree.Grow(s, seed: 8)
    check(a.LODs[0].Positions == b.LODs[0].Positions && a.LODs[0].Positions != c.LODs[0].Positions,
          "the same seed grows the same tree, another seed another")
    check(a.Height >= 13 && a.Height <= 22, "it grows within the species' heights (\(a.Height) m)")
    let v0 = a.LODs[0].VertexCount, v1 = a.LODs[1].VertexCount, v2 = a.LODs[2].VertexCount
    check(v0 > v1 * 2 && v1 > v2 * 3 && v2 < 200, "each level of detail is lighter: \(v0), \(v1), \(v2) vertices (grown in \(ms) ms)")
    var fits = true
    for lod in a.LODs {
        let bb = lod.Bounds()
        if bb.Max.Y > a.Height * 1.05 || bb.Min.Y < -0.1 || bb.Max.X > a.Width * 1.6 || bb.Min.X < -a.Width * 1.6 {
            fits = false
            print("      bounds \(bb.Min) … \(bb.Max), height \(a.Height), width \(a.Width)")
        }
    }
    check(fits, "every level stands from the ground to its height, within its width")
    var unit = true
    for lod in a.LODs { for n in lod.Normals where abs(n.Length() - 1) > 1e-3 { unit = false } }
    check(unit && a.LODs[0].Normals.count == v0 && a.LODs[0].UVs.count == v0, "normals are unit, one per vertex, with UVs")
    check(a.TrunkRadius > 0.1 && a.TrunkRadius < 0.6 && a.TrunkHeight > 1, "it has a trunk to collide with (\(a.TrunkRadius) m, bare to \(a.TrunkHeight) m)")

    let t1 = time.Instant.Now()
    let img = tree.Atlas(s)
    let ams = t1.Elapsed().AsMilliseconds()
    var needles = 0, total = 0, barkSolid = true
    for y in 0..<img.Height {
        for x in 0..<img.Width {
            let alpha = img.Pixels[(y * img.Width + x) * 4 + 3]
            if x < 256 { total += 1; if alpha > 128 { needles += 1 } }
            if x >= 256 && alpha != 255 { barkSolid = false }
        }
    }
    let cover = needles * 100 / total
    check(cover > 15 && cover < 70 && barkSolid, "the atlas has needles with gaps between (\(cover)% covered) and solid bark and far foliage (\(ams) ms)")
    let args = CommandLine.arguments
    if args.count > 1 {
        do { try fs.WriteFile(fs.Path(args[1]), png.Encode(img)) } catch { print("check: \(error)") }
    }
    _ = math.Pi
    if failures == 0 { print("all passed") } else { print("\(failures) failed") }
    return failures == 0 ? 0 : 1
}
