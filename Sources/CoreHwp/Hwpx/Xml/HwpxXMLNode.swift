import Foundation

/// OWPML XML 요소 하나의 값 타입 표현 (mini-DOM).
///
/// `XMLParser`(SAX) 위에서 `HwpxXMLTreeParser`가 만든다. 자식 요소와 텍스트
/// 조각을 **원본 순서 그대로** `content`에 보존한다 — `<hp:t>ab<hp:tab/>cd
/// </hp:t>`처럼 텍스트와 요소가 섞이는 본문에서 순서가 곧 WCHAR 스트림
/// 순서이므로, 요소 배열과 텍스트 문자열로 갈라 담으면 복원할 수 없다.
struct HwpxXMLNode {
    /// 순서 보존 콘텐츠 조각 — 자식 요소이거나 텍스트다.
    enum Content {
        case element(HwpxXMLNode)
        case text(String)
    }

    /// 접두사를 뗀 요소 이름 (`shouldProcessNamespaces` 결과).
    var localName: String
    /// 요소의 namespace URI. 선언 없는 문서는 빈 문자열이다.
    var namespaceURI: String
    /// 속성 — 키는 접두사를 뗀 local name이다.
    var attributes: [String: String]
    var content: [Content]

    init(
        localName: String,
        namespaceURI: String = "",
        attributes: [String: String] = [:],
        content: [Content] = []
    ) {
        self.localName = localName
        self.namespaceURI = namespaceURI
        self.attributes = attributes
        self.content = content
    }
}

extension HwpxXMLNode {
    /// 자식 요소만 순서대로.
    var childElements: [HwpxXMLNode] {
        content.compactMap {
            if case let .element(node) = $0 {
                return node
            }
            return nil
        }
    }

    /// 직속 텍스트 조각의 연결 — 혼합 콘텐츠의 배치 순서는 잃는다.
    /// 순서가 필요한 소비자는 `content`를 직접 순회한다.
    var text: String {
        content.reduce(into: "") { result, piece in
            if case let .text(fragment) = piece {
                result += fragment
            }
        }
    }

    /// local name이 일치하고 namespace가 한컴/OPF 계열이거나 비어 있는지.
    ///
    /// 접두사(hp/hh/hs …)는 문서마다 다를 수 있으므로 보지 않는다. namespace
    /// URI가 비어 있지 않으면 알려진 집합에 들어야 한다 — 외부 namespace의
    /// 동명 요소를 OWPML로 오인하지 않기 위해서다.
    ///
    /// 자식 조회(`firstChild`/`children`)가 이 전역 집합을 쓰는 것은 의도다 —
    /// 한 파일 안에서 vocabulary가 합법적으로 섞이기 때문이다 (`hh:margin`의
    /// 자식은 `hc:left`, `hp:*` 요소도 `hc:*` 자식을 갖는다). 단일 namespace로
    /// 좁히려면 요소별 기대-namespace 표가 필요하고, 잘못 좁히면 교차
    /// vocabulary 자식을 놓쳐 margin·색상 값이 조용히 0으로 떨어진다.
    ///
    /// **vocabulary가 하나로 확정되는 지점은 이미 좁혀 두었다** —
    /// 루트 4종·구역 본문 문단(`hp:p`)·manifest 자식·refList 가족. 남은
    /// 중첩 조회(`hh:paraPr` 안의 `align` 등)를 좁히려면 위의 요소별
    /// 기대-namespace 표가 필요하고, 표 없이 넓게 좁히면 합법적인 `hc:`
    /// 자식을 놓친다 — 실물 픽스처 전수 검증과 함께 별도로 다룬다.
    func isNamed(_ localName: String) -> Bool {
        guard self.localName == localName else {
            return false
        }
        return namespaceURI.isEmpty || HwpxNamespace.known.contains(namespaceURI)
    }

    /// local name이 일치하고 namespace가 기대 vocabulary이거나 비어 있는지.
    ///
    /// 전역 `known` 집합만 보는 `isNamed(_:)`와 달리 특정 namespace 하나로
    /// 좁힌다 — 낯선 vocabulary의 동명 요소(`<hs:head>`가 `head`로, 확장
    /// namespace의 `<ext:tbl>`이 `tbl`로)를 OWPML로 오인하지 않기 위해서다.
    /// 무-namespace 폴백은 선언 없는 문서를 위해 보존한다.
    func isNamed(_ localName: String, in namespace: String) -> Bool {
        guard self.localName == localName else {
            return false
        }
        return namespaceURI.isEmpty || namespaceURI == namespace
    }

    func firstChild(named localName: String) -> HwpxXMLNode? {
        childElements.first { $0.isNamed(localName) }
    }

