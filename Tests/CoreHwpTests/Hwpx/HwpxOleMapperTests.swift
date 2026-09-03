@testable import CoreHwp
import Foundation
import Nimble
import XCTest

/// `hp:ole` typed 매핑 (#134) — 표 118 payload 합성·BinItem 리맵·미소비 자식
/// 강등·강등 표 제거·chart 변환 쌍 실물을 고정한다.
final class HwpxOleMapperTests: XCTestCase {
    private func makeContext(
        options: HwpLoadOptions = .default,
        binItemIds: [String: UInt16] = [:]
    ) -> HwpxMappingContext {
        HwpxObjectFixture.makeContext(options: options, binItemIds: binItemIds)
    }

    private func parse(_ xml: String) throws -> HwpxXMLNode {
        try HwpxObjectFixture.parse(xml)
    }

    private var oleXML: String {
        HwpxObjectFixture.oleXML
    }

    private func oleElement(
        of control: HwpShapeControl
    ) throws -> HwpShapeComponentOLE {
        try XCTUnwrap(control.shapeComponentArray.first?.oleArray.first)
    }

    /// HWP 쌍 manifest `olePayloadPrefixBytes` + BinData ID — 속성 1(CONTENT·
    /// UNKNOWN), extent 7200×7200, BinData ID 1.
    private let chartPayloadPrefix: [UInt8] = [
        1, 0, 0, 0, 0x20, 0x1C, 0, 0, 0x20, 0x1C, 0, 0, 1, 0,
    ]

    func testOleMapsTypedControlAndBinItemJoin() throws {
        let control = HwpxOleMapper.map(
            try parse(oleXML),
            context: makeContext(binItemIds: ["ole1": 1])
        )

        expect(control.ctrlId) == HwpCommonCtrlId.ole
        let common = try XCTUnwrap(control.commonCtrlProperty)
        expect(common.commonCtrlId) == HwpCommonCtrlId.ole
        expect(common.width) == 32250
        expect(common.height) == 18750
        expect(common.propertyInfo.textWrap) == HwpCommonCtrlTextWrap.square
        expect(common.propertyInfo.numberingCategory) == HwpCommonCtrlNumberingCategory.figure

        let component = try XCTUnwrap(control.shapeComponentArray.first)
        expect(component.ctrlId) == HwpCommonCtrlId.ole
        expect(component.ctrlIdName) == "ole"
        expect(component.pictureArray).to(beEmpty())
        expect(component.oleRecords).to(beEmpty())
        expect(component.oleArray.count) == 1

        let ole = try oleElement(of: control)
        // 하류(`HwpPaginator.chartFrame`)가 실제로 읽는 필드 — BinItem 조인 키.
        expect(ole.binaryDataId) == 1
        // 표 118 실물 레이아웃 26바이트: 선두 14바이트가 HWP 쌍 payload와 같다.
        expect(ole.rawPayload.count) == 26
        expect(Array(ole.rawPayload.prefix(14))) == chartPayloadPrefix
        expect(Array(ole.rawPayload.suffix(12))) == [UInt8](repeating: 0, count: 12)
        // 바이너리와 같은 절단 — 속성 UINT32 뒤가 rawTrailing이다.
        expect(ole.rawTrailing) == Data(ole.rawPayload.dropFirst(4))
        expect(try ole.rawPayload.readLittleEndianUInt16(at: 12)) == 1
    }

