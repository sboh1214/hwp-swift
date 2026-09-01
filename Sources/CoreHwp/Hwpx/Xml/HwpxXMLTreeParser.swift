import Foundation
#if canImport(FoundationXML)
    import FoundationXML
#endif

/// `XMLParser`(SAX) 델리게이트로 XML 엔트리 하나를 `HwpxXMLNode` 트리로
/// 만든다.
///
/// 델리게이트 콜백은 throw할 수 없고 이 모듈은 오류 무시 변환을 금지하므로
/// (SourceSafetyTests), 실패를 **누적**했다가 `abortParsing()`으로 멈추고
/// 파싱이 끝난 뒤 typed `HwpError.invalidXML`로 변환한다.
///
/// 요소 깊이 상한은 레코드 트리의 `maxNestingDepth`와 같은 구조 유효성
/// 한도다 — 재귀 소비자(매퍼·switch 해소)가 조작 문서로 스택 오버플로하지
/// 않게 파싱 시점에 한 번만 막는다. 원시 XML은 논리 중첩 1단에 요소 여러
/// 단이 겹겹이라 (`p > run > tbl > tr > tc > subList > p`) 레코드 level보다
/// 훨씬 여유 있게 잡는다.
final class HwpxXMLTreeParser: NSObject {
    /// 요소 깊이 상한. 실측 템플릿 최대 깊이는 8 안팎이다.
    static let maximumElementDepth = 512

    private var stack: [HwpxXMLNode] = []
    private var root: HwpxXMLNode?
    private var failure: String?
    private var sawNamespacedElement = false
    /// 첫 namespaced 요소보다 **앞서** 만들어진 무접두사 노드 수. 루트가
    /// 접두사를 선언만 하고 자신은 무접두사인 파트(`<head xmlns:hh="…">`)가
    /// 그렇다 — 생성 시점에는 파트가 namespace를 쓰는지 알 수 없으므로 그
    /// 노드들만 파싱이 끝난 뒤 소급 표시한다.
    private var unqualifiedNodesBeforeNamespace = 0
    private weak var runningParser: XMLParser?

    /// XML 바이트를 파싱해 루트 요소를 돌려준다. `hp:switch`는 여기서 이미
    /// 해소되어 매퍼는 조건 분기를 보지 않는다.
    static func parse(_ data: Data, entry: String) throws -> HwpxXMLNode {
        // 델리게이트 기반 거부는 Apple 한정이다 — libxml2 기반 Linux
        // XMLParser는 엔티티 선언 콜백을 부르지 않아 선언이 그대로 통과한다
        // (Linux CI 실측). 조용한 본문 유실·치환은 두 플랫폼 모두에서
        // 일어나므로 바이트에서 먼저 거른다.
        if let reason = doctypeInternalSubsetFailure(in: data) {
            throw HwpError.invalidXML(entry: entry, reason: reason)
        }

        let delegate = HwpxXMLTreeParser()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        delegate.runningParser = parser

        let finished = parser.parse()
        if let failure = delegate.failure {
            throw HwpError.invalidXML(entry: entry, reason: failure)
        }
        guard finished, let root = delegate.root else {
            let reason = parser.parserError.map(String.init(describing:))
                ?? "no root element"
            throw HwpError.invalidXML(entry: entry, reason: reason)
        }
        // 소급 표시는 switch 해소보다 **먼저**다 — 해소도 (URI, local name)로
        // 분기를 고르므로, 뒤늦게 갈라 낼 노드를 남긴 채 돌리면 무접두사
        // <switch>가 hp:switch로 해소된다.
        guard delegate.sawNamespacedElement,
              delegate.unqualifiedNodesBeforeNamespace > 0
        else {
            return root.resolvingSwitches()
        }
        return root.markingUnqualifiedElements().resolvingSwitches()
    }

