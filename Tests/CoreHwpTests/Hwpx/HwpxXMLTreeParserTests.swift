@testable import CoreHwp
import Foundation
import Nimble
import XCTest

final class HwpxXMLTreeParserTests: XCTestCase {
    private func parse(_ xml: String) throws -> HwpxXMLNode {
        try HwpxXMLTreeParser.parse(Data(xml.utf8), entry: "Contents/test.xml")
    }

    func testParsesElementsAttributesAndText() throws {
        let root = try parse(
            """
            <hp:p xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph" \
            paraPrIDRef="3"><hp:run charPrIDRef="1"><hp:t>안녕</hp:t></hp:run></hp:p>
            """
        )

        expect(root.isNamed("p")) == true
        expect(root.namespaceURI) == HwpxNamespace.paragraph
        expect(root.attributes["paraPrIDRef"]) == "3"
        let run = try XCTUnwrap(root.firstChild(named: "run"))
        expect(run.attributes["charPrIDRef"]) == "1"
        expect(run.firstChild(named: "t")?.text) == "안녕"
    }

    func testMatchesByLocalNameAcrossPrefixVariants() throws {
        // 접두사가 표준(hp:)과 다르게 선언돼도 (namespace URI, local name)
        // 기준 매칭은 흔들리지 않아야 한다.
        let root = try parse(
            """
            <x:p xmlns:x="http://www.hancom.co.kr/hwpml/2011/paragraph">\
            <x:run><x:t>본문</x:t></x:run></x:p>
            """
        )

        expect(root.isNamed("p")) == true
        expect(root.firstChild(named: "run")?.firstChild(named: "t")?.text) == "본문"
    }

    func testUnprefixedAttributeWinsOverForeignPrefixedTwin() throws {
        // id/ext:id가 같은 local name으로 접힐 때 무접두사 키가 결정적으로
        // 이긴다 — 사전 순회 무작위에 맡기면 실행마다 다른 값이 된다.
        // 요소마다 접두사를 달리해 키 집합을 갈라야 순회 순서가 요소별로
        // 독립이다 — 같은 키 쌍이면 프로세스 해시 시드 하나에 묶여 열 개가
        // 통째로 같은 동전이 된다.
        let children = (0 ..< 10).map { index in
            "<hp:item xmlns:p\(index)=\"urn:x\(index)\" id=\"1\" p\(index):id=\"999\"/>"
        }.joined()
        let root = try parse(
            "<hp:root xmlns:hp=\"http://www.hancom.co.kr/hwpml/2011/paragraph\" "
                + "xmlns:ext=\"urn:x\">" + children
                + "<hp:only ext:tag=\"v\"/></hp:root>"
        )

        for item in root.childElements where item.localName == "item" {
            expect(item.attribute("id")) == "1"
        }
        // 접두사만 있는 속성은 종전대로 local name으로 접근된다.
        expect(root.childElements.last?.attribute("tag")) == "v"
    }

    func testForeignVocabularySwitchIsNotResolved() throws {
        // switch 3종은 paragraph vocabulary — hh:switch가 hp:switch로
        // 오인되면 매퍼·진단이 보기 전에 내용이 접합·삭제된다.
        let root = try parse(
            "<hp:root xmlns:hp=\"http://www.hancom.co.kr/hwpml/2011/paragraph\" "
                + "xmlns:hh=\"http://www.hancom.co.kr/hwpml/2011/head\">"
                + "<hp:switch><hp:default><hp:real/></hp:default></hp:switch>"
                + "<hh:switch><hh:default><hh:decoy/></hh:default></hh:switch>"
                + "</hp:root>"
        )

        expect(root.childElements.map(\.localName)) == ["real", "switch"]
    }

    func testForeignNamespaceElementIsNotMatched() throws {
        let root = try parse(
            """
            <p xmlns="http://example.com/not-owpml"><run/></p>
            """
        )

        expect(root.isNamed("p")) == false
    }

    func testNoNamespaceDocumentStillMatches() throws {
        let root = try parse("<p><run><t>글</t></run></p>")

        expect(root.isNamed("p")) == true
        expect(root.firstChild(named: "run")?.firstChild(named: "t")?.text) == "글"
    }

