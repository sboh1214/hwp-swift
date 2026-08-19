import SwiftUI

public struct HwpPageNavigator: View {
    private let currentPage: Binding<Int>
    private let totalPages: Int

    public init(currentPage: Binding<Int>, totalPages: Int) {
        self.currentPage = currentPage
        self.totalPages = totalPages
    }

    public var body: some View {
        HStack {
            Button(LocalizedStringKey("-"), action: decrementPage)
                .disabled(currentPage.wrappedValue <= 1)
                .accessibilityLabel(previousPageAccessibilityLabel)

            Text(pageText)

            Button(LocalizedStringKey("+"), action: incrementPage)
                .disabled(currentPage.wrappedValue >= totalPages)
                .accessibilityLabel(nextPageAccessibilityLabel)
        }
    }

    // MARK: - VoiceOver 라벨 (#79)

    // `String` 인 이유와 한국어 정책은 `HwpZoomControls` 의 같은 절 주석 참조.
    // `HwpZoomControls` 의 `-`/`+` 와 뜻이 달라 라벨도 상호 구별된다.

    var previousPageAccessibilityLabel: String {
        "이전 쪽"
    }

    var nextPageAccessibilityLabel: String {
        "다음 쪽"
    }

    func decrementPage() {
        guard currentPage.wrappedValue > 1 else { return }
        currentPage.wrappedValue -= 1
    }

    func incrementPage() {
        guard currentPage.wrappedValue < totalPages else { return }
        currentPage.wrappedValue += 1
    }

    private var pageText: LocalizedStringKey {
        "Page \(currentPage.wrappedValue) of \(totalPages)"
    }
}
