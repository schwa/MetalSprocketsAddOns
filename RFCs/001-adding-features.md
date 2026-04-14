# RFC 001: Adding Features to MetalSprocketsAddOns

## Process

1. **Experiment in MetalSprocketsExamples.** New ideas start as demos/prototypes in MSE. This is the place to iterate freely without worrying about API design.
2. **Promote to AddOns if useful.** Once a technique proves its value, extract the reusable core into MetalSprocketsAddOns.
3. **Add a demo in MSE.** Every AddOn should have a corresponding demo in MetalSprocketsExamples showing how to use it.
4. **Write an RFC if complex.** Features with non-obvious design decisions, multiple implementation strategies, or significant API surface should have an RFC in `RFCs/` before or during promotion.

## API Design Principles

- **Implementation agnostic.** AddOn APIs should not bake in assumptions about how the consumer structures their renderer, scene graph, or application.
- **Minimal surface area.** Expose just enough API to be useful. Resist adding configuration for hypothetical use cases.
- **Unopinionated.** Provide building blocks, not frameworks. Let consumers compose AddOns into their own patterns.