    /// DTD 내부 서브셋의 엔티티 선언을 바이트에서 찾는다.
    ///
    /// DOCTYPE의 **내부 서브셋**을 거부한다 — 엔티티 선언은 거기서만 올 수
    /// 있고(외부 DTD는 `shouldResolveExternalEntities = false`로 무력),
    /// Linux는 선언 콜백을 부르지 않아 바이트에서 걸러야 한다.
    ///
    /// 서브셋 안의 `<!ENTITY`만 찾지 않는 이유는 인용부호 안의 `]`이
    /// (`<!NOTATION n SYSTEM "]">`) 서브셋을 조기 종료시켜 뒤따르는 선언을
    /// 놓치기 때문이다. 반대로 DOCTYPE **뒤 전체**를 훑으면 무해한 DOCTYPE이
    /// 있는 문서의 주석·CDATA 속 `<!ENTITY` 문자열이 오탐이 된다. `[`는
    /// DOCTYPE 선언의 첫 `>`보다 앞서므로 이 판정은 본문에 흔들리지 않는다
    /// (실측: 픽스처 10종·한컴 번들 템플릿 전수에 DOCTYPE 0건).
    static func doctypeInternalSubsetFailure(in data: Data) -> String? {
        for encoding in PrologEncoding.allCases
            where prologDeclaresInternalSubset(in: data, encoding: encoding)
        {
            return "DOCTYPE internal subset is not supported"
        }
        return nil
    }

    /// 프롤로그를 **어휘적으로** 훑어 DOCTYPE 선언의 내부 서브셋을 찾는다.
    ///
    /// 바이트 검색으로는 두 방향을 함께 닫을 수 없다 — 첫 매치만 보면 주석 속
    /// 가짜 DOCTYPE이 진짜를 가리고(회피), 매치를 모두 훑으면 주석 안의
    /// `<!DOCTYPE x [` 조각이 유효 문서를 거부한다(오탐). DOCTYPE은 루트 요소
    /// 앞에만 올 수 있으므로, 선두에서 XML 선언·주석·공백만 건너뛰며 진행하면
    /// 둘 다 사라진다. 프롤로그 문법은 전부 ASCII라 세 인코딩이 같은 스캐너를
    /// 쓴다 (실측: 픽스처 10종·한컴 번들 템플릿 전수에 DOCTYPE 0건).
    static func prologDeclaresInternalSubset(
        in data: Data, encoding: PrologEncoding
    ) -> Bool {
        var index = 0
        func unit(_ offset: Int = 0) -> UInt16? {
            encoding.unit(at: index + offset, in: data)
        }
        func matches(_ token: String) -> Bool {
            for (offset, scalar) in token.unicodeScalars.enumerated()
                where unit(offset) != UInt16(scalar.value)
            {
                return false
            }
            return true
        }
        func skip(past token: String) -> Bool {
            while unit() != nil, !matches(token) {
                index += 1
            }
            guard unit() != nil else {
                return false
            }
            index += token.unicodeScalars.count
            return true
        }

        if unit() == 0xFEFF {
            index += 1
        } else if unit() == 0xEF, unit(1) == 0xBB, unit(2) == 0xBF {
            index += 3
        }
        while let current = unit() {
            switch current {
            case 0x20, 0x09, 0x0A, 0x0D:
                index += 1
            case 0x3C where matches("<!--"):
                index += 4
                guard skip(past: "-->") else { return false }
            case 0x3C where matches("<?"):
                index += 2
                guard skip(past: "?>") else { return false }
            case 0x3C where matches("<!DOCTYPE"):
                index += 9
                return doctypeHasSubset(after: &index, encoding: encoding, data: data)
            default:
                // 루트 요소 시작 — DOCTYPE은 이 앞에만 올 수 있다.
                return false
            }
        }
        return false
    }

    /// `<!DOCTYPE` 뒤에서 선언이 끝나기(`>`) 전에 `[`가 오는지. 인용부호 안의
    /// 두 문자는 공개 식별자의 일부이므로 세지 않는다.
    private static func doctypeHasSubset(
        after index: inout Int, encoding: PrologEncoding, data: Data
    ) -> Bool {
        var quote: UInt16?
        while let character = encoding.unit(at: index, in: data) {
            if let open = quote {
                if character == open {
                    quote = nil
                }
            } else if character == 0x22 || character == 0x27 {
                quote = character
            } else if character == 0x5B {
                return true
            } else if character == 0x3E {
                return false
            }
            index += 1
        }
        return false
    }

