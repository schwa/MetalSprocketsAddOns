// VideoTexturePipeline tests. Exercises init + lifecycle. Generates a tiny test
// video file at runtime via AVAssetWriter so we can drive loadVideo/play without
// shipping a binary asset.

import AVFoundation
import CoreVideo
import Foundation
import Metal
@testable import MetalSprocketsAddOns
import MetalSprocketsSupport
import MetalSupport
import Testing

// MARK: - Init

@Test
@MainActor
func testVideoTexturePipeline_init_createsTextureCache() {
    let device = _MTLCreateSystemDefaultDevice()
    let pipeline = VideoTexturePipeline(device: device)
    // No video loaded yet; currentTexture is nil.
    #expect(pipeline.currentTexture == nil)
}

@Test
@MainActor
func testVideoTexturePipeline_pauseWithoutPlay_isSafe() {
    let device = _MTLCreateSystemDefaultDevice()
    let pipeline = VideoTexturePipeline(device: device)
    // Calling pause before play / loadVideo must not crash.
    pipeline.pause()
    #expect(pipeline.currentTexture == nil)
}

// MARK: - Tiny test video generation

/// Generate a 0.5-second test movie (1 frame at 2 fps) at the given URL using
/// AVAssetWriter. Returns the URL on success.
private func writeTestMovie(to url: URL, size: CGSize = CGSize(width: 64, height: 64)) async throws {
    if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
    }

    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let settings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: Int(size.width),
        AVVideoHeightKey: Int(size.height)
    ]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = false

    let attrs: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: Int(size.width),
        kCVPixelBufferHeightKey as String: Int(size.height)
    ]
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: attrs
    )

    guard writer.canAdd(input) else {
        throw NSError(domain: "TestMovie", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot add input"])
    }
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    // Build a single solid red frame.
    var pb: CVPixelBuffer?
    CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)
    guard let pb else {
        throw NSError(domain: "TestMovie", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot create pixel buffer"])
    }
    CVPixelBufferLockBaseAddress(pb, [])
    let ptr = CVPixelBufferGetBaseAddress(pb)!
        .assumingMemoryBound(to: UInt8.self)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
    for y in 0..<Int(size.height) {
        for x in 0..<Int(size.width) {
            let off = y * bytesPerRow + x * 4
            ptr[off + 0] = 0    // B
            ptr[off + 1] = 0    // G
            ptr[off + 2] = 255  // R
            ptr[off + 3] = 255  // A
        }
    }
    CVPixelBufferUnlockBaseAddress(pb, [])

    // Append the frame at t=0.
    while !input.isReadyForMoreMediaData {
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    adaptor.append(pb, withPresentationTime: .zero)

    input.markAsFinished()
    await writer.finishWriting()
    if writer.status != .completed {
        throw writer.error ?? NSError(domain: "TestMovie", code: 3, userInfo: [NSLocalizedDescriptionKey: "Writer did not complete"])
    }
}

// MARK: - loadVideo + pause lifecycle

@Test
@MainActor
func testVideoTexturePipeline_loadVideo_thenPause() async throws {
    let device = _MTLCreateSystemDefaultDevice()
    let pipeline = VideoTexturePipeline(device: device)

    let movieURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("VideoTexturePipelineTest-\(UUID()).mp4")
    try await writeTestMovie(to: movieURL)
    defer { try? FileManager.default.removeItem(at: movieURL) }

    try pipeline.loadVideo(url: movieURL, loopStart: 0, loopEnd: 0.5)

    // Pause is safe even when the player is loaded but never played.
    pipeline.pause()
    pipeline.pause()  // and idempotent
}
