import SwiftUI

public struct HwpPageNavigator: View {
    private let currentPage: Binding<Int>
    private let totalPages: Int

    /// 페이지 번호 입력 초안 (#120). 바인딩에 직접 묶으면 타이핑 도중의 중간
    /// 값("1"을 거쳐 "12")마다 문서가 스크롤되므로, 초안은 뷰가 들고 커밋
    /// (Enter)에서만 바인딩에 쓴다. 판정 로직은 `commitPageEntry(_:)`가 초안을
    /// 인자로 받아 `HwpToolsTests` 관례(뷰 인스턴스로 body 밖 메서드 직접
    /// 호출)로 검증된다.
    @State private var pageFieldText = ""
    @FocusState private var pageFieldFocused: Bool

    public init(currentPage: Binding<Int>, totalPages: Int) {
        self.currentPage = currentPage
        self.totalPages = totalPages
    }

    public var body: some View {
        HStack {
            Button(LocalizedStringKey("-"), action: decrementPage)
                .disabled(currentPage.wrappedValue <= 1)
                .accessibilityLabel(previousPageAccessibilityLabel)

            Text(LocalizedStringKey("Page"))
            pageField
            Text(totalPagesText)

            Button(LocalizedStringKey("+"), action: incrementPage)
                .disabled(currentPage.wrappedValue >= totalPages)
                .accessibilityLabel(nextPageAccessibilityLabel)
        }
    }

    private var pageField: some View {
        let field = TextField(LocalizedStringKey("Page"), text: $pageFieldText)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            // 고정 폭인 이유는 `HwpSearchBar.fieldWidth`와 같다 — 넘치는 툴바를
            // 가로 ScrollView에 넣는 호스트에서 greedy 필드가 레이아웃을 무너뜨린다.
            .frame(width: 56)
            .focused($pageFieldFocused)
            .onSubmit(commitPageField)
            .accessibilityLabel(pageFieldAccessibilityLabel)
            .onAppear(perform: syncPageField)
            // 편집 중(포커스)에는 외부 쪽 변경이 초안을 덮지 않는다 — 타이핑
            // 도중 스크롤·프로그래매틱 이동이 오면 사용자의 입력이 이긴다.
            // 커밋 직후 정규화는 `commitPageField`가 직접 하므로 새지 않는다.
            .onChange(of: currentPage.wrappedValue) {
                if !pageFieldFocused {
                    syncPageField()
                }
            }
            // 포커스를 잃으면 커밋이 아니라 **되돌림**이다 — 다른 곳을 탭했을
            // 뿐인데 문서가 스크롤되면 안 된다. 커밋 통로는 Enter 하나다.
            .onChange(of: pageFieldFocused) {
                if !pageFieldFocused {
                    syncPageField()
                }
            }
        #if os(iOS)
            // 소프트웨어 키보드에서도 숫자 행과 Return(커밋 통로)이 함께 나온다
            // — `.numberPad`는 Return이 없어 커밋할 길이 사라진다.
            return field.keyboardType(.numbersAndPunctuation)
        #else
            return field
        #endif
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

    var pageFieldAccessibilityLabel: String {
        "쪽 번호 입력"
    }

    func decrementPage() {
        guard currentPage.wrappedValue > 1 else { return }
        currentPage.wrappedValue -= 1
    }

    func incrementPage() {
        guard currentPage.wrappedValue < totalPages else { return }
        currentPage.wrappedValue += 1
    }

    // MARK: - 페이지 번호 입력 확정 (#120)

    /// 입력이 숫자가 아니면 바인딩을 건드리지 않는다 — 뷰 쪽 `syncPageField`가
    /// 초안을 현재 쪽으로 되돌린다. 숫자면 `1...totalPages`로 클램프해 쓰되
    /// (`totalPages`가 0인 호스트에서도 하한 1이 서도록 `max(1, totalPages)`),
    /// 같은 값 재쓰기는 생략한다 (`handlePageChanged`의 동치 가드와 같은 성격).
    func commitPageEntry(_ text: String) {
        guard let entered = parsedPageNumber(from: text) else { return }
        let clamped = min(max(1, entered), max(1, totalPages))
        guard currentPage.wrappedValue != clamped else { return }
        currentPage.wrappedValue = clamped
    }

    /// `Int.init`은 앞뒤 공백에 nil을 주므로 사용자가 흘린 공백만 걷어 낸다.
    /// 오버플로 입력(19자리 숫자)도 nil이라 트랩 없이 무효 처리된다.
    func parsedPageNumber(from text: String) -> Int? {
        Int(text.trimmingCharacters(in: .whitespaces))
    }

    private func commitPageField() {
        commitPageEntry(pageFieldText)
        // 클램프·무효 입력으로 바인딩이 안 바뀌면 onChange가 오지 않으므로
        // 초안 정규화("999" → "3")는 여기서 직접 한다.
        syncPageField()
    }

    private func syncPageField() {
        pageFieldText = String(currentPage.wrappedValue)
    }

    private var totalPagesText: LocalizedStringKey {
        "of \(totalPages)"
    }
}