    /// 접두사가 붙어도 승격하는 속성 — `hp:switch`의 분기 선택자 하나뿐이다.
    static let prefixedAttributeAllowlist: Set<String> = ["required-namespace"]

    /// 프리플라이트가 훑는 인코딩 — XML 처리기가 반드시 받아야 하는 UTF-8과
    /// UTF-16 두 갈래다.
    ///
    /// UTF-8 바이트열만 찾으면 UTF-16 파트에서 스캔이 통째로 빗나가고,
    /// Linux는 엔티티 선언 콜백을 부르지 않으므로 그 선언이 **성공한 파싱
    /// 속에서 참조 본문만 지운 채** 통과한다 (Linux 실측: UTF-16LE로 적은
    /// `before&custom;after`가 `beforeafter`로 파싱됨).
    enum PrologEncoding: CaseIterable {
        case utf8
        case utf16LittleEndian
        case utf16BigEndian

        /// 유닛 하나를 읽는다 (범위 밖이면 nil). 프롤로그 문법은 전부
        /// ASCII라 비-ASCII 유닛은 어떤 구문 문자와도 같지 않아 그냥 지나간다.
        func unit(at offset: Int, in data: Data) -> UInt16? {
            switch self {
            case .utf8:
                let index = data.startIndex + offset
                guard index < data.endIndex else {
                    return nil
                }
                return UInt16(data[index])
            case .utf16LittleEndian:
                let index = data.startIndex + offset * 2
                guard index + 1 < data.endIndex else {
                    return nil
                }
                return UInt16(data[index]) | (UInt16(data[index + 1]) << 8)
            case .utf16BigEndian:
                let index = data.startIndex + offset * 2
                guard index + 1 < data.endIndex else {
                    return nil
                }
                return (UInt16(data[index]) << 8) | UInt16(data[index + 1])
            }
        }
    }

    private func record(failure reason: String) {
        guard failure == nil else {
            return
        }
        failure = reason
        runningParser?.abortParsing()
    }

    private func appendText(_ string: String) {
        guard !stack.isEmpty, !string.isEmpty else {
            return
        }
        // 연속 텍스트 조각(엔티티 경계 등)은 하나로 합쳐 둔다 — content 조각
        // 수가 줄고, 소비자는 어차피 연결된 문자열을 기대한다.
        // 제자리 append여야 한다 — `existing + string`으로 새 문자열을 만들면
        // 조각이 많은 텍스트 노드(엔티티·CDATA 경계)에서 누적분을 매번 복사해
        // O(n²)가 되고, byte 한도는 그 CPU 증폭을 막지 못한다.
        let top = stack.count - 1
        let last = stack[top].content.count - 1
        if last >= 0, case var .text(existing) = stack[top].content[last] {
            stack[top].content[last] = .text("")
            existing += string
            stack[top].content[last] = .text(existing)
        } else {
            stack[top].content.append(.text(string))
        }
    }
}

