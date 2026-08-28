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
