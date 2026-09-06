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
 스펙은 두 값의 관계를 적지 않는다. 아래 의미는 한컴 도움말과 한글.app 12.30
 실측(2026-09-06, `numbering-sequence` 픽스처 쌍)으로 확정했다.

 - `startingIndex`는 **시작 번호 방식**이다. 문단 번호 대화상자의 "앞 번호
   목록에 이어 / 새 번호 목록 시작", 개요 번호 모양 대화상자의 "앞 구역의 개요
   번호에 이어서 / 새 번호로 시작"에 대응한다. **0이면 앞 목록(앞 구역)에 이어
   매기고, 1 이상이면 새 번호로 시작**한다 — 값 자체는 번호가 아니다. 실측:
   한글.app이 구역 나누기로 만든 둘째 구역의 정의(`start=0`)는 앞 구역의 개요
   번호를 이어 받았고(`나.`·`2.`), 새 번호로 시작 7을 준 셋째 구역의 정의는
   `start=7`로 `7.`부터 셌다. 헌법주석의 41개 구역 정의는 첫 구역 것만 0이며
   나머지 40개가 1이라 조문마다 `I.`부터 다시 센다(생성 목차 280개와 일치).
 - `startingIndexArray`는 새 번호로 시작할 때 **수준마다 어디서 시작하는가**다.
   배열이 있으면 그 값이 시작 번호다(0이면 1). 실측: 대화상자에 새 번호 N을
   넣으면 `startingIndex`와 배열의 첫 값에 함께 N이 적히지만, 그 목록의 모양을
   대화상자에서 바꾸면 배열만 1로 되돌아가고 `startingIndex`에는 옛 N이 남는데
   한글은 1부터 센다 — **배열이 있으면 배열이 이긴다**. 배열이 없는 저장본
   (5.0.2.5 미만 — 헌법주석 5.0.2.2의 정의 41개 전부)에서만 `startingIndex`가
   1수준의 시작 번호이고(0은 1), 그 밖의 수준은 1이다.
   값은 65,535(UINT16 상한)로 접는다 — 수준별 필드는 UINT32지만 한글의 새 번호
   입력 상한이 65,535라 그 위는 문서 조작이며, 접지 않으면 로마 숫자 모양이
   값에 비례하는 길이의 라벨을 만들어 문서를 여는 순간 메모리를 삼킨다.

 카운터가 이 값을 언제 쓰는지(정의별 카운터·앞 목록 승계)는 HwpKitCore의
 `HwpParagraphNumbering`이 정한다.
 */
public extension HwpNumbering {
    /// 시작 번호 방식 — `startingIndex`가 0이면 앞 번호 목록(개요는 앞 구역)의
    /// 번호를 이어 받고, 1 이상이면 이 정의의 첫 문단부터 새 번호로 시작한다.
    var continuesPreviousList: Bool {
        startingIndex == 0
    }

    /// 사람이 읽는 수준(1-10)이 새 번호로 시작할 때의 첫 번호. 수준별 시작번호
    /// 배열이 있으면 그 값(0이면 1)이고, 배열이 없는 저장본에서는 1수준만
    /// `startingIndex`(0이면 1), 나머지 수준은 1이다. 범위 밖 수준은 1,
    /// 65,535를 넘는 값은 65,535다.
    func startingNumber(forLevel level: Int) -> Int {
        let ceiling = UInt32(UInt16.max)
        if (1 ... 7).contains(level) {
            if let array = startingIndexArray {
                let value = array.indices.contains(level - 1) ? array[level - 1] : 1
                return max(1, Int(min(value, ceiling)))
            }
            return level == 1 ? max(1, Int(startingIndex)) : 1
        }
        if (8 ... 10).contains(level), let array = extendedStartingIndexArray {
            let value = array.indices.contains(level - 8) ? array[level - 8] : 1
            return max(1, Int(min(value, ceiling)))
        }
        return 1
    }
}
