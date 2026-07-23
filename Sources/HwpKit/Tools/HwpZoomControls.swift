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
        zoomScale.wrappedValue = sanitized(newValue)
    }

    /// 비-finite(NaN/±inf) 값은 리셋 기본값 1.0으로 폴백 후 range로 클램프한다.
    /// Swift min/max는 NaN 비교가 전부 false라 클램프만으로는 NaN이 통과한다 —
    /// 표시(Int 변환 트랩)와 쓰기(NaN 전파) 모두 이 게이트를 거친다 (R57 #2).
    func sanitized(_ value: CGFloat) -> CGFloat {
        let finite = value.isFinite ? value : 1.0
        return min(max(finite, range.lowerBound), range.upperBound)
    }

    private var zoomText: LocalizedStringKey {
        "Zoom \(Int(sanitized(zoomScale.wrappedValue) * 100))%"
    }
}
