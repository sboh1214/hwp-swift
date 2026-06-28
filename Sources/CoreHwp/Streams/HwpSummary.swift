import Foundation

/**
 문서 요약

 U+0005 HwpSummaryInformation 스트림에는 한글 메뉴의 “파일-문서 정보-문서 요약”에서 입력한 내용이 저장된다.
 */
public struct HwpSummary: HwpFromData {
    public let rawPayload: Data

    public init(rawPayload: Data = Data()) {
        self.rawPayload = rawPayload
    }

    // MARK: loader contract exemption - summary stream is an opaque raw payload

    init(_ reader: inout DataReader) throws {
        self.init(rawPayload: try reader.readToEnd())
    }
}
