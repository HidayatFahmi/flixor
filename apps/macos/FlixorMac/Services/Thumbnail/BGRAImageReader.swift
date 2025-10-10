//
//  BGRAImageReader.swift
//  FlixorMac
//
//  Converts BGRA raw pixel data to NSImage
//

import Foundation
import AppKit
import CoreGraphics

/// Utility for reading BGRA formatted image data
class BGRAImageReader {
    // MARK: - Public Methods

    /// Load an image from a BGRA file
    /// - Parameters:
    ///   - path: File path to the BGRA raw data
    ///   - width: Image width in pixels
    ///   - height: Image height in pixels
    /// - Returns: NSImage if successful, nil otherwise
    static func loadImage(from path: String, width: Int, height: Int) -> NSImage? {
        guard width > 0, height > 0 else {
            print("❌ [BGRAReader] Invalid dimensions: \(width)x\(height)")
            return nil
        }

        // Read raw BGRA data from file
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            print("❌ [BGRAReader] Failed to read file: \(path)")
            return nil
        }

        // BGRA format: 4 bytes per pixel (Blue, Green, Red, Alpha)
        let bytesPerPixel = 4
        let expectedBytes = width * height * bytesPerPixel

        // Verify data size (must have at least expected bytes)
        guard data.count >= expectedBytes else {
            print("❌ [BGRAReader] Insufficient data: expected \(expectedBytes), got \(data.count)")
            return nil
        }

        if data.count != expectedBytes {
            print("⚠️ [BGRAReader] Data size mismatch: expected \(expectedBytes), got \(data.count) - proceeding anyway")
        }

        // Create CGImage from BGRA data
        guard let image = createCGImage(from: data, width: width, height: height) else {
            print("❌ [BGRAReader] Failed to create CGImage")
            return nil
        }

        // Convert to NSImage
        let nsImage = NSImage(cgImage: image, size: NSSize(width: width, height: height))

        print("✅ [BGRAReader] Loaded image: \(width)x\(height) (\(data.count) bytes)")
        return nsImage
    }

    /// Load an image from BGRA Data object
    /// - Parameters:
    ///   - data: BGRA pixel data
    ///   - width: Image width in pixels
    ///   - height: Image height in pixels
    /// - Returns: NSImage if successful, nil otherwise
    static func loadImage(from data: Data, width: Int, height: Int) -> NSImage? {
        guard width > 0, height > 0 else {
            print("❌ [BGRAReader] Invalid dimensions: \(width)x\(height)")
            return nil
        }

        guard let image = createCGImage(from: data, width: width, height: height) else {
            print("❌ [BGRAReader] Failed to create CGImage")
            return nil
        }

        return NSImage(cgImage: image, size: NSSize(width: width, height: height))
    }

    // MARK: - Private Methods

    /// Create a CGImage from BGRA pixel data
    private static func createCGImage(from data: Data, width: Int, height: Int) -> CGImage? {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bitsPerComponent = 8

        // Create data provider
        guard let provider = CGDataProvider(data: data as CFData) else {
            print("❌ [BGRAReader] Failed to create data provider")
            return nil
        }

        // Create color space (sRGB)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        // BGRA format bitmap info:
        // - premultipliedFirst: Alpha is premultiplied and comes first (BGRA order)
        // - byteOrder32Little: Little-endian byte order (BGRA = B is first byte)
        let bitmapInfo = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.premultipliedFirst.rawValue |
            CGBitmapInfo.byteOrder32Little.rawValue
        )

        // Create CGImage
        let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bytesPerPixel * 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )

        return cgImage
    }
}
