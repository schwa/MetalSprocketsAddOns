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

// MARK: - play() lifecycle

@Test
@MainActor
func testVideoTexturePipeline_secondPlayCancelsFirstUpdateLoop() {
    let device = _MTLCreateSystemDefaultDevice()
    let pipeline = VideoTexturePipeline(device: device)

    pipeline.play()
    let firstTask = pipeline.updateTask
    #expect(firstTask != nil)

    pipeline.play()
    #expect(firstTask?.isCancelled == true)
    #expect(pipeline.updateTask != firstTask)

    pipeline.pause()
    #expect(pipeline.updateTask == nil)
}

@Test
@MainActor
func testVideoTexturePipeline_deallocatesWhilePlaying() {
    weak var weakPipeline: VideoTexturePipeline?
    do {
        let device = _MTLCreateSystemDefaultDevice()
        let pipeline = VideoTexturePipeline(device: device)
        pipeline.play()
        weakPipeline = pipeline
    }
    // The update task must not keep the pipeline alive.
    #expect(weakPipeline == nil)
}

@Test
func testVideoTexturePipeline_concurrentAccessFromOffTheMainActor() async {
    // The pipeline is main-actor isolated, so callers in nonisolated contexts have to hop to the
    // main actor. Concurrent callers therefore serialize rather than racing on the shared
    // player/task storage. Run under the thread sanitizer to make a regression here visible.
    let device = _MTLCreateSystemDefaultDevice()
    let pipeline = await VideoTexturePipeline(device: device)
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<8 {
            group.addTask { await pipeline.play() }
            group.addTask { await pipeline.pause() }
        }
    }
    await pipeline.pause()
    let hasTexture = await MainActor.run { pipeline.currentTexture != nil }
    #expect(hasTexture == false)
}

// MARK: - Tiny test video generation

private enum TestMovieError: Error {
    case cannotAddInput
    case cannotCreatePixelBuffer
    case inputNeverBecameReady
    case writerFailed(status: AVAssetWriter.Status, underlying: (any Error)?)
}

/// Wait until `input` will accept more media data. Gives up after `timeout` (or as soon as the
/// writer fails) rather than spinning forever and hanging the test suite.
private func waitUntilReadyForMoreMediaData(_ input: AVAssetWriterInput, writer: AVAssetWriter, timeout: Duration = .seconds(10)) async throws {
    let deadline = ContinuousClock.now + timeout
    while !input.isReadyForMoreMediaData {
        if writer.status == .failed || writer.status == .cancelled {
            throw TestMovieError.writerFailed(status: writer.status, underlying: writer.error)
        }
        if ContinuousClock.now >= deadline {
            throw TestMovieError.inputNeverBecameReady
        }
        try await Task.sleep(for: .milliseconds(1))
    }
}

/// Generate a test movie at the given URL using AVAssetWriter, `frameCount` frames long at
/// `framesPerSecond`.
private func writeTestMovie(to url: URL, size: CGSize = CGSize(width: 64, height: 64), frameCount: Int = 1, framesPerSecond: Int32 = 30) async throws {
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
        throw TestMovieError.cannotAddInput
    }
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    // Build a single solid red frame.
    var pb: CVPixelBuffer?
    CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)
    guard let pb else {
        throw TestMovieError.cannotCreatePixelBuffer
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

    // Append the frames.
    for frame in 0..<frameCount {
        try await waitUntilReadyForMoreMediaData(input, writer: writer)
        adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: framesPerSecond))
    }

    input.markAsFinished()
    await writer.finishWriting()
    if writer.status != .completed {
        throw TestMovieError.writerFailed(status: writer.status, underlying: writer.error)
    }
}

@Test
func testWaitUntilReadyForMoreMediaData_timesOutInsteadOfHanging() async throws {
    // A writer that was never started never makes its input ready; the helper must give up.
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("WaitReadyTest-\(UUID()).mp4")
    defer { try? FileManager.default.removeItem(at: url) }
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: 64,
        AVVideoHeightKey: 64
    ])
    writer.add(input)
    #expect(input.isReadyForMoreMediaData == false)

    await #expect(throws: TestMovieError.self) {
        try await waitUntilReadyForMoreMediaData(input, writer: writer, timeout: .milliseconds(50))
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

@Test
@MainActor
func testVideoTexturePipeline_playProducesATexture() async throws {
    let device = _MTLCreateSystemDefaultDevice()
    let pipeline = VideoTexturePipeline(device: device)

    let movieURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("VideoTexturePipelineTest-\(UUID()).mp4")
    try await writeTestMovie(to: movieURL, frameCount: 30, framesPerSecond: 30)
    defer { try? FileManager.default.removeItem(at: movieURL) }

    try pipeline.loadVideo(url: movieURL, loopStart: 0, loopEnd: 0.9)
    pipeline.play()

    // Playback is real-time, so poll for the first decoded frame with a hard deadline.
    let deadline = ContinuousClock.now + .seconds(10)
    while pipeline.currentTexture == nil, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(pipeline.currentTexture != nil)
    pipeline.pause()
    #expect(pipeline.updateTask == nil)
}

// MARK: - Frame pacing

@Test
func testVideoTexturePipeline_frameIntervalTracksNominalFrameRate() {
    // Unknown frame rate falls back to the default cadence.
    #expect(VideoTexturePipeline.frameInterval(forNominalFrameRate: 0) == VideoTexturePipeline.defaultFrameInterval)
    // Otherwise: twice the video frame rate, clamped to at most 250 Hz.
    #expect(VideoTexturePipeline.frameInterval(forNominalFrameRate: 24) == .seconds(1.0 / 48))
    #expect(VideoTexturePipeline.frameInterval(forNominalFrameRate: 30) == .seconds(1.0 / 60))
    #expect(VideoTexturePipeline.frameInterval(forNominalFrameRate: 1_000) == .milliseconds(4))
}

@Test
@MainActor
func testVideoTexturePipeline_preferredFrameIntervalUsesLoadedVideo() async throws {
    let device = _MTLCreateSystemDefaultDevice()
    let pipeline = VideoTexturePipeline(device: device)

    // With no video loaded there is nothing to pace against.
    var interval = await pipeline.preferredFrameInterval()
    #expect(interval == VideoTexturePipeline.defaultFrameInterval)

    let movieURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("VideoTexturePipelineTest-\(UUID()).mp4")
    try await writeTestMovie(to: movieURL, frameCount: 10, framesPerSecond: 30)
    defer { try? FileManager.default.removeItem(at: movieURL) }

    try pipeline.loadVideo(url: movieURL, loopStart: 0, loopEnd: 0.3)
    interval = await pipeline.preferredFrameInterval()
    // With a video loaded the cadence comes from the video track's own frame rate.
    let track = try #require(await AVURLAsset(url: movieURL).loadTracks(withMediaType: .video).first)
    let rate = try await track.load(.nominalFrameRate)
    #expect(rate > 0)
    #expect(interval == VideoTexturePipeline.frameInterval(forNominalFrameRate: rate))
    #expect(interval != VideoTexturePipeline.defaultFrameInterval)
}
