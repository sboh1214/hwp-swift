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
    private weak var runningParser: XMLParser?

    /// XML 바이트를 파싱해 루트 요소를 돌려준다. `hp:switch`는 여기서 이미
    /// 해소되어 매퍼는 조건 분기를 보지 않는다.
    static func parse(_ data: Data, entry: String) throws -> HwpxXMLNode {
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
        return root.resolvingSwitches()
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
        for (key, value) in attributeDict {
            let localKey = key.split(separator: ":").last.map(String.init) ?? key
            if attributes[localKey] == nil {
                attributes[localKey] = value
            }
        }
        stack.append(HwpxXMLNode(
            localName: elementName,
            namespaceURI: namespaceURI ?? "",
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

    func parser(_: XMLParser, parseErrorOccurred parseError: Error) {
        record(failure: String(describing: parseError))
    }
}
