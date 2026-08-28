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
    func isNamed(_ localName: String) -> Bool {
        guard self.localName == localName else {
            return false
        }
        return namespaceURI.isEmpty || HwpxNamespace.known.contains(namespaceURI)
    }

    func firstChild(named localName: String) -> HwpxXMLNode? {
        childElements.first { $0.isNamed(localName) }
    }

    func children(named localName: String) -> [HwpxXMLNode] {
        childElements.filter { $0.isNamed(localName) }
    }
}

/// OWPML이 선언하는 namespace URI 모음.
enum HwpxNamespace {
    static let paragraph = "http://www.hancom.co.kr/hwpml/2011/paragraph"
    static let section = "http://www.hancom.co.kr/hwpml/2011/section"
    static let head = "http://www.hancom.co.kr/hwpml/2011/head"
    static let core = "http://www.hancom.co.kr/hwpml/2011/core"
    static let app = "http://www.hancom.co.kr/hwpml/2011/app"
    static let masterPage = "http://www.hancom.co.kr/hwpml/2011/master-page"
    static let history = "http://www.hancom.co.kr/hwpml/2011/history"
    static let version = "http://www.hancom.co.kr/hwpml/2011/version"
    static let paragraph2016 = "http://www.hancom.co.kr/hwpml/2016/paragraph"
    static let hwpUnitChar = "http://www.hancom.co.kr/hwpml/2016/HwpUnitChar"
    static let ooxmlChart = "http://www.hancom.co.kr/hwpml/2016/ooxmlchart"
    static let hpf = "http://www.hancom.co.kr/schema/2011/hpf"
    static let opf = "http://www.idpf.org/2007/opf/"
    static let dublinCore = "http://purl.org/dc/elements/1.1/"
    static let ocfContainer = "urn:oasis:names:tc:opendocument:xmlns:container"

    static let known: Set<String> = [
        paragraph, section, head, core, app, masterPage, history, version,
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
            if child.isNamed("switch") {
                return Self.switchReplacement(child).map { $0.resolvingSwitches() }
                    .map { Content.element($0) }
            }
            return [.element(child.resolvingSwitches())]
        }
        return resolved
    }

    private static func switchReplacement(_ switchNode: HwpxXMLNode) -> [HwpxXMLNode] {
        for candidate in switchNode.childElements where candidate.isNamed("case") {
            let required = candidate.attributes["required-namespace"] ?? ""
            if HwpxNamespace.supportedSwitchNamespaces.contains(required) {
                return candidate.childElements
            }
        }
        return switchNode.firstChild(named: "default")?.childElements ?? []
    }
}
