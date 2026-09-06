import CoreGraphics
import CoreHwp
import Foundation

// HwpFootnoteCoordinator의 번호 미리보기·배치 계산 — 수집·예약
// (`HwpFootnoteCoordinator.swift`)과 파일을 갈라 둔다. 그 파일이 SwiftLint
// file_length 상한(700줄)에 닿아 #158의 번호 열쇠 관통을 실을 자리가 없었다.

// MARK: - 번호 미리보기 / 배치 계산

extension HwpFootnoteCoordinator {
    /// 본문 문단의 extended 마커 치환: 각주/미주 참조 위치 (ext17)에는
    /// 위 첨자 번호를, 자동 쪽 번호 (atno kind 0)에는 논리 쪽 번호를 넣는다.
    /// 번호 미리보기는 collectFootnotes/collectEndnotes가 부여할 값과 같은
    /// 순서로 계산한다 (컨트롤당 1씩 증가).
    func noteReferenceReplacements(
        for paragraph: CoreHwp.HwpParagraph,
        footnoteShape: CoreHwp.HwpFootnoteShape?,
        endnoteShape: CoreHwp.HwpFootnoteShape?,
        pageNumber: Int,
        ordinals: Range<Int>? = nil
    ) -> [Int: HwpControlMarkerReplacement] {
        guard let ctrls = paragraph.ctrlHeaderArray else { return [:] }
        var replacements: [Int: HwpControlMarkerReplacement] = [:]
        var footnotePreview = footnoteCounter
        var endnotePreview = endnoteCounter
        // 조각 범위 밖 컨트롤은 미리보기도 **증가시키지 않는다** (#95): 앞 조각의
        // 몫은 이미 카운터에 반영됐고 뒤 조각의 몫은 아직 아니라, 범위 안만 세어야
        // 수집이 부여할 번호와 같아진다. 그래서 **범위만 훑어도 결과가 같고**,
        // 조각마다 전수 순회하지 않으므로 O(run × 컨트롤)이 되지 않는다.
        for ctrlIndex in ordinals ?? (0 ..< ctrls.count)
            where ctrls.indices.contains(ctrlIndex)
        {
            switch ctrls[ctrlIndex] {
            case .footnote:
                replacements[ctrlIndex] = HwpControlMarkerReplacement(
                    text: HwpTextRunBuilder.noteNumberText(
                        number: footnotePreview,
                        footnoteShape: footnoteShape
                    ),
                    isSuperscript: true
                )
                footnotePreview += 1
            case .endnote:
                replacements[ctrlIndex] = HwpControlMarkerReplacement(
                    text: HwpTextRunBuilder.noteNumberText(
                        number: endnotePreview,
                        footnoteShape: endnoteShape
                    ),
                    isSuperscript: true
                )
                endnotePreview += 1
            case let .autoNumber(other):
                if let info = other.autoNumberInfo, info.kind == .page {
                    replacements[ctrlIndex] = HwpControlMarkerReplacement(
                        text: HwpNumberFormat.string(
                            for: pageNumber,
                            shape: info.numberShapeRawValue
                        )
                    )
                }
            default:
                continue
            }
        }
        return replacements
    }

    // MARK: 배치 계산 (블록 방출·pending 소비는 paginator — 부수효과 경계)

    /// 대기 각주의 페이지 하단 배치를 계산한다 (HwpFootnoteLayout.place 위임).
    /// pendingFootnotes 소비 (overflow 반영)와 블록 방출은 호출자 몫.
    func placePendingFootnotes(
        onPage geometry: HwpPageGeometry,
        footnoteShape: CoreHwp.HwpFootnoteShape?,
        limitsAreaToHalfContent: Bool,
        sizeResolver: HwpObjectSizeResolver? = nil
    ) -> HwpFootnoteLayout.Placement {
        footnoteLayout.place(
            footnotes: pendingFootnotes,
            onPage: geometry,
            index: index,
            footnoteShape: footnoteShape,
            limitsAreaToHalfContent: limitsAreaToHalfContent,
            sizeResolver: sizeResolver
        )
    }

    /// 대기 미주의 흐름 배치를 계산한다 (HwpFootnoteLayout.placeFlow 위임).
    /// pendingEndnotes 소비 (overflow 반영)와 블록 방출은 호출자 몫.
    func placePendingEndnotes(
        from startY: CGFloat,
        in columnFrame: CGRect,
        endnoteShape: CoreHwp.HwpFootnoteShape?,
        drawSeparator: Bool,
        sizeResolver: HwpObjectSizeResolver? = nil
    ) -> HwpFootnoteLayout.FlowPlacement {
        footnoteLayout.placeFlow(
            footnotes: pendingEndnotes,
            from: startY,
            in: columnFrame,
            index: index,
            footnoteShape: endnoteShape,
            drawSeparator: drawSeparator,
            sizeResolver: sizeResolver
        )
    }
}
