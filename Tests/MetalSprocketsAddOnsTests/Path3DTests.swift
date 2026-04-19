// Path3D unit tests — directly exercise mutating builders and getElements().

@testable import MetalSprocketsAddOns
import simd
import Testing

@Test
func testPath3D_emptyInit_hasNoElements() {
    let path = Path3D()
    #expect(path.getElements().isEmpty)
}

@Test
func testPath3D_builderInit_recordsElements() {
    let path = Path3D { p in
        p.move(to: [0, 0, 0])
        p.addLine(to: [1, 0, 0])
        p.closeSubpath()
    }
    let elements = path.getElements()
    #expect(elements.count == 3)
    #expect(elements[0] == .move(to: [0, 0, 0]))
    #expect(elements[1] == .line(to: [1, 0, 0]))
    #expect(elements[2] == .closeSubpath)
}

@Test
func testPath3D_addQuadCurve_recordsElement() {
    var path = Path3D()
    path.move(to: [0, 0, 0])
    path.addQuadCurve(to: [1, 1, 0], control: [0.5, 1.5, 0])
    let elements = path.getElements()
    #expect(elements.count == 2)
    if case let .quadCurve(to, control) = elements[1] {
        #expect(to == SIMD3<Float>(1, 1, 0))
        #expect(control == SIMD3<Float>(0.5, 1.5, 0))
    } else {
        Issue.record("expected .quadCurve element")
    }
}

@Test
func testPath3D_addCurve_recordsElement() {
    var path = Path3D()
    path.move(to: [0, 0, 0])
    path.addCurve(to: [1, 0, 0], control1: [0.25, 0.5, 0], control2: [0.75, 0.5, 0])
    let elements = path.getElements()
    if case let .curve(to, control1, control2) = elements[1] {
        #expect(to == SIMD3<Float>(1, 0, 0))
        #expect(control1 == SIMD3<Float>(0.25, 0.5, 0))
        #expect(control2 == SIMD3<Float>(0.75, 0.5, 0))
    } else {
        Issue.record("expected .curve element")
    }
}

@Test
func testPath3D_equality() {
    let a = Path3D { p in
        p.move(to: [0, 0, 0])
        p.addLine(to: [1, 1, 1])
    }
    let b = Path3D { p in
        p.move(to: [0, 0, 0])
        p.addLine(to: [1, 1, 1])
    }
    let c = Path3D { p in
        p.move(to: [0, 0, 0])
    }
    #expect(a == b)
    #expect(a != c)
}
