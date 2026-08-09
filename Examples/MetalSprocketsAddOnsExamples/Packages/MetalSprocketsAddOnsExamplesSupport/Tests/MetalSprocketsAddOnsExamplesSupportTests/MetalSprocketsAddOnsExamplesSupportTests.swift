@testable import MetalSprocketsAddOnsExamplesSupport
import Testing

@MainActor
@Test
func demoRegistryHasUniqueIdentifiers() {
    let ids = Demo.all.map(\.id)
    #expect(ids.count == Set(ids).count)
    #expect(!ids.isEmpty)
}
