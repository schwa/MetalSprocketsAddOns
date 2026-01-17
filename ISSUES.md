## 1: Replace histogram image comparison with GoldenImage package
status: new
priority: medium
kind: none
created: 2026-01-17

The test Support.swift uses a homebrew histogram-based image comparison (vImage, CoreImage, Histogram struct). Replace this with the GoldenImage package which provides PSNR-based comparison. Requires publishing GoldenImage to GitHub first, then adding it as a dependency.

---

