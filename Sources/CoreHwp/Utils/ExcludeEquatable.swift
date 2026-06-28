import Foundation

@propertyWrapper
public struct ExcludeEquatable<Value: HwpPrimitive>: HwpPrimitive {
    public var wrappedValue: Value

    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    public static func == (_: ExcludeEquatable<Value>, _: ExcludeEquatable<Value>) -> Bool {
        true
    }

    public func hash(into _: inout Hasher) {}
}
