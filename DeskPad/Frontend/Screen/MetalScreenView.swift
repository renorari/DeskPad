import AppKit
import CoreVideo
import Metal
import MetalPerformanceShaders

/// Shows captured frames with Metal.
///
/// Frames are drawn on the thread that delivers them, as they arrive, so nothing is
/// rendered while the virtual display is idle and the main thread is never involved.
final class MetalScreenView: NSView {
    /// Called on the main thread with the new size in pixels.
    var onDrawableSizeChange: ((CGSize) -> Void)?

    private let metalLayer = CAMetalLayer()
    private let commandQueue: MTLCommandQueue
    private let scaler: MPSImageBilinearScale
    private let textureCache: CVMetalTextureCache
    /// Frames are dropped rather than queued when the GPU falls behind.
    private let framesInFlight = DispatchSemaphore(value: 2)

    init() {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let commandQueue = device.makeCommandQueue()
        else {
            fatalError("DeskPad requires Metal.")
        }
        var textureCache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        guard let textureCache else {
            fatalError("Could not create a Metal texture cache.")
        }
        self.commandQueue = commandQueue
        self.textureCache = textureCache
        scaler = MPSImageBilinearScale(device: device)

        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        // Drawables are written by blits and compute kernels, not only by render passes.
        metalLayer.framebufferOnly = false
        metalLayer.isOpaque = true
        metalLayer.backgroundColor = NSColor.black.cgColor

        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func makeBackingLayer() -> CALayer {
        return metalLayer
    }

    override func layout() {
        super.layout()
        updateDrawableSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        metalLayer.contentsScale = window?.backingScaleFactor ?? 1
        updateDrawableSize()
    }

    var drawableSize: CGSize {
        return metalLayer.drawableSize
    }

    private func updateDrawableSize() {
        let scale = window?.backingScaleFactor ?? 1
        let size = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
        guard size.width > 0, size.height > 0, size != metalLayer.drawableSize else {
            return
        }
        metalLayer.drawableSize = size
        onDrawableSizeChange?(size)
    }

    /// Draws a frame. Can be called from any thread.
    func render(_ pixelBuffer: CVPixelBuffer) {
        guard framesInFlight.wait(timeout: .now()) == .success else {
            return
        }
        guard
            let sourceTexture = makeTexture(from: pixelBuffer),
            let source = CVMetalTextureGetTexture(sourceTexture),
            let drawable = metalLayer.nextDrawable(),
            let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            framesInFlight.signal()
            return
        }

        let destination = drawable.texture
        if source.width == destination.width, source.height == destination.height {
            // Capture already matches the window, so a plain copy is enough.
            let blit = commandBuffer.makeBlitCommandEncoder()
            blit?.copy(from: source, to: destination)
            blit?.endEncoding()
        } else {
            scaler.encode(commandBuffer: commandBuffer, sourceTexture: source, destinationTexture: destination)
        }

        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { [framesInFlight] _ in
            // Keeps the captured surface alive until the GPU is done reading it.
            withExtendedLifetime(sourceTexture) {}
            framesInFlight.signal()
        }
        commandBuffer.commit()
    }

    private func makeTexture(from pixelBuffer: CVPixelBuffer) -> CVMetalTexture? {
        var texture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            nil,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            CVPixelBufferGetWidth(pixelBuffer),
            CVPixelBufferGetHeight(pixelBuffer),
            0,
            &texture
        )
        return texture
    }
}
