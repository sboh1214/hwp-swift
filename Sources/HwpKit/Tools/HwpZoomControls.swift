import SwiftUI

public struct HwpZoomControls: View {
    private let zoomScale: Binding<CGFloat>
    private let range: ClosedRange<CGFloat>

    public init(zoomScale: Binding<CGFloat>, range: ClosedRange<CGFloat> = 0.25 ... 5.0) {
        self.zoomScale = zoomScale
        self.range = range
    }

    public var body: some View {
        HStack {
            Button(LocalizedStringKey("-"), action: zoomOut)
                .disabled(zoomScale.wrappedValue <= range.lowerBound)

            Text(zoomText)

            Button(LocalizedStringKey("+"), action: zoomIn)
                .disabled(zoomScale.wrappedValue >= range.upperBound)

            Button(LocalizedStringKey("Reset"), action: resetZoom)
        }
    }

    func zoomOut() {
        setZoomScale(zoomScale.wrappedValue / 2)
    }

    func zoomIn() {
        setZoomScale(zoomScale.wrappedValue * 2)
    }

    func resetZoom() {
        setZoomScale(1.0)
    }

    func setZoomScale(_ newValue: CGFloat) {
        let clamped = min(max(newValue, range.lowerBound), range.upperBound)
        zoomScale.wrappedValue = clamped
    }

    private var zoomText: LocalizedStringKey {
        "Zoom \(Int(zoomScale.wrappedValue * 100))%"
    }
}
