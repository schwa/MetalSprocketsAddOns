# Release Notes

## 0.1.7

- Bumped MetalSprockets dependency to 0.1.7.
- Imported cross-environment macros from MetalSprocketsShaders instead of maintaining local copies.
- Added missing `import OrderedCollections` to fix explicit module builds.
- Optimised edge processing in `MeshWithEdges` (capacity reservation, eliminated temporary arrays).
- Added unit tests for `MeshWithEdges` edge extraction and deduplication.
- Updated Swift tools version to 6.2 and platform version syntax.
- Added SwiftLint to CI.
- Updated GitHub Actions to Node.js 24 compatible versions.
