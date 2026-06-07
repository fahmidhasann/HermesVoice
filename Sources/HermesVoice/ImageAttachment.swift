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
    /// Cap the longest edge so a pasted full-resolution screenshot doesn't blow
    /// up the request (base64 image bytes count against the model's budget).
    static let maxDimension: CGFloat = 1280

    /// Encode an `NSImage` to a downscaled PNG `data:` URL, or nil on failure.
    static func pngDataURL(from image: NSImage) -> String? {
        guard let png = pngData(from: image) else { return nil }
        return "data:image/png;base64,\(png.base64EncodedString())"
    }

    static func pngData(from image: NSImage) -> Data? {
        let scaled = downscaled(image, maxDimension: maxDimension)
        guard let tiff = scaled.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return nil }
        return png
    }

    /// Decode a `data:image/...;base64,…` URL back into an `NSImage` for display.
    static func image(fromDataURL dataURL: String) -> NSImage? {
        guard let commaIndex = dataURL.firstIndex(of: ","),
              dataURL.lowercased().hasPrefix("data:image/") else { return nil }
        let base64 = String(dataURL[dataURL.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: base64) else { return nil }
        return NSImage(data: data)
    }

    /// Proportionally shrink so the longest edge is `maxDimension`; returns the
    /// original when it's already within bounds.
    private static func downscaled(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return image }

        let scale = maxDimension / longest
        let target = NSSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let result = NSImage(size: target)
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: target),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy,
                   fraction: 1.0)
        result.unlockFocus()
        return result
    }
}
