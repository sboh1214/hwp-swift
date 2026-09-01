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
        // 접두사만 있는 속성은 승격되지 않는다 — 허용 목록 밖이라
        // local name으로 접근되면 조작 속성이 조판을 바꾼다.
        expect(root.childElements.last?.attribute("tag")).to(beNil())
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
            expect(reason).to(contain("DOCTYPE"))
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
            <hh:paraPr xmlns:hh="http://www.hancom.co.kr/hwpml/2011/head" \
            xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph">\
            <hp:switch>\
            <hp:case hp:required-namespace="http://www.hancom.co.kr/hwpml/2016/HwpUnitChar">\
            <hh:margin unit="HWPUNIT"/></hp:case>\
            <hp:default><hh:margin unit="CHAR"/></hp:default>\
            </hp:switch></hh:paraPr>
            """
        )

        let margins = root.children(named: "margin")
        expect(margins.count) == 1
        expect(margins.first?.attributes["unit"]) == "HWPUNIT"
    }

    func testSwitchResolutionFallsBackToDefault() throws {
        let root = try parse(
            """
            <hh:paraPr xmlns:hh="http://www.hancom.co.kr/hwpml/2011/head" \
            xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph">\
            <hp:switch>\
            <hp:case hp:required-namespace="http://example.com/unsupported">\
            <hh:margin unit="FUTURE"/></hp:case>\
            <hp:default><hh:margin unit="CHAR"/></hp:default>\
            </hp:switch></hh:paraPr>
            """
        )

        let margins = root.children(named: "margin")
        expect(margins.count) == 1
        expect(margins.first?.attributes["unit"]) == "CHAR"
    }

    func testSwitchWithoutMatchingBranchIsRemoved() throws {
        let root = try parse(
            """
            <hh:paraPr xmlns:hh="http://www.hancom.co.kr/hwpml/2011/head" \
            xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph">\
            <hp:switch>\
            <hp:case hp:required-namespace="http://example.com/unsupported">\
            <hh:margin/></hp:case>\
            </hp:switch><hh:align/></hh:paraPr>
            """
        )

        expect(root.children(named: "margin")).to(beEmpty())
        expect(root.children(named: "align").count) == 1
    }

    func testNestedSwitchInsideChosenBranchIsResolved() throws {
        let root = try parse(
            """
            <hh:paraPr xmlns:hh="http://www.hancom.co.kr/hwpml/2011/head" \
            xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph">\
            <hp:switch><hp:default>\
            <hh:inner><hp:switch><hp:default><hh:margin unit="CHAR"/></hp:default>\
            </hp:switch></hh:inner>\
            </hp:default></hp:switch></hh:paraPr>
            """
        )

        let inner = try XCTUnwrap(root.firstChild(named: "inner"))
        expect(inner.children(named: "margin").count) == 1
    }

    func testUnqualifiedElementInNamespacedPartIsNotMatched() throws {
        // 무접두사 요소의 URI는 빈 문자열이고 그 폴백은 선언 없는 문서용이라,
        // 좁히지 않으면 정상 HWPX에 섞인 <p>가 hp:p로 파싱된다.
        let root = try parse(
            """
            <hs:sec xmlns:hs="http://www.hancom.co.kr/hwpml/2011/section" \
            xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph">\
            <hp:p id="1"/><p id="2"/></hs:sec>
            """
        )

        let paragraphs = root.paragraphChildren(named: "p")
        expect(paragraphs.count) == 1
        expect(paragraphs.first?.attributes["id"]) == "1"
        // 강등돼도 local name은 남아 진단에 실린다.
        let demoted = try XCTUnwrap(root.childElements.last)
        expect(demoted.localName) == "p"
        expect(demoted.isNamed("p")) == false
        expect(demoted.isNamed("p", in: HwpxNamespace.paragraph)) == false
    }

    func testUnqualifiedRootDeclaringPrefixesIsNotMatched() throws {
        // 루트가 접두사를 **선언만** 하고 자신은 무접두사면 생성 시점엔
        // 파트가 namespace를 쓰는지 알 수 없다 — 소급 표시가 없으면 이
        // 루트가 hh:head 게이트를 통과한다.
        let root = try parse(
            "<head xmlns:hh=\"http://www.hancom.co.kr/hwpml/2011/head\">"
                + "<hh:refList/></head>"
        )

        expect(root.isNamed("head", in: HwpxNamespace.head)) == false
        expect(root.localName) == "head"
        // 접두사를 쓴 자식은 그대로 head vocabulary다 (소급 표시가 건드리지 않는다).
        expect(root.firstChild(named: "refList")?.namespaceURI) == HwpxNamespace.head
    }

    func testUnqualifiedElementsBeforeTheFirstNamespacedSiblingAreDemoted() throws {
        // 주입이 첫 namespaced 요소보다 앞서면 생성 시점 판정이 놓친다 —
        // 순서만 바꾼 같은 공격이다.
        let root = try parse(
            "<sec xmlns:hp=\"http://www.hancom.co.kr/hwpml/2011/paragraph\">"
                + "<p id=\"1\"/><hp:p id=\"2\"/></sec>"
        )

        expect(root.paragraphChildren(named: "p").map { $0.attribute("id") }) == ["2"]
    }

    // MARK: - 속성 리더

    func testColorAttributeAcceptsEightDigitARGB() throws {
        // 한컴은 같은 자리에 8자리 ARGB도 쓴다 (noori의 테두리 #FF000000,
        // 번들 템플릿의 shadeColor #FFFFFFFF) — 거부하면 호출자 기본값으로
        // 떨어져 색이 조용히 바뀐다.
        let root = try parse(
            "<hh:borderFill xmlns:hh=\"http://www.hancom.co.kr/hwpml/2011/head\" "
                + "argb=\"#FF3366CC\" rgb=\"#3366CC\" absent=\"none\" short=\"#FF3366C\"/>"
        )

        expect(root.colorAttribute("argb")) == HwpColor(0x33, 0x66, 0xCC)
        // 알파만 다른 8자리는 7자리와 같은 색으로 접힌다.
        expect(root.colorAttribute("argb")) == root.colorAttribute("rgb")
        expect(root.colorAttribute("absent")).to(beNil())
        expect(root.colorAttribute("short")).to(beNil())
    }

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

    func testForeignBoundSelectorAttributeIsNotPromoted() throws {
        // 허용 목록이 이름만 보면 외래 vocabulary에 바인딩된
        // ext:required-namespace가 승격되어 hp:switch 해소에서 위조 case가
        // default 분기를 대체한다 — 요소 엄격 매칭과 같은 규약이다 (P2).
        let root = try parse(
            """
            <case xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph" \
            xmlns:ext="urn:foreign" ext:required-namespace="urn:x"/>
            """
        )

        expect(root.attributes["required-namespace"]).to(beNil())
    }

    func testSelectorAttributePromotionFollowsBindingNotPrefixSpelling() throws {
        // 게이트는 바인딩이지 접두사 문자열이 아니다 — x:가 paragraph에
        // 바인딩된 문서는 합법이고 hp: 관례와 같게 읽혀야 한다.
        let root = try parse(
            """
            <case xmlns:x="http://www.hancom.co.kr/hwpml/2011/paragraph" \
            x:required-namespace="urn:x"/>
            """
        )

        expect(root.attributes["required-namespace"]) == "urn:x"
    }

    func testForeignBoundSelectorDoesNotChooseTheSwitchCase() throws {
        // 종단 확인 — 외래 바인딩 선택자는 case를 고르지 못하고 default의
        // 진짜 내용이 남는다.
        let root = try parse(
            "<hp:root xmlns:hp=\"http://www.hancom.co.kr/hwpml/2011/paragraph\" "
                + "xmlns:ext=\"urn:foreign\"><hp:switch>"
                + "<hp:case ext:required-namespace="
                + "\"http://www.hancom.co.kr/hwpml/2016/HwpUnitChar\">"
                + "<hp:forged/></hp:case>"
                + "<hp:default><hp:real/></hp:default>"
                + "</hp:switch></hp:root>"
        )

        expect(root.childElements.map(\.localName)) == ["real"]
    }

    func testEntityDeclarationIsRejectedInUTF16Encodings() {
        // UTF-8 바이트만 훑으면 UTF-16 파트에서 스캔이 빗나가고, Linux는
        // 엔티티 콜백을 부르지 않아 참조 본문만 조용히 사라진다 (실측:
        // before&custom;after → beforeafter).
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-16\"?>"
            + "<!DOCTYPE doc [<!ENTITY custom \"SECRET\">]>"
            + "<doc>before&custom;after</doc>"
        for littleEndian in [true, false] {
            var data = Data(littleEndian ? [0xFF, 0xFE] : [0xFE, 0xFF])
            for unit in xml.utf16 {
                let low = UInt8(truncatingIfNeeded: unit)
                let high = UInt8(truncatingIfNeeded: unit >> 8)
                data.append(littleEndian ? low : high)
                data.append(littleEndian ? high : low)
            }

            expect {
                _ = try HwpxXMLTreeParser.parse(data, entry: "Contents/header.xml")
            }.to(throwError { error in
                guard case let HwpError.invalidXML(_, reason) = error else {
                    return fail("Expected invalidXML, got \(error)")
                }
                // 델리게이트 사유는 이름을 담는다 — 이름이 없으면 바이트
                // 프리플라이트가 잡은 것이라 Linux에서도 같은 판정이다.
                expect(reason) == "DOCTYPE internal subset is not supported"
            })
        }
    }

    func testBenignDoctypeWithoutInternalSubsetIsAccepted() throws {
        // 내부 서브셋이 없는 DOCTYPE은 엔티티를 선언할 수 없다 (외부 DTD는
        // shouldResolveExternalEntities=false로 무력) — 본문에 <!ENTITY
        // 문자열이 있어도 거부하면 오탐이다.
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
            + "<!DOCTYPE hh:head SYSTEM \"owpml.dtd\">"
            + "<hh:head xmlns:hh=\"http://www.hancom.co.kr/hwpml/2011/head\">"
            + "<![CDATA[<!ENTITY custom \"SECRET\">]]></hh:head>"
        let root = try HwpxXMLTreeParser.parse(
            Data(xml.utf8), entry: "Contents/header.xml"
        )

        expect(root.isNamed("head", in: HwpxNamespace.head)) == true
    }

    func testFakeDoctypeInACommentDoesNotShadowTheRealOne() {
        // 첫 매치만 보면 주석 속 가짜 DOCTYPE이 뒤따르는 진짜 선언을 가린다 —
        // Linux는 엔티티 선언 콜백이 없어 이 우회가 곧 조용한 내용 치환이다.
        let xml = "<?xml version=\"1.0\"?><!-- <!DOCTYPE fake> -->"
            + "<!DOCTYPE doc [<!ENTITY custom \"SECRET\">]>"
            + "<doc>before&custom;after</doc>"
        expect {
            _ = try HwpxXMLTreeParser.parse(
                Data(xml.utf8), entry: "Contents/header.xml"
            )
        }.to(throwError { error in
            guard case let HwpError.invalidXML(_, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            // 이름이 없으면 바이트 프리플라이트가 잡은 것이다 (델리게이트 아님).
            expect(reason) == "DOCTYPE internal subset is not supported"
        })
    }

    func testCommentedDoctypeFragmentDoesNotRejectTheDocument() throws {
        // 주석 안의 문서화용 조각은 선언이 아니다 — 매치를 모두 훑던 방식은
        // `[`를 보고 유효 문서를 거부했다 (프롤로그 어휘 스캔으로 닫힌다).
        let xml = "<?xml version=\"1.0\"?><!-- <!DOCTYPE example [ -->"
            + "<hh:head xmlns:hh=\"http://www.hancom.co.kr/hwpml/2011/head\"/>"
        let root = try HwpxXMLTreeParser.parse(
            Data(xml.utf8), entry: "Contents/header.xml"
        )

        expect(root.isNamed("head", in: HwpxNamespace.head)) == true
    }
}
