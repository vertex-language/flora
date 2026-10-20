# flora

[![package: vs-package](https://img.shields.io/badge/package-vs--package-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)
[![license: MIT](https://img.shields.io/badge/license-MIT-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](LICENSE)

Plants made from rules: what `humanoid` is for people, `flora` is for
trees. A **species** is a few numbers in JSON (how tall, how wide, how its
branches grow); a seed picks one tree of it. Generated, the way SpeedTree
grows a game's trees, rather than modeled one by one. Pure Vertex, no
`gpu`.

---

## Packages

| Package | What it is |
| :--- | :--- |
| **`flora/tree`** | `Species` (`DecodeSpecies`, `Encode`): heights, trunk, where the crown starts and how wide it is, whorls, branches per whorl, rise and droop, needle sprays and their width, needle and bark colors. `Grow(species, seed:)`: a `Tree` with three levels of detail (every branch and needle spray; sprays alone on fewer branches; stacked cones), a trunk to collide with (`TrunkRadius`, `TrunkHeight`), its `Height` and `Width`. `Atlas(species)`: the texture they're all drawn from, painted by code (a needle spray with alpha, bark, far foliage), so a whole tree is one draw. Conifers now: whorls round a straight trunk, shorter toward the top, each branch a droop of crossed needle cards. |

Later: broadleaf trees (space colonization), `flora/grass`, and a
`tree-gen` tool (sliders over a species, like character-gen).

---

## Example

```vertex
import "flora/tree"

let spruce = try tree.DecodeSpecies(try fs.ReadText("data/spruce.json"))
let t = tree.Grow(spruce, seed: 7)          // t.LODs[0] near … [2] far
let atlas = tree.Atlas(spruce)              // image.RGBA, 512 × 256
```

`data/spruce.json` and `data/pine.json` are the two species azure-sky's
forest is grown from.

---

## Testing

```bash
vsc run check [atlas.png]    # species from JSON and back; the same seed the same tree; lighter levels of detail; bounds; normals; the atlas's coverage
```

A spruce of 22 whorls is about 9,000 vertices near, 800 in the middle
and 58 far, and grows in 3 ms.

---

## License

[MIT](LICENSE)
