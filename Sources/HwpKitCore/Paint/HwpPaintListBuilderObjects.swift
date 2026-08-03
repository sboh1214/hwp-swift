import CoreGraphics
import Foundation

// MARK: - 컨테이너 (표 셀/글상자/각주) 안 개체 페인트 명령

extension HwpPaintListBuilder {
    func cellImageCommands(
        _ image: HwpCellImage,
        rect: CGRect
    ) -> [HwpPaintCommand] {
        // clipRect는 표-로컬 — rect가 받은 오프셋만큼 함께 옮긴다 (R32 #2)
        let clip = image.clipRect?.offsetBy(
            dx: rect.minX - image.rect.minX,
            dy: rect.minY - image.rect.minY
        )
        var commands: [HwpPaintCommand] = [
            .drawImageReference(
                binItemId: image.binItemId, rect: rect, style: image.style, clipRect: clip
            ),
        ]
        if let borderColor = image.borderColor, image.borderWidth > 0 {
            // 절단면에 걸친 그림의 테두리는 가시 영역에만 (근사 — 절단선에도
            // 선이 생기지만 조각 밖으로 새지는 않는다)
            commands.append(.strokeRect(
                rect: clip.map { rect.intersection($0) } ?? rect,
                color: borderColor.cgColor,
                width: image.borderWidth
            ))
        }
        return commands
    }

    /// 글상자 안 개체 하나의 페인트 평면 (behind/zOrder/원본 순서) + 명령 묶음
    private struct TextboxObjectPlane {
        let behind: Bool
        let zOrder: Int32
        let sourceOrder: Int
        let commands: [HwpPaintCommand]
    }

    /// 글상자 안 개체의 페인트 명령 (zOrder 오름차순, 동순위는 원본
    /// ctrlHeaderArray 순서 — 종류-버킷 순서가 아니다, R31 #3).
    func textboxObjectCommands(
        _ textbox: HwpTextboxFrame,
        origin: CGPoint
    ) -> [(behind: Bool, commands: [HwpPaintCommand])] {
        var objects: [TextboxObjectPlane] = []
        for image in textbox.images {
            objects.append(TextboxObjectPlane(
                behind: image.paintsBehindText,
                zOrder: image.zOrder,
                sourceOrder: image.sourceOrder,
                commands: cellImageCommands(
                    image, rect: image.rect.offsetBy(dx: origin.x, dy: origin.y)
                )
            ))
        }
        for shape in textbox.shapes {
            objects.append(TextboxObjectPlane(
                behind: shape.paintsBehindText,
                zOrder: shape.zOrder,
                sourceOrder: shape.sourceOrder,
                commands: shapeCommands(
                    shape.geometry,
                    origin: CGPoint(x: origin.x + shape.rect.minX, y: origin.y + shape.rect.minY)
                )
            ))
        }
        return objects.sorted { lhs, rhs in
            lhs.zOrder != rhs.zOrder
                ? lhs.zOrder < rhs.zOrder
                : lhs.sourceOrder < rhs.sourceOrder
        }.map { (behind: $0.behind, commands: $0.commands) }
    }
}

extension HwpPaintListBuilder {
    /// 각주/미주 블록의 페인트 명령 — 구분선 + 문단 텍스트 + 각주 안 개체 (#94).
    ///
    /// 개체 방출 순서 (글 뒤로 개체 → 문단 텍스트 → 나머지 개체 → 각주 안 표
    /// 재귀)는 `HwpBlockContentWalker.walkFootnote`의 이벤트 순서가 정의한다 —
    /// 표 셀 경로 (`tableCommands`)와 같은 규약이라 선택↔렌더 패리티가 유지된다.
    func footnoteCommands(
        _ footnote: HwpFootnoteBlock,
        blockFrame: CGRect,
        drawSeparator: Bool
    ) -> [HwpPaintCommand] {
        var commands: [HwpPaintCommand] = []
        // 구분선은 페이지의 첫 번째 각주 블록에서 한 번만 그린다.
        if drawSeparator {
            commands.append(.fillRect(
                rect: footnote.separatorLine,
                color: footnote.separatorColor.cgColor
            ))
        }
        // 각주 안 개체 (그림/도형/글상자/표)는 각주 콘텐츠로 그린다 (#94).
        // 방출 순서 (글 뒤로 개체 → 문단 텍스트 → 나머지 개체 → 안쪽 표 재귀)는
        // walker의 이벤트 순서가 정의한다 — 표 셀 경로와 같은 규약.
        HwpBlockContentWalker.walkFootnote(
            footnote,
            origin: blockFrame.origin,
            onParagraphText: { attributed, rect, _ in
                commands.append(drawTextCommand(attributed, in: rect))
            },
            onCellStart: { cell, cellRect in
                if let fill = cell.fillColor {
                    commands.append(.fillRect(rect: cellRect, color: fill.cgColor))
                }
                commands.append(contentsOf: borderCommands(cell.borders, around: cellRect))
            },
            onCellImage: { image, rect in
                commands.append(contentsOf: cellImageCommands(image, rect: rect))
            },
            onCellShape: { shape, rect in
                commands.append(contentsOf: shapeCommands(shape.geometry, origin: rect.origin))
            },
            onCellTextbox: { textbox, rect in
                commands.append(contentsOf: textboxCommands(textbox.textbox, origin: rect.origin))
            }
        )
        return commands
    }
}

extension HwpPaintListBuilder {
    /// 각주 블록의 문단-레벨 하이퍼링크 방출 대상 — (문단들, 페이지 좌표 offset).
    /// 각주 본문 문단과 각주 안 글상자 문단을 같은 형태로 묶어, 방출 규칙
    /// (필드 스팬 게이트)은 호출부 한 곳에 남긴다 (#94).
    static func footnoteParagraphGroups(
        _ footnote: HwpFootnoteBlock,
        origin: CGPoint
    ) -> [(paragraphs: [HwpLaidOutParagraph], offset: CGPoint)] {
        [(footnote.paragraphs, origin)] + footnote.textboxes.map { textbox in
            (
                textbox.textbox.paragraphs,
                CGPoint(x: origin.x + textbox.rect.minX, y: origin.y + textbox.rect.minY)
            )
        }
    }
}
