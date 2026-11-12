import CoreGraphics
import MetalSprocketsAddOnsShaders
import simd
import SwiftMesh

internal struct Vertex {
    // periphery:ignore - used in Metal shader
    var position: SIMD3<Float>
    // periphery:ignore - used in Metal shader
    var color: SIMD4<Float>
}

internal struct GeometryGenerator {
    let viewProjections: [float4x4]
    let viewport: SIMD2<Float>

    init(viewProjection: float4x4, viewport: SIMD2<Float>) {
        self.init(viewProjections: [viewProjection], viewport: viewport)
    }

    init(viewProjections: [float4x4], viewport: SIMD2<Float>) {
        self.viewProjections = viewProjections
        self.viewport = viewport
    }

    /// Estimated on-screen length of the Bézier curve with these control points (endpoints first and last), in the view
    /// that sees it largest, so every view gets enough segments.
    private func estimateCurveScreenLength(_ controlPoints: [SIMD3<Float>]) -> Float {
        let lengths: [Float] = viewProjections.map { viewProjection in
            let clipPoints = controlPoints.map { viewProjection * SIMD4<Float>($0, 1.0) }
            guard clipPoints.allSatisfy({ abs($0.w) > 1e-6 }) else {
                return 0
            }
            let screenPoints = clipPoints.map { SIMD2<Float>(($0.x / $0.w * 0.5 + 0.5) * viewport.x, ($0.y / $0.w * 0.5 + 0.5) * viewport.y) }
            let chordLength = distance(screenPoints[0], screenPoints[screenPoints.count - 1])
            let controlLength = zip(screenPoints, screenPoints.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
            return (chordLength + controlLength) / 2
        }
        return lengths.max() ?? 0
    }

    /// Curve tessellation depends on screen length, so only curved paths depend on the view projection and viewport.
    internal static func hasCurves(_ path: Path3D) -> Bool {
        path.getElements().contains { element in
            switch element {
            case .quadCurve, .curve:
                true
            default:
                false
            }
        }
    }

    /// Number of line segments to approximate a curve of the given on-screen length.
    internal static func segmentCount(forScreenLength screenLength: Float) -> Int {
        let pixelsPerSegment: Float = 4.0
        return max(8, min(64, Int(ceil(screenLength / pixelsPerSegment))))
    }

    internal func subdivideQuadCurve(from p0: SIMD3<Float>, to p2: SIMD3<Float>, control p1: SIMD3<Float>) -> [SIMD3<Float>] {
        let screenLength = estimateCurveScreenLength([p0, p1, p2])
        let segmentCount = Self.segmentCount(forScreenLength: screenLength)

        var points: [SIMD3<Float>] = []
        for i in 1...segmentCount {
            let t = Float(i) / Float(segmentCount)
            let mt = 1 - t
            let point = mt * mt * p0 + 2 * mt * t * p1 + t * t * p2
            points.append(point)
        }
        return points
    }

    internal func subdivideCubicCurve(from p0: SIMD3<Float>, to p3: SIMD3<Float>, control1 p1: SIMD3<Float>, control2 p2: SIMD3<Float>) -> [SIMD3<Float>] {
        let screenLength = estimateCurveScreenLength([p0, p1, p2, p3])
        let segmentCount = Self.segmentCount(forScreenLength: screenLength)

        var points: [SIMD3<Float>] = []
        for i in 1...segmentCount {
            let t = Float(i) / Float(segmentCount)
            let mt = 1 - t
            let point = mt * mt * mt * p0 + 3 * mt * mt * t * p1 + 3 * mt * t * t * p2 + t * t * t * p3
            points.append(point)
        }
        return points
    }

    func generateFillGeometry(path: Path3D, color: SIMD4<Float>) -> [Vertex] {
        let points = extractPoints(from: path)
        guard points.count >= 3 else {
            fatalError("Fill requires at least 3 points, got \(points.count)")
        }

        // SwiftMesh projects onto the plane closest to the polygon's normal, so XZ/YZ paths work.
        // Positions stay in world space; the vertex shader projects so the GPU clips against the near plane.
        return triangulatePolygon(outer: points).flatMap { triangle in
            [triangle.x, triangle.y, triangle.z].map { Vertex(position: points[$0], color: color) }
        }
    }

    internal func extractPoints(from path: Path3D) -> [SIMD3<Float>] {
        var points: [SIMD3<Float>] = []
        var currentPoint: SIMD3<Float>?

        for element in path.getElements() {
            switch element {
            case .move(let to):
                currentPoint = to
                points.append(to)
            case .line(let to):
                guard currentPoint != nil else {
                    fatalError("Line command without preceding move command")
                }
                points.append(to)
                currentPoint = to
            case let .quadCurve(to, control):
                guard let from = currentPoint else {
                    fatalError("Curve command without preceding move command")
                }
                let curvePoints = subdivideQuadCurve(from: from, to: to, control: control)
                points.append(contentsOf: curvePoints)
                currentPoint = to
            case let .curve(to, control1, control2):
                guard let from = currentPoint else {
                    fatalError("Curve command without preceding move command")
                }
                let curvePoints = subdivideCubicCurve(from: from, to: to, control1: control1, control2: control2)
                points.append(contentsOf: curvePoints)
                currentPoint = to
            case .closeSubpath:
                break
            }
        }

        return points
    }

    private func generateJoinDataForSubpath(segments: [(start: SIMD3<Float>, end: SIMD3<Float>)], isLoop: Bool, lineWidth: Float, joinStyleValue: UInt32, capStyleValue: UInt32, color: SIMD4<Float>, miterLimit: Float) -> [LineJoinGPUData] {
        guard !segments.isEmpty else {
            return []
        }

        var joinData: [LineJoinGPUData] = []
        let pointCount = isLoop ? segments.count : segments.count + 1

        for i in 0..<pointCount {
            let prevPoint: SIMD3<Float>
            let joinPoint: SIMD3<Float>
            let nextPoint: SIMD3<Float>
            let isStartCap: UInt32
            let isEndCap: UInt32

            if i == 0, !isLoop {
                // Start cap
                joinPoint = segments[0].start
                prevPoint = joinPoint  // Dummy, not used for start cap
                nextPoint = segments[0].end
                isStartCap = 1
                isEndCap = 0
            } else if i == segments.count, !isLoop {
                // End cap
                joinPoint = segments[segments.count - 1].end
                prevPoint = segments[segments.count - 1].start
                nextPoint = joinPoint  // Dummy, not used for end cap
                isStartCap = 0
                isEndCap = 1
            } else {
                // Interior join - connecting two segments
                let incomingSegIndex = isLoop ? (i == 0 ? segments.count - 1 : i - 1) : (i - 1)
                let outgoingSegIndex = isLoop ? i : i

                joinPoint = segments[incomingSegIndex].end
                prevPoint = segments[incomingSegIndex].start
                nextPoint = segments[outgoingSegIndex].end
                isStartCap = 0
                isEndCap = 0
            }

            joinData.append(LineJoinGPUData(
                prevPoint: prevPoint,
                joinPoint: joinPoint,
                nextPoint: nextPoint,
                lineWidth: lineWidth,
                joinStyle: joinStyleValue,
                capStyle: capStyleValue,
                isStartCap: isStartCap,
                isEndCap: isEndCap,
                color: color,
                miterLimit: miterLimit,
                _padding: (0, 0, 0)
            ))
        }

        return joinData
    }

    func generateLineJoinGPUData(path: Path3D, color: SIMD4<Float>, style: StrokeStyle) -> [LineJoinGPUData] {
        var joinData: [LineJoinGPUData] = []
        let lineWidth = Float(style.lineWidth)
        let elements = path.getElements()

        let joinStyleValue: UInt32 = switch style.lineJoin {
        case .miter: 0
        case .round: 1
        case .bevel: 2
        @unknown default: 0
        }

        let capStyleValue: UInt32 = switch style.lineCap {
        case .butt: 1
        case .round: 2
        case .square: 3
        @unknown default: 1
        }

        var currentPoint: SIMD3<Float>?
        var subpathStart: SIMD3<Float>?
        var segments: [(start: SIMD3<Float>, end: SIMD3<Float>)] = []
        var isLoop = false

        func processCurrentSubpath() {
            if !segments.isEmpty {
                let subpathJoinData = generateJoinDataForSubpath(
                    segments: segments,
                    isLoop: isLoop,
                    lineWidth: lineWidth,
                    joinStyleValue: joinStyleValue,
                    capStyleValue: capStyleValue,
                    color: color,
                    miterLimit: Float(style.miterLimit)
                )
                joinData.append(contentsOf: subpathJoinData)
                segments = []
                isLoop = false
            }
        }

        for element in elements {
            switch element {
            case .move(let to):
                // Process previous subpath if any
                processCurrentSubpath()
                currentPoint = to
                subpathStart = to
            case .line(let to):
                guard let from = currentPoint else {
                    fatalError("Line command without preceding move command")
                }
                segments.append((start: from, end: to))
                currentPoint = to
            case let .quadCurve(to, control):
                guard let from = currentPoint else {
                    fatalError("Curve command without preceding move command")
                }
                let curvePoints = subdivideQuadCurve(from: from, to: to, control: control)
                var segmentStart = from
                for segmentEnd in curvePoints {
                    segments.append((start: segmentStart, end: segmentEnd))
                    segmentStart = segmentEnd
                }
                currentPoint = to
            case let .curve(to, control1, control2):
                guard let from = currentPoint else {
                    fatalError("Curve command without preceding move command")
                }
                let curvePoints = subdivideCubicCurve(from: from, to: to, control1: control1, control2: control2)
                var segmentStart = from
                for segmentEnd in curvePoints {
                    segments.append((start: segmentStart, end: segmentEnd))
                    segmentStart = segmentEnd
                }
                currentPoint = to
            case .closeSubpath:
                if let from = currentPoint, let start = subpathStart, from != start {
                    segments.append((start: from, end: start))
                }
                isLoop = true
            }
        }

        // Process final subpath
        processCurrentSubpath()

        return joinData
    }
}
