# 图标设计

以“脚本卡片 + 可视化列表 + Shell 提示符”为核心：叠放的文档代表脚本库，窗口左侧的列表和高亮项代表可视化管理，右侧大号 `>_` 代表执行 Shell 脚本。采用与 macOS Dock 相适应的圆角方形、柔和立体材质和透明外围。

使用内置 image_gen 生成概念与边缘修订。原始输出保留为 `AppIcon-original.png`。最终 `AppIcon.png` 使用本地 Pillow 清除透明区域低于等于 8/255 的残余透明度，并用 Lanczos 缩放为 1024 × 1024；后续尺寸缩放由系统 `sips` 完成，再由 `Scripts/pack-icon.py` 使用 Python 标准库将 PNG 表示打包为 ICNS，不再重新生成图片。所有变体从同一母版导出。

## 生成提示词

Use case: logo-brand. Asset type: production macOS app icon, single square 1024x1024 PNG with transparent pixels outside the icon. Primary request: design an elegant memorable icon for a native visual Shell script library and execution manager. Core metaphor: a compact terminal window in front of two neatly stacked script cards; the front window combines a small visual list of three script rows on its left with one large clear >_ terminal prompt on its right, communicating visual organization plus Shell execution immediately. Style: premium macOS dock icon, carefully crafted soft dimensional surfaces with subtle bevels and soft shadows, restrained luminous accent, precise generous geometry, sophisticated and calm. Composition: centered rounded-square app tile, fully visible with consistent generous transparent margin, front-facing with very slight depth, strong silhouette, sparse large shapes that remain recognizable at 32px. Terminal prompt is the dominant mark; three short rows and tiny rounded selection indicator are the only secondary details. No words, no letters other than the literal terminal symbol >_, no tiny code, no arrows or badges, no photographic background, no mockup scene, no outer frame, no watermark. Deliver only the finished single app icon, true alpha transparency outside its rounded tile.

## 边缘修订提示词

Use case: precise-object-edit. Edit this macOS app icon. Change only the transparency cleanup: remove every stray blue/cyan speck and all detached noise floating outside the main rounded-square icon, especially the artifacts above the top edge. Make the exterior fully transparent with a clean smooth anti-aliased silhouette. Preserve the complete central design exactly: same stacked shell script cards, terminal window, >_ prompt, selected list row, colors, materials, spacing and soft dimensional shading. Do not add any new elements, text, border or background. Keep the entire rounded-square icon intact with transparent margin on all sides. Return a single clean production PNG app icon with true alpha transparency.

## 转换

```bash
bash ScriptDeck/Scripts/make-icon.sh
```

输出 `Assets/AppIcon.icns`，包含 16、32、64、128、256、512、1024 像素的标准与 Retina 图标。`build.sh` 会自动调用转换脚本、复制图标到 App Resources，并在 Info.plist 注册图标。