    func testOlePropertyBitsFollowTable119() throws {
        func property(_ attributes: String) throws -> UInt32 {
            let xml = """
            <hp:ole xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph" \(attributes)/>
            """
            let control = HwpxOleMapper.map(try parse(xml), context: makeContext())
            return try oleElement(of: control).rawPayload.readLittleEndianUInt32(at: 0)
        }

        // 생략 → CONTENT(1) — 한글.app 저장본이 쓰는 유일한 값.
        expect(try property("")) == 1
        // 이름은 한컴 모델 `g_OleDrawAspectList`의 직렬화 문자열 그대로다 —
        // 밑줄이 빠지면 실물 문서의 값이 조용히 0으로 접힌다.
        expect(try property("drawAspect=\"THUMB_NAIL\"")) == 2
        expect(try property("drawAspect=\"ICON\"")) == 4
        expect(try property("drawAspect=\"DOC_PRINT\"")) == 8
        // 미지 이름은 추측하지 않는다 — 붙여 쓴 표기는 스키마에 없다.
        expect(try property("drawAspect=\"BOGUS\"")) == 0
        expect(try property("drawAspect=\"THUMBNAIL\"")) == 0
        expect(try property("drawAspect=\"DOCPRINT\"")) == 0
        expect(try property("hasMoniker=\"1\"")) == 1 | 1 << 8
        // 수식이 아닌 개체의 베이스라인은 그대로 실린다 — 스펙상 이 종류는
        // 베이스라인을 갖지 않고, chart 쌍 실측(HWPX "0" ↔ HWP raw 0)이 근거다.
        expect(try property("eqBaseLine=\"0\"")) == 1
        expect(try property("eqBaseLine=\"50\"")) == 1 | 50 << 9
        // 7비트 필드 — 범위 밖은 클램프 (마스킹이면 999 → 103으로 뒤틀린다).
        expect(try property("eqBaseLine=\"999\"")) == 1 | 127 << 9
        expect(try property("eqBaseLine=\"-4\"")) == 1
        expect(try property("objectType=\"UNKNOWN\"")) == 1
        expect(try property("objectType=\"EMBEDDED\"")) == 1 | 1 << 16
        expect(try property("objectType=\"LINK\"")) == 1 | 2 << 16
        expect(try property("objectType=\"STATIC\"")) == 1 | 3 << 16
        expect(try property("objectType=\"EQUATION\"")) == 1 | 4 << 16
        expect(try property("objectType=\"BOGUS\"")) == 1
        // 전부 함께 — 필드가 서로 침범하지 않는다. 기대값은 문장으로 쪼개
        // 미리 세운다: 항이 많은 리터럴 연결식은 CI 타입 체커가 시간 안에 풀지
        // 못해 로컬에서만 통과하는 컴파일 오류가 된다 (루트 AGENTS.md).
        let drawAspectICON: UInt32 = 4
        let monikerBit: UInt32 = 1 << 8
        let baseline101: UInt32 = 101 << 9
        let objectTypeLINK: UInt32 = 2 << 16
        let combined = drawAspectICON | monikerBit | baseline101 | objectTypeLINK
        expect(try property(
            "drawAspect=\"ICON\" hasMoniker=\"true\" eqBaseLine=\"101\" objectType=\"LINK\""
        )) == combined
    }

    /// 수식 OLE의 베이스라인만 표 119 코드로 변환한다 — 스펙의 "1~101이
    /// 0~100%"이고, 한컴 모델의 XML 기본값 85가 그 값이 백분율임을 가리킨다.
    /// 수식이 아닌 종류는 스펙상 베이스라인을 갖지 않아 그대로 싣는다(chart 쌍
    /// 실측). 두 경로를 한 테스트에서 나란히 고정한다.
    func testEquationBaselineEncodesPercentIntoTable119Code() throws {
        func baseline(_ attributes: String) throws -> UInt32 {
            let xml = """
            <hp:ole xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph" \(attributes)/>
            """
            let control = HwpxOleMapper.map(try parse(xml), context: makeContext())
            let property = try oleElement(of: control)
                .rawPayload.readLittleEndianUInt32(at: 0)
            return (property >> 9) & 0x7F
        }

        // 수식: 백분율 + 1 (0% → 1, 50% → 51, 100% → 101).
        expect(try baseline("objectType=\"EQUATION\" eqBaseLine=\"0\"")) == 1
        expect(try baseline("objectType=\"EQUATION\" eqBaseLine=\"50\"")) == 51
        expect(try baseline("objectType=\"EQUATION\" eqBaseLine=\"100\"")) == 101
        // 범위 밖은 0~100으로 좁힌 뒤 인코딩한다 — 101을 넘는 코드는 없다.
        expect(try baseline("objectType=\"EQUATION\" eqBaseLine=\"999\"")) == 101
        expect(try baseline("objectType=\"EQUATION\" eqBaseLine=\"-4\"")) == 1
        // 생략·형식 오류는 raw 0 = "디폴트(85%)" — 모델 기본값 85와 같은 뜻이다.
        expect(try baseline("objectType=\"EQUATION\"")) == 0
        expect(try baseline("objectType=\"EQUATION\" eqBaseLine=\"abc\"")) == 0

        // 수식이 아닌 종류는 게이트 밖이다 — 같은 "50"이 51이 되지 않는다.
        expect(try baseline("objectType=\"UNKNOWN\" eqBaseLine=\"50\"")) == 50
        expect(try baseline("objectType=\"EMBEDDED\" eqBaseLine=\"50\"")) == 50
        expect(try baseline("eqBaseLine=\"50\"")) == 50
    }

