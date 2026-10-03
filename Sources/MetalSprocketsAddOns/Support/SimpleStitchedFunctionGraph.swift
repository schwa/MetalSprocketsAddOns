import Metal
import MetalSprockets
import MetalSprocketsSupport
import MetalSupport

public struct SimpleStitchedFunctionGraph {
    public var stitchedFunctions: [VisibleFunction]

    public init(name: String, function: VisibleFunction, inputs: Int) throws {
        let function = function.function
        let device = _MTLCreateSystemDefaultDevice()
        let inputs = (0..<inputs).map { MTLFunctionStitchingInputNode(argumentIndex: $0) }
        let node = MTLFunctionStitchingFunctionNode(name: function.name, arguments: inputs, controlDependencies: [])
        let graph = MTLFunctionStitchingGraph(functionName: name, nodes: [node], outputNode: node, attributes: [])
        let stitchedLibraryDescriptor = MTLStitchedLibraryDescriptor(functions: [function], functionGraphs: [graph])
        let stitchedLibrary = try device.makeLibrary(stitchedDescriptor: stitchedLibraryDescriptor)
        stitchedFunctions = [
            try VisibleFunction(ShaderFunction(library: stitchedLibrary, name: name, type: .visible))
        ]
    }

    public var linkedFunctions: [VisibleFunction] {
        stitchedFunctions
    }
}

private extension MTLStitchedLibraryDescriptor {
    convenience init(functions: [MTLFunction], functionGraphs: [MTLFunctionStitchingGraph]) {
        self.init()
        self.functions = functions
        self.functionGraphs = functionGraphs
    }
}
