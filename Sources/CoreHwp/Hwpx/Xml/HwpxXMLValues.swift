import Foundation

/// OWPML 속성 값의 typed 리더.
///
/// 규약: **필수** 속성은 부재·형식 오류에 `HwpError.invalidXML`을 던지고,
/// **선택** 속성은 기본값을 명시해 조용히 대체한다 — 무엇이 기본값으로
/// 덮였는지가 호출부에 드러나는 것이 바이너리 loader의 EOF 강제에 해당하는
/// XML 쪽 규율이다. 형식이 틀린 선택 속성도 기본값으로 대체한다 (제3자
/// 저장기의 이형 값이 문서 전체를 죽이지 않게 — 복구 모드와 같은 태도).
extension HwpxXMLNode {
    func requiredAttribute(_ name: String, entry: String) throws -> String {
        guard let value = attributes[name] else {
            throw HwpError.invalidXML(
                entry: entry,
                reason: "<\(localName)> is missing required attribute '\(name)'"
            )
        }
        return value
    }

    func requiredIntAttribute(_ name: String, entry: String) throws -> Int {
        let raw = try requiredAttribute(name, entry: entry)
        guard let value = Int(raw) else {
            throw HwpError.invalidXML(
                entry: entry,
                reason: "<\(localName)> attribute '\(name)' is not an integer: '\(raw)'"
            )
        }
        return value
    }

    func attribute(_ name: String) -> String? {
        attributes[name]
    }

    func intAttribute(_ name: String, default defaultValue: Int = 0) -> Int {
        attributes[name].flatMap(Int.init) ?? defaultValue
    }

    func uint32Attribute(_ name: String, default defaultValue: UInt32 = 0) -> UInt32 {
        attributes[name].flatMap(UInt32.init) ?? defaultValue
    }

    func int32Attribute(_ name: String, default defaultValue: Int32 = 0) -> Int32 {
        attributes[name].flatMap(Int32.init) ?? defaultValue
    }

    func uint16Attribute(_ name: String, default defaultValue: UInt16 = 0) -> UInt16 {
        attributes[name].flatMap(UInt16.init) ?? defaultValue
    }

    /// OWPML 불리언은 `0`/`1`이 기본이고 일부 저장기는 `true`/`false`를 쓴다.
    func boolAttribute(_ name: String, default defaultValue: Bool = false) -> Bool {
        switch attributes[name]?.lowercased() {
        case "1", "true":
            true
        case "0", "false":
            false
        default:
            defaultValue
        }
    }

    /// `#RRGGBB` 색상. `none`과 형식 오류는 nil이다.
    func colorAttribute(_ name: String) -> HwpColor? {
        guard let raw = attributes[name], raw.hasPrefix("#"), raw.count == 7,
              let value = UInt32(raw.dropFirst(), radix: 16)
        else {
            return nil
        }
        return HwpColor(
            Int((value >> 16) & 0xFF),
            Int((value >> 8) & 0xFF),
            Int(value & 0xFF)
        )
    }
}