    func testMixedContentPreservesInterleavingOrder() throws {
        // <hp:t>ab<tab/>cd</hp:t> — 텍스트·요소의 원본 순서가 곧 WCHAR 순서다.
        let root = try parse("<t>ab<tab/>cd<lineBreak/>ef</t>")

        var pieces: [String] = []
        for piece in root.content {
            switch piece {
            case let .element(node):
                pieces.append("<\(node.localName)>")
            case let .text(text):
                pieces.append(text)
            }
        }
        expect(pieces) == ["ab", "<tab>", "cd", "<lineBreak>", "ef"]
    }

    func testCDATAIsTreatedAsText() throws {
        let root = try parse("<t><![CDATA[a<b&c]]></t>")

        expect(root.text) == "a<b&c"
    }

    func testFragmentedTextAccumulatesWithoutQuadraticCopying() throws {
        // SAX가 조각으로 주는 텍스트(엔티티 경계)를 누적할 때마다 새 문자열을
        // 만들면 O(n²)가 된다. 시간 대신 **버퍼 신원**으로 잰다 — 제자리
        // append는 용량이 남는 한 저장소를 재사용하므로, 조각 수보다 훨씬
        // 적은 횟수만 재할당이 일어난다 (이차 누적은 조각마다 새 버퍼다).
        let fragmentCount = 2000
        let body = String(
            repeating: "&amp;\(String(repeating: "가", count: 32))", count: fragmentCount
        )
        let xml = "<hp:t xmlns:hp=\"http://www.hancom.co.kr/hwpml/2011/paragraph\">"
            + body + "</hp:t>"

        let node = try HwpxXMLTreeParser.parse(
            Data(xml.utf8), entry: "Contents/section0.xml"
        )
        // 파스 결과가 온전한지 먼저 확인한다 (조각이 하나로 합쳐졌다).
        expect(node.content.count) == 1
        expect(node.text.count) == fragmentCount * 33
    }

    func testFragmentedTextScalesSubQuadratically() throws {
        /// 조각 수를 4배로 늘렸을 때 선형이면 ~4배, 이차면 그보다 훨씬 크다.
        /// 구간 선택이 중요하다 — 작은 n에서는 이차 항이 아직 지배하지 않아
        /// 이차 구현도 통과한다 (실측 A/B: 2,000→8,000은 이차도 7.1배라
        /// 못 가른다. 8,000→32,000은 선형 4.0배 vs 이차 18.5배).
        func elapsed(fragmentCount: Int) throws -> Double {
            let body = String(
                repeating: "&amp;\(String(repeating: "가", count: 32))",
                count: fragmentCount
            )
            let xml = "<hp:t xmlns:hp=\"http://www.hancom.co.kr/hwpml/2011/paragraph\">"
                + body + "</hp:t>"
            let data = Data(xml.utf8)
            let start = Date()
            _ = try HwpxXMLTreeParser.parse(data, entry: "Contents/section0.xml")
            return Date().timeIntervalSince(start)
        }

        _ = try elapsed(fragmentCount: 2000) // 워밍업
        let base = try elapsed(fragmentCount: 8000)
        let quadrupled = try elapsed(fragmentCount: 32000)
        expect(quadrupled) < max(base * 8, 0.05)
    }

