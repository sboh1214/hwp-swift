import Foundation

/**
 문단 번호

 Tag ID : HWPTAG_NUMBERING

 * 잘못된 문서화
 */
public struct HwpNumbering {
    /** 원본 payload */
    @ExcludeEquatable
    public var rawPayload: Data
    /**
     7회 반복 수준(1~7)

     각 레벨에 해당하는 숫자 또는 문자 또는 기호를 표시
     */
    public var formatArray: [HwpNumberingFormat]
    /** 시작 번호 */
    public let startingIndex: UInt16
    /** 수준별 시작번호 (5.0.2.5 이상) */
    public var startingIndexArray: [UInt32]?
    /**
     3회 반복 수준(8~10)

     각 레벨에 해당하는 숫자 또는 문자 또는 기호를 표시
     */
    public var extendedFormatArray: [HwpNumberingFormat]?
    /** 확장 수준별 시작번호 (5.1.0.0 이상) */
    public var extendedStartingIndexArray: [UInt32]?
}

extension HwpNumbering: HwpFromDataWithVersion {
    init(_ reader: inout DataReader, _ version: HwpVersion) throws {
        let startOffset = reader.byteOffset
        rawPayload = Data()
        formatArray = [HwpNumberingFormat]()
        for _ in 1 ... 7 {
            formatArray.append(try Self.numberingFormat(from: &reader))
        }
        startingIndex = try reader.read(UInt16.self)
        if version >= HwpVersion(5, 0, 2, 5) {
            let startingIndexCount = try Self.startingIndexCount(from: reader, version)
            startingIndexArray = try reader.read(UInt32.self, startingIndexCount)
        }
        if version >= HwpVersion(5, 1, 0, 0) {
            extendedFormatArray = [HwpNumberingFormat]()
            for _ in 8 ... 10 {
                extendedFormatArray?.append(try Self.numberingFormat(from: &reader))
            }
            extendedStartingIndexArray = try reader.read(UInt32.self, 3)
        }
        rawPayload = try reader.consumedData(from: startOffset)
    }

    static func load(
        _ data: Data,
        _ version: HwpVersion,
        options: HwpLoadOptions = .default
    ) throws -> Self {
        var reader = DataReader(data, options: options)
        var numbering = try self.init(&reader, version)
        if !reader.isEOF {
            throw HwpError.bytesAreNotEOF(model: Self.self, remain: reader.remainBytes)
        }
        numbering.rawPayload = options.preservedPayload(data)
        return numbering
    }
}

private extension HwpNumbering {
    static func numberingFormat(from reader: inout DataReader) throws -> HwpNumberingFormat {
        let bytes = try reader.readBytes(12).bytes
        let length = try reader.read(WORD.self)
        let formatStartOffset = reader.byteOffset
        let formatCharacters = try reader.read(WCHAR.self, length)
        let formatRawPayload = try reader.consumedData(from: formatStartOffset)
        return try HwpNumberingFormat(
            bytes,
            length,
            formatCharacters.string,
            formatRawPayload: formatRawPayload
        )
    }

    static func startingIndexCount(
        from reader: DataReader,
        _ version: HwpVersion
    ) throws -> Int {
        let documentedCount = 7
        let byteWidth = MemoryLayout<UInt32>.size

        if version >= HwpVersion(5, 1, 0, 0) {
            return documentedCount
        }

        let availableCount = min(documentedCount, reader.remainBytes / byteWidth)
        let unreadTrailingBytes = reader.remainBytes - (availableCount * byteWidth)
        guard unreadTrailingBytes == 0 || availableCount == documentedCount else {
            throw HwpError.truncatedData(expected: byteWidth, actual: unreadTrailingBytes)
        }
        return availableCount
    }
}

extension HwpNumbering {
    init(
        formatArray: [HwpNumberingFormat],
        startingIndex: UInt16,
        startingIndexArray: [UInt32]? = nil,
        extendedFormatArray: [HwpNumberingFormat]? = nil,
        extendedStartingIndexArray: [UInt32]? = nil,
        rawPayload: Data = Data()
    ) {
        self.rawPayload = rawPayload
        self.formatArray = formatArray
        self.startingIndex = startingIndex
        self.startingIndexArray = startingIndexArray
        self.extendedFormatArray = extendedFormatArray
        self.extendedStartingIndexArray = extendedStartingIndexArray
    }
}

