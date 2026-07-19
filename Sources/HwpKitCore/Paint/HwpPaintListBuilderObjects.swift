import CoreGraphics
import Foundation

// MARK: - 컨테이너 (표 셀/글상자) 안 개체 페인트 명령

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
