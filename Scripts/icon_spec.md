# Grapfel App Icon — SVG/Artwork Specification

Use this spec to create a hand-crafted replacement icon in Figma, Illustrator, or Affinity Designer.
Export a single 1024×1024 PNG, then run `swift Scripts/generate_icon.swift` (after updating it to
use your master file instead of generating from code) — or use `sips` to resize manually.

---

## Canvas

| Property | Value |
|----------|-------|
| Size | 1024 × 1024 px |
| Color profile | sRGB |
| Background shape | Full square (macOS applies the rounded-rect mask at the OS level) |

---

## Layer 1 — Background

| Property | Value |
|----------|-------|
| Fill | Solid `#121121` (deep navy-indigo) |

---

## Layer 2 — Purple radial bloom

| Property | Value |
|----------|-------|
| Type | Radial gradient |
| Center | 512, 512 |
| Radius | 563 px (55% of 1024) |
| Color stop 0% | `#381E6F` at 80% opacity |
| Color stop 100% | `#121121` at 0% opacity (transparent) |
| Blend mode | Normal |

---

## Layer 3 — Four-pointed star (✦)

The ✦ glyph as a geometric path, NOT a text character.

| Property | Value |
|----------|-------|
| Center | 512, 512 |
| Outer radius | 379 px (37% of 1024) |
| Inner radius | 67 px (6.5% of 1024) |
| Points | 4 (8 path vertices total, alternating outer/inner) |
| Rotation | First outer point at top (−90° / 270°) |
| Fill | `#F7F5FF` (near-white with slight cool tint) |

**Vertex coordinates (1024px canvas):**

Outer points (at 0°, 90°, 180°, 270° from top):
- Top:    512, 133
- Right:  891, 512
- Bottom: 512, 891
- Left:   133, 512

Inner points (at 45°, 135°, 225°, 315° from top):
- Top-right:    559, 465   ← approx; recalculate from center±(67×cos45°, 67×sin45°)
- Bottom-right: 559, 559
- Bottom-left:  465, 559
- Top-left:     465, 465

> Tip: in Figma, use the polygon tool set to 4 points, then adjust the "ratio" (inner radius)
> to ~17.7% (67/379). Set rotation to 0° so the first point faces up.

---

## Layer 4 — Glow / outer light

| Property | Value |
|----------|-------|
| Type | Drop shadow or outer glow on the star layer |
| Color | `#C9BFFF` (soft violet) |
| Opacity | 85% |
| Blur / spread | 72 px blur, 0 px offset (pure glow, no directional shadow) |
| Blend mode | Normal |

---

## Design notes for the final version

- The interim generated icon is intentionally minimal. For final release, consider:
  - A subtle inner highlight on the star (top face slightly brighter)
  - A very faint specular rim on the background (light source from top-left)
  - Optionally replacing the flat background with a dark glass/material look
    to match macOS 26 Liquid Glass aesthetics
- Keep the star simple — the ✦ must read clearly at 16×16px (Dock small size)
- Avoid gradients on the star itself; the contrast with the dark bg is what makes it pop
- The macOS icon mask applies ~22% corner radius at display time — leave ~40px padding
  from canvas edge so the star isn't clipped at very small sizes

---

## Replacing the interim icon

Once you have a final 1024×1024 PNG:

1. Drop it into `grapfel/Resources/Assets.xcassets/AppIcon.appiconset/` as `AppIcon-master.png`
2. Run: `sips -z <px> <px> AppIcon-master.png --out AppIcon-<size>@<scale>.png` for each size,
   OR update `Scripts/generate_icon.swift` to load your PNG instead of drawing from code.
3. Rebuild in Xcode.
