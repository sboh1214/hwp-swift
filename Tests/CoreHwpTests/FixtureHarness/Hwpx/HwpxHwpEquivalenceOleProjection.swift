@testable import CoreHwp
import Foundation

/// OLE 개체 등가 투영 (#134) — `DocumentEquivalenceProjection`의 OLE 축.
///
/// 본체에서 떼어 둔 것은 길이 때문이다(SwiftLint `type_body_length`) — 이 축은
/// BinItem 조인(`HwpImageStore`와 같은 규칙)과 차트 XML digest를 스스로 갖는다.
extension DocumentEquivalenceProjection {
    /// OLE 개체 요소 하나의 포맷 무관 투영 (#134).
    ///
    /// **BinItem id 숫자는 넣지 않는다** — id 공간은 재저장이 재생성하고(HWPX는
    /// manifest 등장 순서, `Hwpx/AGENTS.md`의 리맵 규약) 그래서 같은 개체가
    /// 포맷마다 다른 번호를 받을 수 있다. 이 투영이 id 매핑 인덱스를 제외하고
    /// 그림 축이 개수만 보는 것과 같은 이유다. 대신 참조가 실제로 닿는지와
    /// 내장 차트 XML을 비교한다.
    struct OleObject: Equatable {
        /// `binaryDataId`가 BinData 스트림에 닿는가 (댕글링이면 false).
        let resolvesBinaryData: Bool
        /// 내장 차트 XML의 digest — 차트가 아니거나 못 읽으면 nil.
        ///
        /// payload 전체는 축이 아니다: chart 쌍 실측에서 CFB의
        /// `OOXMLChartContents` 4,926바이트는 바이트 동일이지만 `Contents`
        /// 스트림이 1바이트 다르다. 그래서 렌더가 실제로 읽는 차트 XML만 본다.
        let chartXMLDigest: String?
    }

    /// OLE 개체 요소를 문서 순서로 투영한다 — BinItem 조인은 `HwpImageStore`와
    /// 같은 규칙(binDataArray 등재 순서 + 1 → `streamId` → 스트림)이다.
    static func oleObjects(of file: HwpFile) -> [OleObject] {
        var streams: [UInt16: Data] = [:]
        for stream in file.binaryDataArray {
            guard let streamId = stream.streamId, streams[streamId] == nil else { continue }
            streams[streamId] = stream.data
        }
        var payloads: [UInt32: Data] = [:]
        for (index, entry) in file.docInfo.idMappings.binDataArray.enumerated() {
            guard let streamId = entry.streamId, let data = streams[streamId] else { continue }
            payloads[UInt32(index + 1)] = data
        }

        let elements = HwpxFixtureAssertions.shapeComponents(from: file).flatMap(\.oleArray)
        return elements.map { ole -> OleObject in
            let payload = ole.binaryDataId.flatMap { payloads[$0] }
            let chartXML = payload.flatMap { HwpEmbeddedChart.chartXML(fromOLEPayload: $0) }
            return OleObject(
                resolvesBinaryData: payload != nil,
                chartXMLDigest: chartXML.map(Self.digest)
            )
        }
    }

    /// FNV-1a 64비트 digest — 실패 메시지에 4,926자 차트 XML이 통째로 찍히지
    /// 않게 하면서 내용 변화는 잡는다 (CryptoKit은 Linux에 없다).
    static func digest(_ text: String) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }
}
