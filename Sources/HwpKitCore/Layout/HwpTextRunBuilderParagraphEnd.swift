import CoreGraphics
import CoreHwp
import Foundation

/// 문단 끝 글자(CR, 코드 13)의 글자 모양 — 조판 문자열에서 접힌 글자(#137)의 모양을 문단 속성으로
/// 보존한다. 한글 문서는 기본 글자 크기(`attachParagraphEndBaseFontSize`, #206), MS 워드 호환
/// 문서는 라틴 슬롯 글꼴 상자(`attachMsWordParagraphEndBox`, #187·#194)이고, 세로 배치
/// (`HwpDrawnTextLayout.LineMetrics`)가 문단 마지막 줄(`HwpDrawnLine.endsParagraph`)의 줄 상자·
/// 비율 여분에 되돌려 넣는다. 둘 다 `finishBuild`(`HwpTextRunBuilderMarks.swift`)가 잘리지 않은
/// 문단에만 부른다.
extension HwpTextRunBuilder {
    /// 문단 끝 글자(CR)의 기본 글자 크기를 문단 조판 문자열 전체에 싣는다
    /// (`HwpAttributedStringKey.paragraphEndBaseFontSize`, #206). CR은 조판 문자열에서
    /// 접히지만(`controlText`) 한글은 그 글자 모양의 크기도 문단 **마지막 줄**의 글자 상자에
    /// 넣으므로 — 줄 상자와 비율 줄 간격 여분의 기준 둘 다 — 세로 배치(`HwpDrawnTextLayout.
    /// LineMetrics`)가 마지막 줄(`HwpDrawnLine.endsParagraph`)에서 되돌려 넣는다. 한글 12.30
    /// 실측(2026-09-21, 함초롬바탕 본문 + 빈 꼬리 run으로 CR 글자 모양을 준 합성 HWPX의 재저장
    /// 줄 캐시·PDF): 10pt 본문 + 16pt CR의 한 줄 문단 `vertsize` 1600·`baseline` 1360·160%
    /// `spacing` 960, 여러 줄 문단은 마지막 줄만 그렇고 앞 줄은 1000·850·600, 16pt 본문 + 10pt
    /// CR은 1600(최댓값), 10pt + 40pt CR은 4000·3400·2400, 줄 간격 고정 30·여백만 5·최소 12/20
    /// 도 상자 16 기준(30·21·16·20), 상대 크기 50%의 CR도 1600(기본 크기), 글꼴 무관(Apple SD
    /// 산돌고딕 Neo 1600), 표 마커 10pt + 30pt 표 + 16pt CR(`noori` 꼴)은 3000·2550·170%
    /// 1120, 8pt 표 + 16pt CR은 1600(CR이 상자를 정한다), 20pt 표 + 16pt CR은 2000·1700·960
    /// (여분 기준은 CR 16), 표 셀·글상자 안 문단도 같다. 한 줄 끝(코드 10)으로 나뉜 앞 줄에는
    /// 들지 않는다 — 10pt 글 + 10pt run의 한 줄 끝 + 16pt CR 문단은 첫 줄 `baseline` 850·
    /// `spacing` 600(전진량 16)이고 빈 마지막 줄만 1600·1360·960; 한 줄 끝이 16pt run에
    /// 있으면 첫 줄도 1600(한 줄 끝 글자 자신의 글자 모양 — `hwp.lineBreak` run이 싣는다).
    ///
    /// 싣는 범위가 문단 전체인 이유는 `attachMsWordParagraphEndBox`와 같다 — 마지막 글자에만
    /// 얹으면 속성 경계가 글리프 조합을 가른다. 상한으로 잘린 결과(`whole == false`)는 문단
    /// 끝이 아니라 싣지 않는다. 빈 문단 앵커에도 싣는다 — 앵커는 첫 글자 모양으로 서는데
    /// 접힌 글자(하이픈 24)와 CR의 글자 모양이 다르면 CR 쪽이 그 줄의 상자다.
    func attachParagraphEndBaseFontSize(
        to output: NSMutableAttributedString, paragraph: CoreHwp.HwpParagraph
    ) {
        guard output.length > 0, let shapeId = paragraph.paraCharShape.shapeId.last else { return }
        let resolved = resolvedShape(id: shapeId, paragraph: paragraph)
        let size = HwpUnits.points(fromHwpUnit: resolved.shape.baseSize)
        guard size > 0 else { return }
        output.addAttribute(
            HwpAttributedStringKey.paragraphEndBaseFontSize,
            value: NSNumber(value: Double(size)),
            range: NSRange(location: 0, length: output.length)
        )
    }

    /// MS 워드 호환 문서에서 문단 끝 글자(CR)의 줄 상자를 마지막 글자에 싣는다
    /// (`HwpAttributedStringKey.msWordParagraphEndBox`, #187). CR은 조판 문자열에서
    /// 접히지만(`controlText`) 한글은 그 글자를 마지막 글자 모양의 라틴 슬롯 글꼴로
    /// 줄 상자에 넣으므로, 렌더러가 마지막 줄의 밑줄 자리를 잡을 때 되돌려 넣는다.
    /// 상한으로 잘린 결과(`whole == false`)는 문단 끝이 아니라 싣지 않는다.
    ///
    /// 싣는 범위는 마지막 글자가 아니라 **문단 조판 문자열 전체**다 — 마지막 UTF-16
    /// 단위에만 얹으면 속성 경계가 글리프 조합을 가르고(PR 리뷰 재현: 이모지 서로게이트
    /// 쌍이 LastResort 글리프 둘로 깨져 폭이 74.6 → 122.6pt, 결합 문자 `é`·아랍어 합자는
    /// CoreText가 조합을 지키는 대신 속성을 버려 끝 상자가 사라진다), 마지막 속성 run에만
    /// 얹어도 그 run이 앞 run과 한 글리프로 합쳐지면(글자 모양 id만 다른 `لا` 합자·결합
    /// 문자) CoreText가 앞 run의 속성만 남겨 상자를 버린다. 문단 전체에 같은 값을 얹으면
    /// 새 경계가 없고 어느 run이 살아남아도 상자가 남는다. 어느 줄이 문단의 마지막 줄인지는
    /// 렌더러가 `HwpDrawnLine.endsParagraph`(이어짐 표식이 없는 조각의 끝 줄)로 가른다.
    func attachMsWordParagraphEndBox(
        to output: NSMutableAttributedString, paragraph: CoreHwp.HwpParagraph
    ) {
        guard output.length > 0, let font = msWordParagraphEndFont(of: paragraph),
              let shapeId = paragraph.paraCharShape.shapeId.last
        else { return }
        let resolved = resolvedShape(id: shapeId, paragraph: paragraph)
        // 곱하는 크기는 라틴 슬롯 상대 크기를 반영한 글꼴 크기가 아니라 글자 모양 기본
        // 크기다 — 한글은 MS 워드 호환 상자를 기본 크기로 잰다 (PR 리뷰 실측, `decorationBaseFontSize`).
        let box = HwpMsWordLineBox.metrics(of: font)
            .scaled(by: HwpUnits.points(fromHwpUnit: resolved.shape.baseSize))
        output.addAttribute(
            HwpAttributedStringKey.msWordParagraphEndBox,
            value: [NSNumber(value: Double(box.lineHeight)), NSNumber(value: Double(box.baseline))],
            range: NSRange(location: 0, length: output.length)
        )
    }
}
