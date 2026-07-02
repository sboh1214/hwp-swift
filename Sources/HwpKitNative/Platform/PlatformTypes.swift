import CoreGraphics
import Foundation

#if os(macOS)
    import AppKit

    public typealias PlatformView = NSView
    public typealias PlatformScrollView = NSScrollView
    public typealias PlatformColor = NSColor
    public typealias PlatformImage = NSImage
    public typealias PlatformFont = NSFont

    public extension NSImage {
        convenience init(hwpCgImage: CGImage) {
            self.init(cgImage: hwpCgImage, size: .zero)
        }
    }

    public extension NSColor {
        static func hwpColor(from cgColor: CGColor) -> NSColor {
            NSColor(cgColor: cgColor) ?? .clear
        }
    }

#elseif os(iOS)
    import UIKit

    public typealias PlatformView = UIView
    public typealias PlatformScrollView = UIScrollView
    public typealias PlatformColor = UIColor
    public typealias PlatformImage = UIImage
    public typealias PlatformFont = UIFont

    public extension UIImage {
        convenience init(hwpCgImage: CGImage) {
            self.init(cgImage: hwpCgImage)
        }
    }

    public extension UIColor {
        convenience init(hwpCgColor: CGColor) {
            self.init(cgColor: hwpCgColor)
        }
    }

#endif
