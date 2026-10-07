import AsyncAlgorithms
import AVFoundation
import CoreVideo
import Metal
import MetalSprockets
import MetalSprocketsSupport

/// Pipeline that renders video frames to a Metal texture.
///
/// The pipeline is isolated to the main actor: all of its mutable state (the player, the video
/// output, the update task and the current texture) is only ever touched from there, so no
/// additional synchronization is required.
@MainActor
@Observable
public class VideoTexturePipeline {
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var videoOutput: AVPlayerItemVideoOutput?
    // Internal getter so tests can observe update-task lifetime.
    private(set) var updateTask: Task<Void, Never>?
    private var endOfItemObserver: (any NSObjectProtocol)?

    /// Valid only while `currentTextureOwner` is alive. Retain the owner for each frame that samples
    /// the texture (for example with `.retainOwners([owner])`), or the texture cache can recycle the
    /// backing surface while the GPU still reads it.
    public private(set) var currentTexture: MTLTexture?

    /// The `CVMetalTexture` backing `currentTexture`.
    public private(set) var currentTextureOwner: AnyObject?
    private var textureCache: CVMetalTextureCache?

    public init(device: MTLDevice) {
        // Create texture cache for efficient video frame conversion
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        self.textureCache = cache
    }

    public func loadVideo(url: URL, loopStart: TimeInterval = 2.95, loopEnd: TimeInterval = 11.95) throws {
        // Create player item and player
        playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)

        // Configure video output for Metal textures
        let outputSettings: [String: any Sendable] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: outputSettings)
        guard let videoOutput else {
            fatalError("Failed to create video output")
        }
        playerItem?.add(videoOutput)

        // Set up looping. The notification is delivered on an unspecified queue, so hop back to
        // the main actor before touching any state.
        player?.actionAtItemEnd = .none
        if let endOfItemObserver {
            NotificationCenter.default.removeObserver(endOfItemObserver)
        }
        endOfItemObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.playerItemDidReachEnd()
            }
        }

        // Store loop points
        self.loopStart = CMTime(seconds: loopStart, preferredTimescale: 600)
        self.loopEnd = CMTime(seconds: loopEnd, preferredTimescale: 600)
    }

    private var loopStart = CMTime.zero
    private var loopEnd = CMTime.zero

    /// Fallback cadence when the video's frame rate is unknown.
    nonisolated static let defaultFrameInterval = Duration.milliseconds(16)

    /// Polling cadence for a video with the given nominal frame rate.
    ///
    /// Frames are polled at twice the video's frame rate, which bounds the latency of a new frame
    /// to half a frame interval without waking up at an arbitrary rate unrelated to the content.
    /// Very high frame rates are clamped so the loop cannot spin faster than 250 Hz.
    nonisolated static func frameInterval(forNominalFrameRate nominalFrameRate: Float) -> Duration {
        guard nominalFrameRate > 0 else {
            return defaultFrameInterval
        }
        return max(.milliseconds(4), .seconds(1.0 / (Double(nominalFrameRate) * 2)))
    }

    /// Polling cadence for the currently loaded video.
    func preferredFrameInterval() async -> Duration {
        guard let asset = playerItem?.asset else {
            return Self.defaultFrameInterval
        }
        do {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                return Self.defaultFrameInterval
            }
            return Self.frameInterval(forNominalFrameRate: try await track.load(.nominalFrameRate))
        } catch {
            return Self.defaultFrameInterval
        }
    }

    private func playerItemDidReachEnd() async {
        await player?.seek(to: loopStart)
    }

    public func play() {
        player?.play()

        // Replace any loop left over from a previous play(); otherwise each call would add another
        // concurrent frame-update loop.
        updateTask?.cancel()

        // Set up async task for frame updates, paced to the video rather than a fixed 60 Hz
        // guess. self is captured weakly so a playing pipeline can still be deallocated - deinit
        // cancels the task.
        updateTask = Task { [weak self] in
            let interval = await self?.preferredFrameInterval() ?? Self.defaultFrameInterval
            for await _ in AsyncTimerSequence(interval: interval, clock: .continuous) {
                guard let self else {
                    return
                }
                await self.updateFrame()
            }
        }
    }

    public func pause() {
        player?.pause()
        updateTask?.cancel()
        updateTask = nil
    }

    private func updateFrame() async {
        guard let videoOutput, let player else {
            return
        }

        let currentTime = player.currentTime()

        // Check for loop point
        if currentTime >= loopEnd {
            await player.seek(to: loopStart)
            return
        }

        // Get the current video frame
        guard videoOutput.hasNewPixelBuffer(forItemTime: currentTime), let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil) else {
            return
        }

        // Convert pixel buffer to Metal texture
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        guard let textureCache else {
            fatalError("Texture cache not initialized")
        }
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )

        guard status == kCVReturnSuccess, let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else {
            return
        }

        texture.label = "Video Frame Texture"
        currentTexture = texture
        currentTextureOwner = cvTexture
    }

    // Isolated so that teardown can touch the main-actor state it owns.
    isolated deinit {
        updateTask?.cancel()
        player?.pause()
        if let endOfItemObserver {
            NotificationCenter.default.removeObserver(endOfItemObserver)
        }
    }
}