    func children(named localName: String) -> [HwpxXMLNode] {
        childElements.filter { $0.isNamed(localName) }
    }

    /// paragraph vocabulary로 확정된 자식만 고른다 — 표 구조(tr·tc·셀 문단)
    /// 처럼 vocabulary가 하나로 정해지는 자리에 쓴다.
    func paragraphChildren(named localName: String) -> [HwpxXMLNode] {
        childElements.filter { $0.isNamed(localName, in: HwpxNamespace.paragraph) }
    }

    /// head vocabulary로 확정된 자식만 고른다 — refList 정의 요소(charPr·
    /// style 등)처럼 vocabulary가 하나로 정해지는 자리에 쓴다
    /// (`paragraphChildren`의 head 대응).
    func headChildren(named localName: String) -> [HwpxXMLNode] {
        childElements.filter { $0.isNamed(localName, in: HwpxNamespace.head) }
    }

    /// paragraph vocabulary로 확정된 첫 자식 — secPr 하위(pagePr·margin·
    /// colLine)처럼 vocabulary가 하나로 정해지는 단일 자식 조회에 쓴다
    /// (`paragraphChildren`의 firstChild 대응).
    func paragraphFirstChild(named localName: String) -> HwpxXMLNode? {
        childElements.first { $0.isNamed(localName, in: HwpxNamespace.paragraph) }
    }

    /// core vocabulary로 확정된 첫 자식 — 채우기(`hc:fillBrush`)처럼 값
    /// 표현이 core로 정해지는 자리에 쓴다.
    func coreFirstChild(named localName: String) -> HwpxXMLNode? {
        childElements.first { $0.isNamed(localName, in: HwpxNamespace.core) }
    }

    /// 이름마다 기대 vocabulary가 갈리는 가족의 소비 판정 — `hh:borderFill`은
    /// 테두리 4종이 head, 채우기가 core다. 단일 namespace 변형으로는 그 둘을
    /// 함께 표현할 수 없다.
    func unconsumedChildRecords(consumed: [String: String]) -> [HwpUnknownRecord] {
        childElements
            .filter { child in
                guard let namespace = consumed[child.localName] else {
                    return true
                }
                return !child.isNamed(child.localName, in: namespace)
            }
            .map { $0.syntheticUnknownRecord() }
    }

    /// head vocabulary로 확정된 첫 자식 — charPr 잎(bold·underline 등)처럼
    /// 스키마가 vocabulary를 하나로 고정하는 단일 자식 조회에 쓴다
    /// (`paragraphFirstChild`의 head 대응).
    func headFirstChild(named localName: String) -> HwpxXMLNode? {
        childElements.first { $0.isNamed(localName, in: HwpxNamespace.head) }
    }

    /// 미지 요소를 자식 트리째 합성 레코드로 바꾼다 — 바이너리 변환
    /// (`HwpUnknownRecord(HwpRecord)`)과 같은 재귀 보존이다. 평탄 변환은
    /// 진단 walker의 `.child[i]` 재귀가 안쪽 미지 요소에 닿지 못하게 한다.
    /// 깊이는 파서의 `maximumElementDepth`가 유계로 잡는다.
    func syntheticUnknownRecord(
        maxDepth: Int = HwpReadLimits.default.maxNestingDepth
    ) -> HwpUnknownRecord {
        HwpUnknownRecord(
            tagId: hwpxSyntheticTagId,
            level: 0,
            payload: Data(localName.utf8),
            children: maxDepth <= 1 ? [] : childElements.map {
                $0.syntheticUnknownRecord(maxDepth: maxDepth - 1)
            }
        )
    }

    /// 소비되지 않은 자식을 진단용 합성 레코드로 옮긴다.
    ///
    /// 소비 판정은 **조회와 같은 술어**(`isNamed`)여야 한다 — local name만
    /// 비교하면 낯선 namespace의 동명 요소(`<ext:pagePr>`)가 조회에서는
    /// 거부되면서 소비 목록에는 걸려 진단에서도 사라진다.
    func unconsumedChildRecords(
        consumed: Set<String>,
        maxDepth: Int = HwpReadLimits.default.maxNestingDepth
    ) -> [HwpUnknownRecord] {
        childElements
            .filter { child in !consumed.contains { child.isNamed($0) } }
            .map { $0.syntheticUnknownRecord(maxDepth: maxDepth) }
    }

    /// `unconsumedChildRecords(consumed:)`의 vocabulary-좁힘 변형 —
    /// `paragraphChildren`처럼 좁혀 조회한 자리는 소비 판정도 같은 술어여야
    /// 한다. 전역 판정이면 타 vocabulary 디코이(`<hh:tc>`)가 소비로 오인돼
    /// 진단에서 사라진다.
    func unconsumedChildRecords(
        consumed: Set<String>,
        in namespace: String,
        maxDepth: Int = HwpReadLimits.default.maxNestingDepth
    ) -> [HwpUnknownRecord] {
        childElements
            .filter { child in !consumed.contains { child.isNamed($0, in: namespace) } }
            .map { $0.syntheticUnknownRecord(maxDepth: maxDepth) }
    }
}

