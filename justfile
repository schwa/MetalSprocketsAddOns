# MetalSprocketsAddOns justfile
# Run `just` to see available commands

# Default recipe - show help
default:
    @just --list

# Run all tests
test *ARGS:
    swift test {{ARGS}}

# Run only FlatShader tests
test-flatshader:
    @just test --filter FlatShader

# Run a specific test by name
test-one TEST:
    @just test --filter {{TEST}}

# Build the package
build:
    swift build

# Clean build artifacts
clean:
    swift package clean
    rm -rf .build

# Update golden images from /tmp (use after verifying test output)
update-golden IMAGE:
    cp /tmp/{{IMAGE}}.png "Tests/MetalSprocketsAddOnsTests/Golden Images/{{IMAGE}}.png"
    @echo "Updated golden image: {{IMAGE}}.png"

# Update all FlatShader golden images from /tmp
update-all-golden:
    @just update-golden FlatShaderRed
    @just update-golden FlatShaderRotated
    @just update-golden FlatShaderTextured
    @just update-golden FlatShaderVertexColors

# Open golden images directory
show-golden:
    open "Tests/MetalSprocketsAddOnsTests/Golden Images"

# Open /tmp directory to see test output
show-tmp:
    open /tmp

# Run tests and open tmp if any fail
test-debug *ARGS:
    #!/usr/bin/env bash
    BUILD_DIR=$(just _build-dir)
    if ! PACKAGE_RESOURCE_BUNDLE_PATH="$BUILD_DIR" swift test {{ARGS}}; then
        echo "Tests failed, opening /tmp for inspection..."
        open /tmp
        exit 1
    fi

# Format code (if you have swift-format installed)
format:
    @echo "swift-format not configured yet"

# Generate Xcode project
xcode:
    swift package generate-xcodeproj