    func testDanglingBinaryItemFallsBackToZero() throws {
        // manifest에 없는 참조 → 0 (스트림 없음 → 도형 상자 폴백, 그림과 같다).
        let control = HwpxOleMapper.map(try parse(oleXML), context: makeContext())
        let ole = try oleElement(of: control)
        expect(ole.binaryDataId) == 0
        expect(try ole.rawPayload.readLittleEndianUInt16(at: 12)) == 0
    }

    func testExtentFallsBackToObjectSize() throws {
        let xml = """
        <hp:ole xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph">\
        <hp:sz width="100" height="200"/></hp:ole>
        """
        let control = HwpxOleMapper.map(try parse(xml), context: makeContext())
        let payload = try oleElement(of: control).rawPayload
        expect(try payload.readLittleEndianInt32(at: 4)) == 100
        expect(try payload.readLittleEndianInt32(at: 8)) == 200

        // 실물처럼 extent가 있으면 sz와 달라도 extent가 실린다 (7200 ≠ 32250).
        let real = HwpxOleMapper.map(try parse(oleXML), context: makeContext())
        let realPayload = try oleElement(of: real).rawPayload
        expect(try realPayload.readLittleEndianInt32(at: 4)) == 7200
        expect(try realPayload.readLittleEndianInt32(at: 8)) == 7200
    }

    func testExtentLookupIgnoresOtherVocabularyDecoy() throws {
        // hh:extent 디코이는 core 조회에 걸리지 않고 진단으로 강등된다.
        let xml = """
        <hp:ole xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph" \
        xmlns:hh="http://www.hancom.co.kr/hwpml/2011/head">\
        <hp:sz width="100" height="200"/><hh:extent x="1" y="2"/></hp:ole>
        """
        let control = HwpxOleMapper.map(try parse(xml), context: makeContext())
        let payload = try oleElement(of: control).rawPayload
        expect(try payload.readLittleEndianInt32(at: 4)) == 100
        expect(try payload.readLittleEndianInt32(at: 8)) == 200
        expect(control.unknownChildren.compactMap { String(bytes: $0.payload, encoding: .utf8) })
            == ["extent"]
    }

    func testPayloadSurvivesViewerOptions() throws {
        // 바이너리 OLE 요소는 payload를 decoupledPayload(양 모드 보존)로 읽는다 —
        // HWPX도 비우지 않아야 HWP↔HWPX viewer 패리티다 (pgnp의 preservedPayload
        // 게이트와 다른 부류).
        let standard = try oleElement(of: HwpxOleMapper.map(
            try parse(oleXML), context: makeContext(binItemIds: ["ole1": 1])
        ))
        let viewer = try oleElement(of: HwpxOleMapper.map(
            try parse(oleXML), context: makeContext(options: .viewer, binItemIds: ["ole1": 1])
        ))
        expect(viewer.rawPayload) == standard.rawPayload
        expect(viewer.rawPayload.count) == 26
        expect(viewer.rawTrailing) == standard.rawTrailing
        expect(viewer.binaryDataId) == 1
    }

