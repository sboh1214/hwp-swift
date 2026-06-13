import Foundation
#if canImport(UIKit)
    import UIKit
#endif
#if canImport(AppKit)
    import AppKit
#endif
#if canImport(SwiftUI)
    import SwiftUI
#endif

public struct HwpColor: HwpPrimitive {
    public let red: Int
    public let green: Int
    public let blue: Int
}

public extension HwpColor {
    internal init() {
        red = 0
        green = 0
        blue = 0
    }

    init(_ data: COLORREF) {
        var reader = BitsReader(from: data)
        // reader.readBits(8)
        red = reader.readInt(8)
        green = reader.readInt(8)
        blue = reader.readInt(8)
    }

    init(_ red: Int, _ green: Int, _ blue: Int) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public extension HwpColor {
    #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
        @available(iOS 13.0, *)
        var cgColor: CGColor {
            let red = CGFloat(red) / CGFloat(255)
            let green = CGFloat(green) / CGFloat(255)
            let blue = CGFloat(blue) / CGFloat(255)
            let alpha = CGFloat(1)
            return CGColor(red: red, green: green, blue: blue, alpha: alpha)
        }
    #endif

    #if canImport(UIKit)
        var uiColor: UIColor {
            let red = CGFloat(red) / CGFloat(255)
            let green = CGFloat(green) / CGFloat(255)
            let blue = CGFloat(blue) / CGFloat(255)
            let alpha = CGFloat(1)
            return UIColor(red: red, green: green, blue: blue, alpha: alpha)
        }
    #endif

    #if canImport(AppKit)
        var nsColor: NSColor {
            NSColor(cgColor: cgColor)!
        }
    #endif

    #if canImport(SwiftUI)
        @available(iOS 13.0, OSX 10.15, *)
        func color(colorSpace: Color.RGBColorSpace = .sRGB) -> Color {
            let red = Double(red) / Double(255)
            let green = Double(green) / Double(255)
            let blue = Double(blue) / Double(255)
            let opacity = Double(1)
            return Color(colorSpace, red: red, green: green, blue: blue, opacity: opacity)
        }
    #endif
}
