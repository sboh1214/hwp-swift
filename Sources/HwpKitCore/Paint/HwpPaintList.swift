import Foundation

public struct HwpPaintList: Sendable {
    public let commands: [HwpPaintCommand]

    public init(commands: [HwpPaintCommand]) {
        self.commands = commands
    }
}
