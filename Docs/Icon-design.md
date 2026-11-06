# Icon Design

The icon combines stacked script cards, a visual list, and a large `>_` shell prompt. Cards represent the library, a highlighted list row represents visual organization, and the terminal prompt represents execution. A rounded square, soft dimensional materials, and transparent outer margin fit the macOS Dock.

The initial concept and edge cleanup used image generation. `AppIcon-original.png` preserves the original output. The final `AppIcon.png` is a 1024 × 1024 master: local Pillow processing cleared residual alpha at or below 8/255 and resized with Lanczos. All sizes derive from this master. System `sips` generates representations, and `Scripts/pack-icon.py` uses the Python standard library to package them into ICNS.

## Generation prompt

Use case: logo-brand. Asset type: production macOS app icon, single square 1024x1024 PNG with transparent pixels outside the icon. Primary request: design an elegant memorable icon for a native visual Shell script library and execution manager. Core metaphor: a compact terminal window in front of two neatly stacked script cards; the front window combines a small visual list of three script rows on its left with one large clear >_ terminal prompt on its right, communicating visual organization plus Shell execution immediately. Style: premium macOS dock icon, carefully crafted soft dimensional surfaces with subtle bevels and soft shadows, restrained luminous accent, precise generous geometry, sophisticated and calm. Composition: centered rounded-square app tile, fully visible with consistent generous transparent margin, front-facing with very slight depth, strong silhouette, sparse large shapes that remain recognizable at 32px. Terminal prompt is the dominant mark; three short rows and tiny rounded selection indicator are the only secondary details. No words, no letters other than the literal terminal symbol >_, no tiny code, no arrows or badges, no photographic background, no mockup scene, no outer frame, no watermark. Deliver only the finished single app icon, true alpha transparency outside its rounded tile.

## Edge cleanup prompt

Use case: precise-object-edit. Edit this macOS app icon. Change only the transparency cleanup: remove every stray blue/cyan speck and all detached noise floating outside the main rounded-square icon, especially the artifacts above the top edge. Make the exterior fully transparent with a clean smooth anti-aliased silhouette. Preserve the complete central design exactly: same stacked shell script cards, terminal window, >_ prompt, selected list row, colors, materials, spacing and soft dimensional shading. Do not add any new elements, text, border or background. Keep the entire rounded-square icon intact with transparent margin on all sides. Return a single clean production PNG app icon with true alpha transparency.

## Conversion

From the project root:

```bash
bash Scripts/make-icon.sh
```

The output is `Assets/AppIcon.icns`, containing standard and Retina representations from 16 to 1024 pixels. `build.sh` invokes conversion automatically, copies the icon into app resources, and registers it in `Info.plist`.