/// OWPML이 선언하는 namespace URI 모음.
enum HwpxNamespace {
    static let paragraph = "http://www.hancom.co.kr/hwpml/2011/paragraph"
    static let section = "http://www.hancom.co.kr/hwpml/2011/section"
    static let head = "http://www.hancom.co.kr/hwpml/2011/head"
    static let core = "http://www.hancom.co.kr/hwpml/2011/core"
    static let app = "http://www.hancom.co.kr/hwpml/2011/app"
    /// OWPML의 master-page namespace — 한글 UI 용어로 "바탕쪽"이다.
    static let batangPage = "http://www.hancom.co.kr/hwpml/2011/master-page"
    static let history = "http://www.hancom.co.kr/hwpml/2011/history"
    static let version = "http://www.hancom.co.kr/hwpml/2011/version"
    static let paragraph2016 = "http://www.hancom.co.kr/hwpml/2016/paragraph"
    static let hwpUnitChar = "http://www.hancom.co.kr/hwpml/2016/HwpUnitChar"
    static let ooxmlChart = "http://www.hancom.co.kr/hwpml/2016/ooxmlchart"
    static let hpf = "http://www.hancom.co.kr/schema/2011/hpf"
    static let opf = "http://www.idpf.org/2007/opf/"
    static let dublinCore = "http://purl.org/dc/elements/1.1/"
    static let ocfContainer = "urn:oasis:names:tc:opendocument:xmlns:container"

    /// namespace를 선언한 파트 안의 **무접두사** 요소에 파서가 붙이는 표식.
    ///
    /// XML 의미론상 그런 요소의 URI는 빈 문자열인데, 빈 URI는 선언 없는
    /// 문서를 위한 폴백이라 어느 vocabulary 조회에도 걸린다 — 정상 HWPX에
    /// 섞인 `<p>`가 `hp:p`로 파싱된다. 파트 전체가 무-namespace일 때만 그
    /// 폴백이 성립하므로, 그렇지 않은 파트에서는 이 표식으로 갈라 낸다
    /// (known에 넣지 않아 모든 조회에서 미지로 강등된다).
    static let unqualified = "urn:x-hwp-swift-unqualified"

    static let known: Set<String> = [
        paragraph, section, head, core, app, batangPage, history, version,
        paragraph2016, hwpUnitChar, ooxmlChart, hpf, opf, dublinCore, ocfContainer,
    ]

    /// `hp:switch`의 `hp:case required-namespace`가 이 집합에 들면 그 분기를
    /// 채택한다 — 2016 HwpUnitChar 확장이 있는 문서는 그쪽 값이 정본이다.
    static let supportedSwitchNamespaces: Set<String> = [hwpUnitChar]
}

extension HwpxXMLNode {
    /// `hp:switch` 조건 분기를 정적으로 해소한 사본을 돌려준다.
    ///
    /// `required-namespace`가 지원 집합에 드는 첫 `case`의 콘텐츠를, 없으면
    /// `default`의 콘텐츠를 switch 자리에 이어 붙인다 (둘 다 없으면 제거).
    /// 매퍼가 조건 분기를 볼 일이 없도록 파싱 직후 한 번만 돌린다.
    func resolvingSwitches() -> HwpxXMLNode {
        var resolved = self
        resolved.content = content.flatMap { piece -> [Content] in
            guard case let .element(child) = piece else {
                return [piece]
            }
            // switch·case·default는 paragraph vocabulary다 — 전역 매칭이면
            // 타 vocabulary의 동명 요소가 매퍼·진단이 보기 전에 접합·삭제된다.
            if child.isNamed("switch", in: HwpxNamespace.paragraph) {
                return Self.switchReplacement(child).map { $0.resolvingSwitches() }
                    .map { Content.element($0) }
            }
            return [.element(child.resolvingSwitches())]
        }
        return resolved
    }

    private static func switchReplacement(_ switchNode: HwpxXMLNode) -> [HwpxXMLNode] {
        for candidate in switchNode.childElements
            where candidate.isNamed("case", in: HwpxNamespace.paragraph)
        {
            let required = candidate.attributes["required-namespace"] ?? ""
            if HwpxNamespace.supportedSwitchNamespaces.contains(required) {
                return candidate.childElements
            }
        }
        return switchNode.paragraphFirstChild(named: "default")?.childElements ?? []
    }
}
