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
                .accessibilityLabel(zoomOutAccessibilityLabel)

            Text(zoomText)

            Button(LocalizedStringKey("+"), action: zoomIn)
                .disabled(zoomScale.wrappedValue >= range.upperBound)
                .accessibilityLabel(zoomInAccessibilityLabel)

            Button(LocalizedStringKey("Reset"), action: resetZoom)
                .accessibilityLabel(resetZoomAccessibilityLabel)

            if fitZoom != nil {
                Button(LocalizedStringKey("Fit Width")) { requestFit(.width) }
                    .accessibilityLabel(fitWidthAccessibilityLabel)
                Button(LocalizedStringKey("Fit Page")) { requestFit(.page) }
                    .accessibilityLabel(fitPageAccessibilityLabel)
            }
        }
    }

    // MARK: - VoiceOver 라벨 (#79)

    // `-`·`+` 는 문장부호라 VoiceOver 가 문맥 없이 읽는다. `LocalizedStringKey`
    // 는 키 문자열을 꺼낼 공개 경로가 없어 문구를 테스트로 고정할 수 없으므로
    // `String` 계산 프로퍼티로 낸다 — 문구는 한국어다 (#78 1번 에러 한국어화와
    // 같은 정책: 로컬라이제이션 인프라가 없어 하드코딩이 유일한 경로다).

    var zoomOutAccessibilityLabel: String {
        "축소"
    }

    var zoomInAccessibilityLabel: String {
        "확대"
    }

    var resetZoomAccessibilityLabel: String {
        "배율 초기화"
    }

    var fitWidthAccessibilityLabel: String {
        "폭 맞춤"
    }

    var fitPageAccessibilityLabel: String {
        "쪽 맞춤"
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

    /// **쓰기 전용** 정규화 — 비-finite(NaN/±inf)는 리셋 기본값 1.0으로 폴백 후
    /// `range`로 클램프한다. Swift min/max는 NaN 비교가 전부 false라 클램프만으로는
    /// NaN이 통과한다 (R57 #2). 표시는 `displayScale`이 따로 처리한다.
    func sanitized(_ value: CGFloat) -> CGFloat {
        let finite = value.isFinite ? value : 1.0
        return min(max(finite, range.lowerBound), range.upperBound)
    }

    /// **표시 전용** 정규화 — `range`로 클램프하지 **않는다**.
    ///
    /// 배율을 정하는 것은 문서 뷰이고 그 한계(`0.25...5.0`)는 이 컴포넌트의 `range`와
    /// 다를 수 있다. `range`는 `±` 버튼의 이동 경계일 뿐 뷰를 구속할 통로가 없으므로,
    /// 표시까지 클램프하면 좁은 `range`를 넘긴 호스트에서 라벨이 실제 배율과 다른 값을
    /// 말한다 (실측: `range` 0.5...2.0에 배율 0.25 → "50%" 표시). 값이 핀치로 들어왔든
    /// 맞춤으로 들어왔든 같은 바인딩 하나를 지나므로 표시는 출처를 구분할 수 없다.
    ///
    /// 남기는 것은 트랩 방어뿐이다 — 비-finite는 1.0, `Int(_ * 100)`이 넘칠 값은
    /// `displayLimit`으로 접는다. 그 한계는 뷰의 배율 한계보다 훨씬 넓어 정상 값을
    /// 건드리지 않는다.
    func displayScale(_ value: CGFloat) -> CGFloat {
        let finite = value.isFinite ? value : 1.0
        return min(max(finite, -Self.displayLimit), Self.displayLimit)
    }

    private static let displayLimit: CGFloat = 10000

    var displayPercent: Int {
        Int(displayScale(zoomScale.wrappedValue) * 100)
    }

    private var zoomText: LocalizedStringKey {
        "Zoom \(displayPercent)%"
    }
}
