import HwpKitCore
import SwiftUI

public struct HwpZoomControls: View {
    private let zoomScale: Binding<CGFloat>
    private let fitZoom: Binding<HwpZoomFit?>?
    private let range: ClosedRange<CGFloat>

    /// - Parameter fitZoom: `HwpDocumentView(fitZoom:)`와 **같은** 바인딩. 넘기지
    ///   않으면 맞춤 버튼을 아예 그리지 않는다 — 뷰에 연결되지 않은 채 눌러도
    ///   아무 일도 일어나지 않는 버튼을 내지 않기 위해서다. 배율 산식은 뷰포트를
    ///   아는 문서 뷰가 쥐고 있으므로 이 컴포넌트는 명령만 세운다.
    public init(
        zoomScale: Binding<CGFloat>,
        fitZoom: Binding<HwpZoomFit?>? = nil,
        range: ClosedRange<CGFloat> = 0.25 ... 5.0
    ) {
        self.zoomScale = zoomScale
        self.fitZoom = fitZoom
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

            if fitZoom != nil {
                Button(LocalizedStringKey("Fit Width")) { requestFit(.width) }
                Button(LocalizedStringKey("Fit Page")) { requestFit(.page) }
            }
        }
    }

    /// 명령만 세우고 끝낸다 — 실제 배율은 뷰가 정해 `zoomScale` 로 되돌려주므로
    /// 여기서 배율 라벨을 미리 바꾸지 않는다 (뷰가 못 맞추는 순간에도 라벨이
    /// 거짓말하지 않게).
    func requestFit(_ fit: HwpZoomFit) {
        fitZoom?.wrappedValue = fit
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
