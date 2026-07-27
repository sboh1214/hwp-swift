import SwiftUI

public struct HwpDocumentToolbar<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                content
            }
            .padding()
            .background(.regularMaterial)

            Divider()
        }
    }
}