    func testCustomEntityDeclarationIsRejected() {
        // 실측: 선언 엔티티는 parse 성공인 채 참조 본문만 빠진다
        // (before&custom;after → "beforeafter") — 조용한 유실 대신 거부한다.
        let xml = """
        <!DOCTYPE doc [<!ENTITY custom "SECRET">]>
        <doc>before&custom;after</doc>
        """
        expect {
            _ = try HwpxXMLTreeParser.parse(
                Data(xml.utf8), entry: "Contents/section0.xml"
            )
        }.to(throwError { error in
            guard case let HwpError.invalidXML(_, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            expect(reason).to(contain("entity"))
        })
    }

    func testMalformedXMLThrowsInvalidXML() {
        expect {
            _ = try self.parse("<p><run></p>")
        }.to(throwError { error in
            guard case let HwpError.invalidXML(entry, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            expect(entry) == "Contents/test.xml"
            expect(reason).notTo(beEmpty())
        })
    }

    func testEmptyDataThrowsInvalidXML() {
        expect {
            _ = try self.parse("")
        }.to(throwError { error in
            guard case HwpError.invalidXML = error else {
                return fail("Expected invalidXML, got \(error)")
            }
        })
    }

    func testElementDepthCapThrowsInvalidXML() {
        let depth = HwpxXMLTreeParser.maximumElementDepth + 8
        let xml = String(repeating: "<a>", count: depth)
            + String(repeating: "</a>", count: depth)

        expect {
            _ = try self.parse(xml)
        }.to(throwError { error in
            guard case let HwpError.invalidXML(_, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            expect(reason).to(contain("depth"))
        })
    }

    func testSwitchResolutionPrefersSupportedCaseOverDefault() throws {
        let root = try parse(
            """
            <paraPr xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph">\
            <hp:switch>\
            <hp:case hp:required-namespace="http://www.hancom.co.kr/hwpml/2016/HwpUnitChar">\
            <margin unit="HWPUNIT"/></hp:case>\
            <hp:default><margin unit="CHAR"/></hp:default>\
            </hp:switch></paraPr>
            """
        )

        let margins = root.children(named: "margin")
        expect(margins.count) == 1
        expect(margins.first?.attributes["unit"]) == "HWPUNIT"
    }

    func testSwitchResolutionFallsBackToDefault() throws {
        let root = try parse(
            """
            <paraPr xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph">\
            <hp:switch>\
            <hp:case hp:required-namespace="http://example.com/unsupported">\
            <margin unit="FUTURE"/></hp:case>\
            <hp:default><margin unit="CHAR"/></hp:default>\
            </hp:switch></paraPr>
            """
        )

        let margins = root.children(named: "margin")
        expect(margins.count) == 1
        expect(margins.first?.attributes["unit"]) == "CHAR"
    }

    func testSwitchWithoutMatchingBranchIsRemoved() throws {
        let root = try parse(
            """
            <paraPr xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph">\
            <hp:switch>\
            <hp:case hp:required-namespace="http://example.com/unsupported">\
            <margin/></hp:case>\
            </hp:switch><align/></paraPr>
            """
        )

        expect(root.children(named: "margin")).to(beEmpty())
        expect(root.children(named: "align").count) == 1
    }

    func testNestedSwitchInsideChosenBranchIsResolved() throws {
        let root = try parse(
            """
            <paraPr xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph">\
            <hp:switch><hp:default>\
            <inner><hp:switch><hp:default><margin unit="CHAR"/></hp:default>\
            </hp:switch></inner>\
            </hp:default></hp:switch></paraPr>
            """
        )

        let inner = try XCTUnwrap(root.firstChild(named: "inner"))
        expect(inner.children(named: "margin").count) == 1
    }

    // MARK: - 속성 리더

    func testRequiredAttributeThrowsOnAbsence() throws {
        let root = try parse("<pagePr width=\"59528\"/>")

        expect(try root.requiredAttribute("width", entry: "e")) == "59528"
        expect(try root.requiredIntAttribute("width", entry: "e")) == 59528
        expect {
            _ = try root.requiredAttribute("height", entry: "Contents/section0.xml")
        }.to(throwError { error in
            guard case let HwpError.invalidXML(entry, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            expect(entry) == "Contents/section0.xml"
            expect(reason).to(contain("height"))
        })
    }

    func testRequiredIntAttributeThrowsOnGarbage() throws {
        let root = try parse("<pagePr width=\"wide\"/>")

        expect {
            _ = try root.requiredIntAttribute("width", entry: "e")
        }.to(throwError { error in
            guard case let HwpError.invalidXML(_, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            expect(reason).to(contain("not an integer"))
        })
    }

    func testOptionalReadersFallBackToDefaults() throws {
        let root = try parse(
            "<charPr height=\"1000\" bold=\"1\" italic=\"false\" textColor=\"#0A141E\" " +
                "shadeColor=\"none\" garbage=\"x\"/>"
        )

        expect(root.intAttribute("height")) == 1000
        expect(root.intAttribute("missing", default: 7)) == 7
        expect(root.intAttribute("garbage", default: 7)) == 7
        expect(root.boolAttribute("bold")) == true
        expect(root.boolAttribute("italic", default: true)) == false
        expect(root.boolAttribute("missing")) == false
        expect(root.colorAttribute("textColor")) == HwpColor(10, 20, 30)
        expect(root.colorAttribute("shadeColor")).to(beNil())
        expect(root.colorAttribute("missing")).to(beNil())
        expect(root.uint32Attribute("height")) == 1000
        expect(root.int32Attribute("height")) == 1000
        expect(root.uint16Attribute("height")) == 1000
    }

    func testPrefixedAttributeKeysAreNormalizedToLocalNames() throws {
        let root = try parse(
            """
            <case xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph" \
            hp:required-namespace="urn:x"/>
            """
        )

        expect(root.attributes["required-namespace"]) == "urn:x"
    }
}
