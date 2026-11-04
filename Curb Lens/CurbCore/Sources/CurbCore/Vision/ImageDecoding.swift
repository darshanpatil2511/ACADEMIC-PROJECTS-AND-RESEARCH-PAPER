import CoreGraphics
import Foundation
import ImageIO

/// Loads photos (JPEG, HEIC, PNG) as a CGImage plus the EXIF orientation needed to make them upright.
public enum ImageDecoding {
    public enum DecodeError: Error, LocalizedError {
        case unreadable

        public var errorDescription: String? { "That file isn't a photo CurbLens can read." }
    }

    public static func decode(data: Data) throws -> (CGImage, CGImagePropertyOrientation) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw DecodeError.unreadable }
        return try decode(source: source)
    }

    public static func decode(url: URL) throws -> (CGImage, CGImagePropertyOrientation) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw DecodeError.unreadable }
        return try decode(source: source)
    }

    private static func decode(source: CGImageSource) throws -> (CGImage, CGImagePropertyOrientation) {
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw DecodeError.unreadable }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let raw = (properties?[kCGImagePropertyOrientation] as? UInt32) ?? 1
        return (image, CGImagePropertyOrientation(rawValue: raw) ?? .up)
    }
}
