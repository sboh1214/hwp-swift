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
        static let container = "META-INF/container.xml"
        static let packageMediaType = "application/hwpml-package+xml"
    }

    private let archive: HwpxArchive
    private let limits: HwpReadLimits
    private var budget: HwpxByteBudget

    init(data: Data, limits: HwpReadLimits) throws {
        archive = try HwpxArchive(data: data, limits: limits)
        self.limits = limits
        budget = HwpxByteBudget(limits: limits)
        // 이름 디코딩은 예산이 서기 전에 끝나므로 사후 차감이다 — 그래도
        // 남은 엔트리 예산이 그만큼 줄어 파일 단위 상한이 하나로 지켜진다.
        try budget.consume(archive.centralDirectoryBytes, entryName: "central directory")

        // mimetype 게이트를 암호화 분류보다 먼저 통과시킨다 (불변식 #3) —
        // encryption.xml을 가진 비-HWP ZIP(.docx 등)이 암호화 HWP 문서로
        // 오분류돼 자동 감지·HwpKit로 새어 나가지 않게 한다 (P2).
        try Self.validateMimetype(archive, limits: limits, budget: &budget)
        guard archive.entriesByName[EntryName.encryption] == nil else {
            throw HwpError.unsupportedFeature(.encryptedDocument)
        }
    }

    /// 패키지 문서(content.hpf)의 실제 경로.
    ///
    /// OCF에서 그 경로의 정본은 `META-INF/container.xml`의 rootfile이므로
    /// **선언을 먼저 본다** — 관례 경로를 앞세우면 낡은
    /// `Contents/content.hpf`가 남은 재포장 컨테이너에서 선언된 문서 대신
    /// 그 낡은 패키지를 파싱한다. 관례 경로는 container.xml이 없거나
    /// hwpml-package rootfile을 선언하지 않을 때의 폴백이다 (파싱 실패는
    /// 이 모듈의 규약대로 전파한다).
    mutating func packageEntryName() throws -> String {
        guard let data = try optionalEntry(EntryName.container) else {
            return EntryName.manifest
        }
        let root = try HwpxXMLTreeParser.parse(data, entry: EntryName.container)
        guard root.isNamed("container", in: HwpxNamespace.ocfContainer) else {
            return EntryName.manifest
        }
        return Self.packagePath(in: root) ?? EntryName.manifest
    }

    private static func packagePath(in container: HwpxXMLNode) -> String? {
        for rootfiles in container.childElements
            where rootfiles.isNamed("rootfiles", in: HwpxNamespace.ocfContainer)
        {
            for rootfile in rootfiles.childElements
                where rootfile.isNamed("rootfile", in: HwpxNamespace.ocfContainer)
            {
                guard rootfile.attribute("media-type") == EntryName.packageMediaType,
                      let path = rootfile.attribute("full-path"), !path.isEmpty
                else {
                    continue
                }
                return path
            }
        }
        return nil
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
        // 정규 이름만 폴백에 채택한다 — Int("01")도 1이라 별칭을 받으면 같은
        // 인덱스의 구역이 중복되고, 동률 정렬 순서가 사전 순회 무작위를 탄다.
        guard let index = Int(digits), String(index) == digits else {
            return nil
        }
        return index
    }

    private static func validateMimetype(
        _ archive: HwpxArchive,
        limits: HwpReadLimits,
        budget: inout HwpxByteBudget
    ) throws {
        guard let entry = archive.entriesByName[EntryName.mimetype] else {
            throw HwpError.invalidArchive(reason: "missing 'mimetype' entry")
        }
        // 암호화된 mimetype은 포맷 판정 자체가 불능이다 — 범용 entry 리더에
        // 맡기면 encryptedDocument(HWP 도메인 주장)가 미디어 타입 비교보다
        // 먼저 던져져 임의 암호화 ZIP이 "암호 한글 문서"로 오분류된다. OCF는
        // mimetype을 평문 저장하므로 이 아카이브는 한컴 저장본이 아니다.
        guard entry.flags & 0b1 == 0 else {
            throw HwpError.invalidArchive(reason: "encrypted 'mimetype' entry")
        }
        let data = try archive.entryData(
            named: EntryName.mimetype, limits: limits, budget: &budget
        )
        // 후행 개행 정도는 허용한다 — 판정의 본질은 미디어 타입 문자열이다.
        let mimetype = String(bytes: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard mimetype == expectedMimetype else {
            throw HwpError.invalidArchive(
                reason: "unexpected mimetype '\(mimetype ?? "<not UTF-8>")'"
            )
        }
    }
}
