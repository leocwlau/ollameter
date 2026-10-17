# Icon assets

## App icon

**Required:** `assets/Ollameter-1024.png`

-   Size: `1024 x 1024`.
-   Format: PNG, full-color.
-   Shape: opaque square canvas.
-   Corners: square is fine; macOS masks the icon at render time.

If all sizes are prepared externally, they should follow the standard `AppIcon.iconset` names:

| File                  |          Size |
| --------------------- | ------------: |
| `icon_16x16.png`      |     `16 x 16` |
| `icon_16x16@2x.png`   |     `32 x 32` |
| `icon_32x32.png`      |     `32 x 32` |
| `icon_32x32@2x.png`   |     `64 x 64` |
| `icon_128x128.png`    |   `128 x 128` |
| `icon_128x128@2x.png` |   `256 x 256` |
| `icon_256x256.png`    |   `256 x 256` |
| `icon_256x256@2x.png` |   `512 x 512` |
| `icon_512x512.png`    |   `512 x 512` |
| `icon_512x512@2x.png` | `1024 x 1024` |

## Menu bar icon

**Required:** `assets/menu-bar-icon.png`

-   Logical size: `22 x 22` Apple points.
-   Format: PNG with an alpha channel.
-   Foreground color: solid black.
-   Background: fully transparent.
-   Template behavior: AppKit sets it as a template image and tints it to match the menu bar appearance.

An optional `assets/menu-bar-icon@2x.png` at `44 x 44` may be provided for retina detail.
