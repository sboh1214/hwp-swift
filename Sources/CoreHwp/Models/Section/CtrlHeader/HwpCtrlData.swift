import Foundation

/** 컨트롤 데이터 */
public struct HwpCtrlData {
    /** 원본 payload */
    public var rawPayload: Data
    /** 알려진 ParameterSet payload를 해석한 값 */
    public var parameterSet: HwpCtrlDataParameterSet?
    /** 아직 해석하지 않은 child record */
    public var unknownChildren: [HwpUnknownRecord]

    /** 기존 raw record assertion과 호환되는 payload alias */
    public var payload: Data {
        rawPayload
    }
}

extension HwpCtrlData: HwpTagValidatedRecord {
    static let expectedTag: HwpSectionTag = .ctrlData
    /// 커스텀 load 시절 EOF를 검사하지 않던 현행 동작 보존 (#83) —
    /// init이 payload를 전부 소비하므로 강제 전환은 후속 이슈에서 켠다.
    static let enforcesEOF = false

    // MARK: loader contract exemption - CTRL_DATA payload is currently opaque raw data

    init(_ reader: inout DataReader, _ children: [HwpRecord]) throws {
        // 책갈피 등이 load 반환 후 rawPayload를 다시 파싱하므로
        // 보존 off에서도 비우지 않고 분리 복사한다.
        rawPayload = reader.options.decoupledPayload(try reader.readToEnd())
        parameterSet = HwpCtrlDataParameterSet(rawPayload)
        unknownChildren = children.map(HwpUnknownRecord.init)
    }
}
