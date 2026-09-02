@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// DOCTYPE·엔티티 바이트 프리플라이트 — 파서가 **성공한 파스 속에서** 본문을
/// 조용히 바꾸는 두 경로(내부 서브셋 선언·외부 식별자)를 막는지 잠근다.
/// 트리 구성 자체는 `HwpxXMLTreeParserTests`가 맡는다.
final class HwpxXMLDoctypeTests: XCTestCase {
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

    func testDoctypeIsRejectedInUTF16Encodings() {
        // UTF-8 바이트만 훑으면 UTF-16 파트에서 스캔이 빗나가고, Linux는
        // 엔티티 콜백을 부르지 않아 참조 본문만 조용히 사라진다 (실측:
        // before&custom;after → beforeafter). 두 거부 사유가 같은 스캐너를
        // 쓰므로 UTF-16에서도 함께 잠근다.
        let cases = [
            (
                "<!DOCTYPE doc [<!ENTITY custom \"SECRET\">]>",
                "DOCTYPE internal subset is not supported"
            ),
            (
                "<!DOCTYPE doc SYSTEM \"owpml.dtd\">",
                "DOCTYPE external identifier is not supported"
            ),
        ]
        for (declaration, expected) in cases {
            let xml = "<?xml version=\"1.0\" encoding=\"UTF-16\"?>" + declaration
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
                    expect(reason) == expected
                })
            }
        }
    }

    func testPartInAnUnscannableEncodingIsRejected() {
        // 스캐너가 ASCII 호환 바이트열만 훑으므로 그렇지 않은 인코딩으로 적으면
        // DOCTYPE 판정이 통째로 우회된다 — libxml2는 XML 선언의 encoding을 보고
        // 그런 파트도 파싱한다. 아래는 IBM037(EBCDIC)로 적은
        // `<!ENTITY custom "ATTACKER">` 문서이고, 실측상 이 우회는 플랫폼마다
        // 다른 형태로 열려 있었다: Linux는 이 내부 서브셋 형태를, macOS는 외부
        // 식별자 형태를 조용히 통과시켜 `before&custom;after`가 "beforeafter"가
        // 됐다. XML 문서는 (BOM 뒤) 공백이나 `<`로만 시작할 수 있으므로 세
        // 인코딩 중 어느 것으로도 안 읽히면 파트째로 거부한다.
        let ebcdic = Data([
            0x4C, 0x6F, 0xA7, 0x94, 0x93, 0x40, 0xA5, 0x85, 0x99, 0xA2, 0x89, 0x96,
            0x95, 0x7E, 0x7F, 0xF1, 0x4B, 0xF0, 0x7F, 0x40, 0x85, 0x95, 0x83, 0x96,
            0x84, 0x89, 0x95, 0x87, 0x7E, 0x7F, 0xC9, 0xC2, 0xD4, 0xF0, 0xF3, 0xF7,
            0x7F, 0x6F, 0x6E, 0x4C, 0x5A, 0xC4, 0xD6, 0xC3, 0xE3, 0xE8, 0xD7, 0xC5,
            0x40, 0x84, 0x96, 0x83, 0x40, 0xBA, 0x4C, 0x5A, 0xC5, 0xD5, 0xE3, 0xC9,
            0xE3, 0xE8, 0x40, 0x83, 0xA4, 0xA2, 0xA3, 0x96, 0x94, 0x40, 0x7F, 0xC1,
            0xE3, 0xE3, 0xC1, 0xC3, 0xD2, 0xC5, 0xD9, 0x7F, 0x6E, 0xBB, 0x6E, 0x4C,
            0x84, 0x96, 0x83, 0x6E, 0x82, 0x85, 0x86, 0x96, 0x99, 0x85, 0x50, 0x83,
            0xA4, 0xA2, 0xA3, 0x96, 0x94, 0x5E, 0x81, 0x86, 0xA3, 0x85, 0x99, 0x4C,
            0x61, 0x84, 0x96, 0x83, 0x6E,
        ])

        expect {
            _ = try HwpxXMLTreeParser.parse(ebcdic, entry: "Contents/section0.xml")
        }.to(throwError { error in
            guard case let HwpError.invalidXML(_, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            expect(reason) == "unsupported XML encoding"
        })
    }

    func testLeadingWhitespaceBeforeTheRootElementIsAccepted() {
        // 인코딩 게이트는 "첫 유닛이 `<`"가 아니라 프롤로그 스캔 결과로 판정한다
        // — XML 선언 없이 공백·개행으로 시작하는 문서는 합법이다.
        expect {
            _ = try HwpxXMLTreeParser.parse(
                Data("\n  <hh:head xmlns:hh=\"http://www.hancom.co.kr/hwpml/2011/head\"/>".utf8),
                entry: "Contents/header.xml"
            )
        }.toNot(throwError())
    }

    func testExternalDoctypeEntityReferenceIsRejected() {
        // 외부 DTD를 매달면 **선언이 없어도** 미선언 엔티티 참조가 오류에서
        // 경고로 격하된다 — macOS 실측: 이 입력이 성공 파스로 통과하며
        // 본문이 "beforeafter", 속성값도 "beforeafter"가 됐다 (Linux는 던져
        // 플랫폼이 갈린다). shouldResolveExternalEntities=false는 실체를
        // 가져오지 않을 뿐 이 격하를 막지 못하므로 바이트에서 거른다.
        let xml = "<!DOCTYPE doc SYSTEM \"owpml.dtd\">"
            + "<doc a=\"before&custom;after\">before&custom;after</doc>"

        expect {
            _ = try HwpxXMLTreeParser.parse(
                Data(xml.utf8), entry: "Contents/section0.xml"
            )
        }.to(throwError { error in
            guard case let HwpError.invalidXML(_, reason) = error else {
                return fail("Expected invalidXML, got \(error)")
            }
            expect(reason) == "DOCTYPE external identifier is not supported"
        })
    }

    func testExternalDoctypeIsRejectedForBothIdentifierForms() {
        // PUBLIC 식별자도 외부 서브셋을 매단다 — 인용부호가 곧 외부 식별자다
        // (선언 머리에서 인용 문자열은 SYSTEM·PUBLIC에만 올 수 있다).
        let declarations = [
            "<!DOCTYPE hh:head SYSTEM \"owpml.dtd\">",
            "<!DOCTYPE hh:head PUBLIC \"-//HANCOM//DTD OWPML//KO\" \"owpml.dtd\">",
        ]
        for declaration in declarations {
            let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" + declaration
                + "<hh:head xmlns:hh=\"http://www.hancom.co.kr/hwpml/2011/head\"/>"

            expect {
                _ = try HwpxXMLTreeParser.parse(
                    Data(xml.utf8), entry: "Contents/header.xml"
                )
            }.to(throwError { error in
                guard case let HwpError.invalidXML(_, reason) = error else {
                    return fail("Expected invalidXML, got \(error)")
                }
                expect(reason) == "DOCTYPE external identifier is not supported"
            })
        }
    }

    func testBareDoctypeWithoutExternalIdentifierIsAccepted() throws {
        // 외부 식별자도 내부 서브셋도 없는 DOCTYPE은 아무것도 선언하지 못하고
        // 격하도 열지 않는다 (실측: 미선언 참조가 macOS·Linux 모두 오류) —
        // 본문에 <!ENTITY 문자열이 있어도 거부하면 오탐이다.
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
            + "<!DOCTYPE hh:head>"
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