    func testUnconsumedChildrenDegradeIntoDiagnostics() throws {
        // 실물 자식 11종 중 sz·pos·outMargin·extent만 소비한다 — 나머지는 렌더에
        // 반영되지 않으므로 진단(shapeControl.unknownChildren)에 남아야 한다.
        let control = HwpxOleMapper.map(
            try parse(oleXML), context: makeContext(binItemIds: ["ole1": 1])
        )
        let names = control.unknownChildren
            .compactMap { String(bytes: $0.payload, encoding: .utf8) }
        expect(names) == [
            "offset", "orgSz", "curSz", "flip", "rotationInfo", "renderingInfo", "lineShape",
        ]
        // 래퍼 안 자식은 트리째 보존된다 (진단 walker의 .child[i] 재귀용).
        let rendering = try XCTUnwrap(control.unknownChildren.first {
            String(bytes: $0.payload, encoding: .utf8) == "renderingInfo"
        })
        expect(rendering.children.compactMap { String(bytes: $0.payload, encoding: .utf8) })
            == ["transMatrix", "scaMatrix", "rotMatrix"]

        // 소비 4종만 있는 최소 요소는 강등 0건 (음성 대조).
        let minimal = """
        <hp:ole xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph" \
        xmlns:hc="http://www.hancom.co.kr/hwpml/2011/core">\
        <hc:extent x="1" y="1"/><hp:sz width="1" height="1"/>\
        <hp:pos vertRelTo="PARA"/><hp:outMargin left="0"/></hp:ole>
        """
        let plain = HwpxOleMapper.map(try parse(minimal), context: makeContext())
        expect(plain.unknownChildren).to(beEmpty())
    }

    func testWrapperDescendantsAndDuplicatesDegradeIntoDiagnostics() throws {
        // 잎 래퍼(sz·pos·outMargin·extent) 안의 미지 자식과 둘째 등장 래퍼는 값도
        // 안 실리고 조회에도 안 잡히므로 여기서 강등해야 진단에 남는다.
        let xml = """
        <hp:ole xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph" \
        xmlns:hc="http://www.hancom.co.kr/hwpml/2011/core" xmlns:ext="urn:x">\
        <hc:extent x="1" y="1"><ext:inExtent/></hc:extent>\
        <hp:sz width="1" height="1"><ext:inSz/></hp:sz>\
        <hp:sz width="9" height="9"/>\
        <hp:pos vertRelTo="PARA"><ext:inPos/></hp:pos>\
        <hp:outMargin left="0"><ext:inMargin/></hp:outMargin>\
        </hp:ole>
        """
        let control = HwpxOleMapper.map(try parse(xml), context: makeContext())
        let names = control.unknownChildren
            .compactMap { String(bytes: $0.payload, encoding: .utf8) }
        expect(names) == ["sz", "inSz", "inPos", "inMargin", "inExtent"]
        // 첫 sz만 값으로 실린다.
        expect(control.commonCtrlProperty?.width) == 1
    }

    func testDemotionDepthHonorsTheCallerLimit() throws {
        // 미지 서브트리 합성도 호출자 한도를 따른다 (그림·표와 같은 계약).
        let capped = HwpLoadOptions(readLimits: HwpReadLimits(maxNestingDepth: 2))
        let xml = oleXML.replacingOccurrences(
            of: "</hp:renderingInfo>",
            with: "<hp:deep><hp:deeper><hp:deepest/></hp:deeper></hp:deep></hp:renderingInfo>"
        )
        let control = HwpxOleMapper.map(
            try parse(xml), context: makeContext(options: capped)
        )
        let rendering = try XCTUnwrap(control.unknownChildren.first {
            String(bytes: $0.payload, encoding: .utf8) == "renderingInfo"
        })
        // 깊이 2 = renderingInfo + 직계 자식까지. 손자(deeper)는 잘린다.
        let deep = try XCTUnwrap(rendering.children.first {
            String(bytes: $0.payload, encoding: .utf8) == "deep"
        })
        expect(deep.children).to(beEmpty())
    }