extension HwpxXMLTreeParser: XMLParserDelegate {
    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName _: String?,
        attributes attributeDict: [String: String]
    ) {
        guard failure == nil else {
            return
        }
        guard stack.count < Self.maximumElementDepth else {
            record(failure: "element depth exceeds \(Self.maximumElementDepth)")
            return
        }
        // 속성 키는 접두사를 뗀 local name으로 통일한다 — OWPML 속성은 거의
        // 무접두사지만 `hp:required-namespace`처럼 접두사가 붙는 예가 있다.
        var attributes: [String: String] = [:]
        attributes.reserveCapacity(attributeDict.count)
        for (key, value) in attributeDict where !key.contains(":") {
            attributes[key] = value
        }
        // 접두사 붙은 속성은 **허용 목록만** 승격한다 — 요소를 (namespace,
        // local name)으로 엄격히 매칭하면서 속성만 접두사를 무시하면
        // `<hp:p ext:pageBreak="true">`가 진짜 쪽 나누기로 읽힌다.
        // 실물에서 접두사를 쓰는 OWPML 속성은 `hp:required-namespace`
        // 하나다 (픽스처 290건·한컴 템플릿 227건; 그 밖은 우리가 읽지 않는
        // `xml:space`뿐). 무접두사 키에 밀리는 것과 정렬 순회는 그대로 —
        // 사전 순회는 실행마다 무작위라 비결정 파싱이 된다.
        for (key, value) in attributeDict.sorted(by: { $0.key < $1.key })
            where key.contains(":")
        {
            let localKey = key.split(separator: ":").last.map(String.init) ?? key
            if Self.prefixedAttributeAllowlist.contains(localKey),
               attributes[localKey] == nil
            {
                attributes[localKey] = value
            }
        }
        // 무접두사 요소의 URI는 빈 문자열인데 그 값은 선언 없는 문서용
        // 폴백이라 어느 vocabulary 조회에도 걸린다 — namespace를 쓰는 파트에
        // 섞인 <p>가 hp:p로 파싱된다. 그런 파트에서는 sentinel로 갈라 낸다
        // (판정은 문서 순서 기준이라, 선언이 있는 파트는 루트에서 이미 참이다).
        let uri = namespaceURI ?? ""
        if !uri.isEmpty {
            sawNamespacedElement = true
        } else if !sawNamespacedElement {
            unqualifiedNodesBeforeNamespace += 1
        }
        stack.append(HwpxXMLNode(
            localName: elementName,
            namespaceURI: uri.isEmpty && sawNamespacedElement
                ? HwpxNamespace.unqualified : uri,
            attributes: attributes
        ))
    }

    func parser(
        _: XMLParser,
        didEndElement _: String,
        namespaceURI _: String?,
        qualifiedName _: String?
    ) {
        guard failure == nil, let finished = stack.popLast() else {
            return
        }
        if stack.isEmpty {
            root = finished
        } else {
            stack[stack.count - 1].content.append(.element(finished))
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        guard failure == nil else {
            return
        }
        appendText(string)
    }

    func parser(_: XMLParser, foundCDATA CDATABlock: Data) {
        guard failure == nil else {
            return
        }
        guard let string = String(data: CDATABlock, encoding: .utf8) else {
            record(failure: "CDATA block is not valid UTF-8")
            return
        }
        appendText(string)
    }

    func parser(
        _: XMLParser,
        foundInternalEntityDeclarationWithName name: String,
        value _: String?
    ) {
        // 선언된 엔티티는 성공 판정 속에서 참조 지점의 본문을 조용히 비운다
        // (실측: before&custom;after → "beforeafter") — 거부만이 안전하다.
        record(failure: "custom entity declaration '\(name)' is not supported")
    }

    func parser(
        _: XMLParser,
        foundExternalEntityDeclarationWithName name: String,
        publicID _: String?,
        systemID _: String?
    ) {
        record(failure: "custom entity declaration '\(name)' is not supported")
    }

    func parser(
        _: XMLParser,
        foundUnparsedEntityDeclarationWithName name: String,
        publicID _: String?,
        systemID _: String?,
        notationName _: String?
    ) {
        record(failure: "custom entity declaration '\(name)' is not supported")
    }

    func parser(_: XMLParser, parseErrorOccurred parseError: Error) {
        record(failure: String(describing: parseError))
    }
}

private extension HwpxXMLNode {
    /// 남은 빈 URI를 sentinel로 바꾼다 — 생성 시점 판정이 놓친 노드
    /// (`unqualifiedNodesBeforeNamespace`)를 위한 소급 패스다.
    ///
    /// 파트가 namespace를 쓸 때만 호출되므로 빈 URI는 전부 무접두사 요소다.
    /// 생성 시점에 이미 표시된 노드는 URI가 비어 있지 않아 그대로 지난다.
    func markingUnqualifiedElements() -> HwpxXMLNode {
        var node = self
        if node.namespaceURI.isEmpty {
            node.namespaceURI = HwpxNamespace.unqualified
        }
        node.content = node.content.map { piece in
            guard case let .element(child) = piece else {
                return piece
            }
            return .element(child.markingUnqualifiedElements())
        }
        return node
    }
}
