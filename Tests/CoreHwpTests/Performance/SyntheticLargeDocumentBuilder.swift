@testable import CoreHwp
import Foundation

/// 성능 계측용 합성 대형 BodyText 섹션 빌더.
///
/// 1,030쪽급 실문서 (한/글 2007 계열)와 같은 파싱 경로를 태우도록 문단마다
/// PARA_HEADER + PARA_TEXT + PARA_CHAR_SHAPE + PARA_LINE_SEG 레코드를
/// 방출한다. lineLocation은 페이지 내 절대 y (절대 캐시 모드)로 채우고,
/// 페이지 경계에서 리셋되도록 wrap한다.
enum SyntheticLargeDocument {
    /// isTraceChange 없는 22바이트 문단 헤더를 쓰는 파싱 버전
    static let version = HwpVersion(5, 0, 2, 2)

    /// 절대 y 좌표 파라미터 (HWPUNIT) — 본문 시작 2720, 줄 전진 2100
    static let firstLineLocation: Int32 = 2720
    static let lineAdvance: Int32 = 2100
    static let linesPerPage = 34

    /// N문단 × 약 M자 섹션 레코드 스트림
    static func sectionData(paragraphCount: Int, charactersPerParagraph: Int) -> Data {
        var data = Data()
        // 문단당 대략 (헤더 4+22) + (텍스트 4+2M) + (모양 4+8) + (라인 4+36)
        data.reserveCapacity(paragraphCount * (74 + charactersPerParagraph * 2))
        for index in 0 ..< paragraphCount {
            let text = paragraphText(index: index, targetCount: charactersPerParagraph)
            let textPayload = utf16Data(text)
            data.append(recordData(
                tagId: HwpSectionTag.paraHeader.rawValue,
                level: 0,
                payload: paraHeaderPayload(
                    charCount: UInt32(textPayload.count / 2),
                    paraId: UInt32(index)
                )
            ))
            data.append(recordData(
                tagId: HwpSectionTag.paraText.rawValue,
                level: 1,
                payload: textPayload
            ))
            data.append(recordData(
                tagId: HwpSectionTag.paraCharShape.rawValue,
                level: 1,
                payload: littleEndianData(UInt32(0)) + littleEndianData(UInt32(0))
            ))
            data.append(recordData(
                tagId: HwpSectionTag.paraLineSeg.rawValue,
                level: 1,
                payload: lineSegPayload(
                    location: firstLineLocation
                        + Int32(index % linesPerPage) * lineAdvance
                )
            ))
        }
        return data
    }

    /// 문단마다 내용이 다른 본문 텍스트 (BMP 한글/ASCII만 — UTF-16 절단 안전)
    static func paragraphText(index: Int, targetCount: Int) -> String {
        var text = "제\(index)문단 "
        while text.utf16.count < targetCount {
            text += "가나다라마바사아자차카타파하 성능 계측 본문 텍스트 "
        }
        return String(decoding: Array(text.utf16.prefix(targetCount)), as: UTF16.self)
    }

    // MARK: - payload 조립

    private static func paraHeaderPayload(charCount: UInt32, paraId: UInt32) -> Data {
        var payload = Data()
        payload.append(littleEndianData(charCount))
        payload.append(littleEndianData(UInt32(0))) // controlMask
        payload.append(littleEndianData(UInt16(0))) // paraShapeId
        payload.append(contentsOf: [0, 0]) // paraStyleId, columnType
        payload.append(littleEndianData(UInt16(1))) // charShapeInfoCount
        payload.append(littleEndianData(UInt16(0))) // rangeTagInfoCount
        payload.append(littleEndianData(UInt16(1))) // alignInfoCount
        payload.append(littleEndianData(paraId))
        return payload
    }

    /// HwpSynthetic.lineSegParagraph와 같은 36바이트 세그먼트 레이아웃
    private static func lineSegPayload(location: Int32) -> Data {
        var payload = Data(capacity: 36)
        payload.append(littleEndianData(UInt32(0))) // textStartingIndex
        payload.append(littleEndianData(location))
        payload.append(littleEndianData(Int32(1500))) // lineHeight
        payload.append(littleEndianData(Int32(1500))) // textHeight
        payload.append(littleEndianData(Int32(850))) // baselineGap
        payload.append(littleEndianData(Int32(600))) // lineSpacing
        payload.append(littleEndianData(Int32(0))) // columnStartingIndex
        payload.append(littleEndianData(Int32(42520))) // segmentWidth
        payload.append(littleEndianData(UInt32(393_216))) // flags
        return payload
    }

    private static func recordData(tagId: UInt32, level: UInt32, payload: Data) -> Data {
        SectionRecordBuilder.record(tagId: tagId, level: level, payload: payload)
    }

    private static func utf16Data(_ text: String) -> Data {
        var data = Data(capacity: text.utf16.count * 2)
        for unit in text.utf16 {
            withUnsafeBytes(of: unit.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    private static func littleEndianData(_ value: some FixedWidthInteger) -> Data {
        var littleEndian = value.littleEndian
        return withUnsafeBytes(of: &littleEndian) { Data($0) }
    }
}