    func testClassifyPromotesOleAndKeepsChartDegraded() throws {
        // 강등 표에서 빠졌다 — 남아 있으면 typed 분기가 있어도 표가 먼저 잡지는
        // 않지만, 표가 "미구현 목록"이라는 문서 계약이 깨진다.
        expect(HwpxControlMapper.objectFourCCs["ole"]).to(beNil())
        expect(HwpxControlMapper.objectFourCCs["chart"]) == HwpCommonCtrlId.ole.rawValue

        let action = try HwpxControlMapper.classify(
            try parse(oleXML), context: makeContext(binItemIds: ["ole1": 1])
        )
        guard case let .anchor(code, fourCC, ctrl) = action,
              case let .ole(control) = ctrl
        else {
            return fail("Expected .anchor(.ole), got \(action)")
        }
        expect(code) == 11
        expect(fourCC) == HwpCommonCtrlId.ole.rawValue
        expect(try self.oleElement(of: control).binaryDataId) == 1
    }

    /// chart 변환 쌍 실물 — `.ole`로 서고, BinData 조인이 닫혀 내장 차트 XML까지
    /// 닿으며, 진단에서 `$ole` 미구현 보고가 사라진다.
    func testChartFixturePromotesOleAndJoinsEmbeddedChart() throws {
        let hwpx = try openHwpx(#file, "chart")
        let hwp = try HwpFile(fromPath: FixtureLoader.load(id: "chart").documentURL.path)

        let ctrls = try XCTUnwrap(hwpx.sectionArray[0].paragraph[1].ctrlHeaderArray)
        guard case let .ole(control)? = ctrls.first else {
            return fail("Expected .ole, got \(String(describing: ctrls.first))")
        }
        let ole = try oleElement(of: control)
        expect(ole.binaryDataId) == 1
        expect(Array(ole.rawPayload.prefix(14))) == chartPayloadPrefix
        expect(control.commonCtrlProperty?.width) == 32250
        expect(control.commonCtrlProperty?.height) == 18750

        // HWP 쌍은 gso + $ole 개체 요소다. 두 파일 각각의 **실측 핀**이고 교차
        // 포맷 불변식이 아니다 — id 공간은 재저장이 재생성하므로 등가 투영은
        // 숫자 대신 해석 결과(차트 XML)를 본다 (`DocumentEquivalenceProjection`).
        expect(HwpxFixtureAssertions.oleBinItemIds(from: hwpx)) == [1]
        expect(HwpxFixtureAssertions.oleBinItemIds(from: hwp)) == [1]
        let hwpOle = try XCTUnwrap(HwpxFixtureAssertions.shapeComponents(from: hwp)
            .flatMap(\.oleArray).first)
        expect(Array(hwpOle.rawPayload.prefix(14))) == chartPayloadPrefix

        // BinData 조인 — HwpImageStore와 같은 규칙(binDataArray[offset+1].streamId →
        // binaryDataArray)으로 내장 차트 XML에 닿는다.
        let entry = try XCTUnwrap(hwpx.docInfo.idMappings.binDataArray.first)
        let stream = try XCTUnwrap(hwpx.binaryDataArray.first { $0.streamId == entry.streamId })
        expect(stream.data.count) == 15876
        let xml = try XCTUnwrap(HwpEmbeddedChart.chartXML(fromOLEPayload: stream.data))
        expect(xml.contains("<c:chartSpace")) == true
        // HWP 쌍의 CFB와 같은 차트 XML (Contents 스트림 1바이트만 다르다).
        let hwpStream = try XCTUnwrap(hwp.binaryDataArray.first)
        expect(HwpEmbeddedChart.chartXML(fromOLEPayload: hwpStream.data)) == xml

        // 진단: $ole notImplemented는 사라지고, 미소비 자식(offset·lineShape 등)은
        // 여전히 같은 컨트롤 경로 아래 unknownRecord로 남는다.
        let diagnostics = hwpx.parseDiagnostics()
        expect(diagnostics.filter {
            $0.kind == .notImplementedControl && $0.ctrlId == HwpCommonCtrlId.ole.rawValue
        }).to(beEmpty())
        expect(diagnostics.contains {
            $0.kind == .unknownRecord && $0.path.hasPrefix("section[0].paragraph[1].ctrl[0]")
        }) == true
    }
}
