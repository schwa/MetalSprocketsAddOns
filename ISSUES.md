## 1: Replace histogram image comparison with GoldenImage package
status: new
priority: medium
kind: none
created: 2026-01-17T00:00:00+00:00

The test Support.swift uses a homebrew histogram-based image comparison (vImage, CoreImage, Histogram struct). Replace this with the GoldenImage package which provides PSNR-based comparison. Requires publishing GoldenImage to GitHub first, then adding it as a dependency.

---

## 2: Remove local cross-environment macros and adopt them from MetalSprockets
status: new
priority: medium
kind: task
created: 2026-04-02T18:30:29.267773+00:00

Once MetalSprockets#305 is complete, remove the locally defined cross-environment macros from `Sources/MetalSprocketsAddOnsShaders/include/Support.h` (TEXTURE2D, DEPTH2D, TEXTURECUBE, SAMPLER, BUFFER, ATTRIBUTE, MS_ENUM) and import them from MetalSprockets instead.

Blocked on MetalSprockets#305.

---