/**
 문단 번호 정의(표 38)의 시작 번호 해석 (#153).

 표 38은 시작 번호를 두 자리에 적는다 — 정의 전체의 `시작 번호`(UINT16,
 `startingIndex`)와 5.0.2.5부터 붙은 `수준별 시작번호`(UINT×7,
 `startingIndexArray`; 5.1.0.0부터는 8-10수준의 `extendedStartingIndexArray`).
 스펙은 두 값의 관계를 적지 않는다. 아래 의미는 한컴 도움말에서 추론하고
 실물과 모순되지 않음을 확인한 것이다 — 실물이 가르지 못하는 절반은 그
 자리에 적었다.

 - `startingIndex`는 **시작 번호 방식**이다. 문단 번호 대화상자의 "앞 번호
   목록에 이어 / 새 번호 목록 시작(1수준 시작 번호 입력)", 개요 번호 모양
   대화상자의 "이전 구역의 번호에 이어 / 새 번호로 시작(1수준 시작 번호 입력)"
   에 대응한다. **0이면 앞 목록(앞 구역)에 이어 매기고, 1 이상이면 새 번호로
   시작**한다. 실물: 한글.app이 새로 만든 정의(빈 문서 기본값·`outline-numbering`·
   noori의 둘째 정의)는 0이고, 헌법주석의 41개 구역이 하나씩 가리키는 41개
   정의는 첫 구역 것만 0이며 나머지 40개가 1이다 — 그 문서의 생성 목차가
   구역(조문)마다 `I.`부터 다시 세는 것과 맞물린다(수준 1 표제 280개 전부
   일치, `HwpParagraphNumberingFixtureTests`). 다만 실물이 행사하는 것은 새
   번호(≥1 → 다시 셈) 쪽뿐이다 — 0인 정의는 앞이 없는 첫 구역·첫 목록에서만
   나와, 0이 실제로 앞 구역·앞 목록을 잇는지는 한글.app 실측이 남았다.
 - `startingIndexArray`는 새 번호로 시작할 때 **수준마다 어디서 시작하는가**다.
   배열이 없거나(5.0.2.5 미만 — 헌법주석 5.0.2.2의 정의 41개 전부) 값이
   0이면 1이다. 1수준은 두 자리 모두에 적힐 수 있어(`startingIndex`가 새 번호
   N이면서 배열의 첫 값이 1이거나 그 반대) **둘 중 큰 값**을 쓴다 — 한 값만
   1보다 크면 그것이 사용자가 적은 시작 번호이고, 둘 다 1이면 1이다.
   한글.app이 새 번호 N을 어느 자리에 적는지는 아직 실측하지 못했다(2026-09-06
   GUI 접근 거부) — 두 인코딩 모두 같은 결과를 내도록 둔 것이다. 값은 65,535
   (UINT16 상한)로 접는다 — 수준별 필드는 UINT32지만 정의 전체 시작 번호가
   UINT16이고 한글의 새 번호 입력 상한도 65,535라 그 위는 문서 조작이며, 접지
   않으면 로마 숫자 모양이 값에 비례하는 길이의 라벨을 만들어 문서를 여는
   순간 메모리를 삼킨다.

 카운터가 이 값을 언제 쓰는지(구역 경계·정의 교체)는 HwpKitCore의
 `HwpParagraphNumbering`이 정한다.
 */
public extension HwpNumbering {
    /// 시작 번호 방식 — `startingIndex`가 0이면 앞 번호 목록(개요는 이전 구역)에
    /// 이어 매기고, 1 이상이면 이 정의로 바뀌는 자리에서 새 번호로 시작한다.
    var continuesPreviousList: Bool {
        startingIndex == 0
    }

    /// 사람이 읽는 수준(1-10)이 새 번호로 시작할 때의 첫 번호. 수준별 시작번호가
    /// 없거나 0이면 1이고, 1수준은 `startingIndex`와 수준별 값 중 큰 쪽이다.
    /// 범위 밖 수준은 1, 65,535를 넘는 값은 65,535다.
    func startingNumber(forLevel level: Int) -> Int {
        let perLevel: UInt32? = if (1 ... 7).contains(level) {
            startingIndexArray.flatMap { $0.indices.contains(level - 1) ? $0[level - 1] : nil }
        } else if (8 ... 10).contains(level) {
            extendedStartingIndexArray.flatMap {
                $0.indices.contains(level - 8) ? $0[level - 8] : nil
            }
        } else {
            nil
        }
        let levelStart = max(1, Int(min(perLevel ?? 1, UInt32(UInt16.max))))
        guard level == 1 else { return levelStart }
        return max(levelStart, Int(startingIndex))
    }
}
