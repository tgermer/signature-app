# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Building & Running

This is an Xcode iOS/iPadOS app. There is no command-line build script — build and run via Xcode or `xcodebuild`:

```bash
# Build (simulator)
xcodebuild -project "Signatures.xcodeproj" -scheme Signatures -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M4)" build

# Build (device — requires signing identity)
xcodebuild -project "Signatures.xcodeproj" -scheme Signatures -destination "generic/platform=iOS" build
```

There are no tests in this project. There is no linter configured.

## Architecture

**Pattern:** MVVM with SwiftUI + SwiftData.

**Single ViewModel for the whole app:** `SignatureViewModel` is the core of the app. It owns the live `PKCanvasView`, all export logic, CRUD operations, and user preferences. It is created once in `ContentView` and passed down.

**Data layer:**
- `SignatureModel` (SwiftData `@Model`) stores only relative filenames (not absolute paths). URL access goes through computed properties that prepend the current Documents directory — this prevents broken paths after app updates.
- `ExportSettings` is a plain struct persisted to `UserDefaults`, embedded in the ViewModel.
- `strokeWidth` and `strokeColor` are also persisted to `UserDefaults` directly from the ViewModel's `didSet`.

**Canvas sizing:**
- The `PKCanvasView` is set up at **2× the logical export size** (canvas = 453.544 × 226.772 pts for a 60 mm × 30 mm signature). This gives PencilKit more room to capture pressure data.
- All export code must divide by 2 (or set scale = 0.5) to convert canvas coordinates to export coordinates.
- `exportWidth`/`exportHeight` (226.772 × 113.386) are the 1× reference values used for PNG and PDF page sizing.

**Export pipeline:**
- `saveSignature()` exports all enabled formats on save.
- `regenerateMissingExports()` is called when a format toggle is turned on in Settings — it fetches all `SignatureModel` records, loads each `.drawing` file, and generates only the missing format files.
- All export helpers (`makeSVGString`, `makePDFData`, `EMFExporter`, `ZIPExporter`) operate on a `PKDrawing` value directly, not on the live canvas.

**Variable-width strokes (pressure rendering):**
SVG, PDF, and EMF all use `PKStrokePoint.size.width` (actual rendered width from Apple Pencil pressure/tilt) instead of the tool's nominal width. The approach:
1. Compute a unit tangent at each sample point using adjacent points (central difference).
2. Offset left/right by `size.width / 2` along the perpendicular to get outline edge points.
3. Build a filled closed polygon: left edge forward + flat cap + right edge backward + flat cap, then add filled circles at both endpoints for round caps.
4. Apply Q-Bézier midpoint spline to the outline edges (same technique as PencilKit's own rendering) so the polygon edges are smooth rather than faceted.

**EMFExporter:**
- Pure Swift binary MS-EMF writer, no external dependencies.
- Uses `EMR_CREATEBRUSHINDIRECT` + `EMR_SELECTOBJECT(NULL_PEN)` + `EMR_POLYGON` / `EMR_ELLIPSE` — no pen, only fill.
- Internal coordinate scale is 2.0× (908 × 454 units for 60 × 30 mm) to reduce integer-quantization artifacts. `rclFrame` stays at 0.01 mm units (5999 × 2999) for correct physical size in Word/LibreOffice.
- One Chaikin corner-cutting pass is applied to the polygon edge points for additional smoothing.

**ZIPExporter:**
- Pure Swift PKZIP writer, STORE method (no compression), no external libraries.

## Key Constants

| Constant | Value | Meaning |
|---|---|---|
| `canvasWidth/Height` | 453.544 × 226.772 pt | 2× canvas for PencilKit drawing |
| `exportWidth/Height` | 226.772 × 113.386 pt | 1× reference = 60 × 30 mm |
| `EMFExporter.scale` | 2.0 | Canvas pt → EMF internal unit |
| `EMFExporter.emfW/H` | 908 × 454 | EMF device pixel size |
| Default stroke color | RGB 49/39/129 | "HM-Standard" corporate blue |
| Default stroke width | 3.0 pt | Tool width (canvas coordinates) |

## UI Language

All user-facing strings are in **German**. Keep new UI strings in German.
