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

            Text(pageText)

            Button(LocalizedStringKey("+"), action: incrementPage)
                .disabled(currentPage.wrappedValue >= totalPages)
        }
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
