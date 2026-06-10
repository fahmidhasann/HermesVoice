import AppKit

/// A pending or sent image attachment. Holds an `NSImage` for display plus the
/// `data:image/...;base64,…` URL used both to send the image to Hermes
/// (multimodal `image_url` part) and to persist it in the transcript.
struct ImageAttachment: Identifiable, Equatable {
    let id: UUID
    let image: NSImage
    let dataURL: String

    init?(image: NSImage, id: UUID = UUID()) {
        guard let url = ImageEncoder.pngDataURL(from: image) else { return nil }
        self.id = id
        self.image = image
        self.dataURL = url
    }

    /// Rebuild an attachment from a stored data URL (loading a transcript).
    init?(dataURL: String, id: UUID = UUID()) {
        guard let image = ImageEncoder.image(fromDataURL: dataURL) else { return nil }
        self.id = id
        self.image = image
        self.dataURL = dataURL
    }

    static func == (lhs: ImageAttachment, rhs: ImageAttachment) -> Bool {
        lhs.id == rhs.id && lhs.dataURL == rhs.dataURL
    }
}

/// Pure-ish AppKit helpers for converting between `NSImage` and the base64 PNG
/// data URLs that the gateway accepts (`data:image/png;base64,…`).
enum ImageEncoder {
    /// Cap the longest edge — in **pixels** — so a pasted full-resolution
    /// screenshot doesn't blow up the request (base64 image bytes count against
    /// the model's budget).
    static let maxDimension: CGFloat = 1280

    /// Encode an `NSImage` to a downscaled PNG `data:` URL, or nil on failure.
    static func pngDataURL(from image: NSImage) -> String? {
        guard let png = pngData(from: image) else { return nil }
        return "data:image/png;base64,\(png.base64EncodedString())"
    }

    /// Render the image into a PNG capped at `maxDimension` pixels on its
    /// longest edge. All math is in pixels and the draw targets an explicit
    /// `NSBitmapImageRep` (points == pixels) — `NSImage.size` is in points and
    /// `lockFocus()` rasterizes at the screen's backing scale, which on Retina
    /// produced bitmaps 2× the documented cap (4× the bytes).
    static func pngData(from image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let pixelWidth = CGFloat(cgImage.width)
        let pixelHeight = CGFloat(cgImage.height)
        let longest = max(pixelWidth, pixelHeight)
        guard longest > 0 else { return nil }

        let scale = min(1, maxDimension / longest)
        let targetWidth = max(1, Int(floor(pixelWidth * scale)))
        let targetHeight = max(1, Int(floor(pixelHeight * scale)))

        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: targetWidth,
                                         pixelsHigh: targetHeight,
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: targetWidth, height: targetHeight)

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.interpolationQuality = .high
        context.cgContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }

    /// Decode a `data:image/...;base64,…` URL back into an `NSImage` for display.
    static func image(fromDataURL dataURL: String) -> NSImage? {
        guard let commaIndex = dataURL.firstIndex(of: ","),
              dataURL.lowercased().hasPrefix("data:image/") else { return nil }
        let base64 = String(dataURL[dataURL.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: base64) else { return nil }
        return NSImage(data: data)
    }

}
