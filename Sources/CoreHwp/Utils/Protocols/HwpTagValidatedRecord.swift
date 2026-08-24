import Foundation

/// record tag 검증을 default `load`에 통합하기 위한 tag 추상화.
/// tag 체계가 Section/DocInfo 두 갈래이므로 검증 진입점만 프로토콜로 연다 —
/// error 문구는 기존 validate 함수를 그대로 사용해 두 갈래의 기존 진단
/// 메시지를 바꾸지 않는다 (#83).
protocol HwpValidatableRecordTag {
    static func validateRecordTag(_ record: HwpRecord, expectedTag: Self) throws
}

extension HwpSectionTag: HwpValidatableRecordTag {
    static func validateRecordTag(_ record: HwpRecord, expectedTag: Self) throws {
        try validateSectionRecordTag(record, expectedTag: expectedTag)
    }
}

extension HwpDocInfoTag: HwpValidatableRecordTag {
    static func validateRecordTag(_ record: HwpRecord, expectedTag: Self) throws {
        try validateDocInfoRecordTag(record, expectedTag: expectedTag)
    }
}

/// 두 tag-검증 프로토콜(version 유/무)이 공유하는 요구사항.
/// version 유무 양쪽을 채택하는 타입에서 `enforcesEOF` default가
/// witness 모호성을 내지 않도록 default를 이 한 곳에만 둔다.
protocol HwpTagValidatedRecordCore {
    associatedtype ExpectedTag: HwpValidatableRecordTag
    static var expectedTag: ExpectedTag { get }
    /// EOF 강제 여부. 기본 true. 커스텀 load 시절 EOF를 검사하지 않던
    /// 타입의 현행 동작을 그대로 옮기는 스위치다 — 일괄 강제 전환은
    /// 실문서에서 새 `bytesAreNotEOF`를 낼 수 있어 후속 이슈로 분리한다.
    /// 새 타입에서 끄지 말 것 (#83).
    static var enforcesEOF: Bool { get }
}

extension HwpTagValidatedRecordCore {
    static var enforcesEOF: Bool {
        true
    }
}

/**
 record tag 검증이 선행되는 record 모델.

 채택 측은 `expectedTag`와 `init(_:_:)`만 작성한다 — default `load`가
 tag 검증 + reader 생성(options 전파) + init + EOF 강제를 제공하므로
 `load`를 override하지 않는다 (`HwpFromRecord` 계약과 동일).
 */
protocol HwpTagValidatedRecord: HwpFromRecord, HwpTagValidatedRecordCore {}

extension HwpTagValidatedRecord {
    static func load(_ record: HwpRecord) throws -> Self {
        try loadTagValidated(record)
    }

    /// tag 검증 load 코어 — rawPayload 복원 변형이 재사용한다.
    static func loadTagValidated(_ record: HwpRecord) throws -> Self {
        try ExpectedTag.validateRecordTag(record, expectedTag: expectedTag)

        var reader = DataReader(record.payload, options: record.options)
        let model = try self.init(&reader, record.children)
        if enforcesEOF, !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        return model
    }
}

/** record tag 검증이 선행되는 record 모델의 version 변형. */
protocol HwpTagValidatedRecordWithVersion: HwpFromRecordWithVersion, HwpTagValidatedRecordCore {}

extension HwpTagValidatedRecordWithVersion {
    static func load(_ record: HwpRecord, _ version: HwpVersion) throws -> Self {
        try loadTagValidated(record, version)
    }

    /// tag 검증 load 코어 — rawPayload 복원 변형이 재사용한다.
    static func loadTagValidated(_ record: HwpRecord, _ version: HwpVersion) throws -> Self {
        try ExpectedTag.validateRecordTag(record, expectedTag: expectedTag)

        var reader = DataReader(record.payload, options: record.options)
        let model = try self.init(&reader, record.children, version)
        if enforcesEOF, !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        return model
    }
}

/**
 load 반환 직전 record payload 전체를 `rawPayload`로 복원하는 변형 표식.

 커스텀 load마다 반복되던
 `model.rawPayload = record.options.preservedPayload(record.payload)` 한 줄을
 default로 옮긴다 (#83). init이 채운 rawPayload를 record 전체 payload로
 덮으므로 보존 off(`.viewer`)에서는 비워져 메모리 이득이 유지된다 —
 load 후 rawPayload를 다시 읽는 타입은 이 표식 대신 커스텀 load에서
 `decoupledPayload`를 유지해야 한다 (`HwpListControl` 참조).
 */
protocol HwpRawPayloadRestoringRecord {
    var rawPayload: Data { get set }
}

extension HwpTagValidatedRecord where Self: HwpRawPayloadRestoringRecord {
    static func load(_ record: HwpRecord) throws -> Self {
        var model = try loadTagValidated(record)
        model.rawPayload = record.options.preservedPayload(record.payload)
        return model
    }
}

extension HwpTagValidatedRecordWithVersion where Self: HwpRawPayloadRestoringRecord {
    static func load(_ record: HwpRecord, _ version: HwpVersion) throws -> Self {
        var model = try loadTagValidated(record, version)
        model.rawPayload = record.options.preservedPayload(record.payload)
        return model
    }
}
