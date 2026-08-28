import Foundation

/// ZIP 위의 OCF 컨테이너 계층 — HWPX 판정 게이트와 이름 있는 엔트리 접근.
///
/// 여기서 두 게이트를 통과해야 파싱이 시작된다:
/// 1. `mimetype` 엔트리 내용이 `application/hwp+zip`이어야 한다 — .docx 등
///    임의 ZIP이 하류에서 알 수 없는 XML 오류로 표류하는 대신 컨테이너
///    단계에서 명확한 typed error로 거부되게 하는 포맷 게이트다. OCF의
///    "첫 엔트리·비압축" 권고는 검사하지 않는다 (내용 일치가 본질이다).
/// 2. `META-INF/encryption.xml`이 있으면 암호화 문서다 — HWP5의
///    `unsupportedFeature(.encryptedDocument)`와 같은 분류로 거부한다.
///
/// 집계 바이트 예산(`HwpxByteBudget`)을 들고 다니므로 mutating 접근자다.
struct HwpxContainer {
    static let expectedMimetype = "application/hwp+zip"

    enum EntryName {
        static let mimetype = "mimetype"
        static let version = "version.xml"
        static let manifest = "Contents/content.hpf"
        static let header = "Contents/header.xml"
        static let settings = "settings.xml"
        static let previewText = "Preview/PrvText.txt"
        static let previewImage = "Preview/PrvImage.png"
        static let encryption = "META-INF/encryption.xml"
    }

    private let archive: HwpxArchive
    private let limits: HwpReadLimits
    private var budget: HwpxByteBudget

    init(data: Data, limits: HwpReadLimits) throws {
        archive = try HwpxArchive(data: data)
        self.limits = limits
        budget = HwpxByteBudget(limits: limits)

        guard archive.entriesByName[EntryName.encryption] == nil else {
            throw HwpError.unsupportedFeature(.encryptedDocument)
        }
        try Self.validateMimetype(archive, limits: limits, budget: &budget)
    }

    mutating func requiredEntry(_ name: String) throws -> Data {
        try archive.entryData(named: name, limits: limits, budget: &budget)
    }

    mutating func optionalEntry(_ name: String) throws -> Data? {
        try archive.optionalEntryData(named: name, limits: limits, budget: &budget)
    }

    func hasEntry(_ name: String) -> Bool {
        archive.entriesByName[name] != nil
    }

    /// `Contents/section{N}.xml` 엔트리 이름을 N 오름차순으로 돌려준다.
    ///
    /// 구역 순서의 정본은 content.hpf의 spine이지만, spine이 없거나 항목이
    /// 누락된 문서를 위해 아카이브 실재 목록을 폴백으로 쓴다. 사전순은
    /// `section10`을 `section2` 앞에 두므로 숫자 정렬이어야 한다.
    var sectionEntryNames: [String] {
        archive.entriesByName.keys
            .compactMap { name -> (index: Int, name: String)? in
                guard let index = Self.sectionIndex(of: name) else {
                    return nil
                }
                return (index, name)
            }
            .sorted { $0.index < $1.index }
            .map(\.name)
    }

    static func sectionIndex(of entryName: String) -> Int? {
        guard entryName.hasPrefix("Contents/section"), entryName.hasSuffix(".xml") else {
            return nil
        }
        let digits = entryName.dropFirst("Contents/section".count).dropLast(".xml".count)
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else {
            return nil
        }
        return Int(digits)
    }

    private static func validateMimetype(
        _ archive: HwpxArchive,
        limits: HwpReadLimits,
        budget: inout HwpxByteBudget
    ) throws {
        guard archive.entriesByName[EntryName.mimetype] != nil else {
            throw HwpError.invalidArchive(reason: "missing 'mimetype' entry")
        }
        let data = try archive.entryData(
            named: EntryName.mimetype, limits: limits, budget: &budget
        )
        // 후행 개행 정도는 허용한다 — 판정의 본질은 미디어 타입 문자열이다.
        let mimetype = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard mimetype == expectedMimetype else {
            throw HwpError.invalidArchive(reason: "unexpected mimetype '\(mimetype)'")
        }
    }
}
