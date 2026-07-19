import CoreGraphics
import Foundation

// MARK: - 컨테이너 (표 셀/글상자) 안 개체 페인트 명령

extension HwpPaintListBuilder {
    func cellImageCommands(
        _ image: HwpCellImage,
        rect: CGRect
    ) -> [HwpPaintCommand] {
        var commands: [HwpPaintCommand] = [
            .drawImageReference(binItemId: image.binItemId, rect: rect, style: image.style),
        ]
        if let borderColor = image.borderColor, image.borderWidth > 0 {
            commands.append(.strokeRect(
                rect: rect,
                color: borderColor.cgColor,
                width: image.borderWidth
            ))
        }
        return commands
    }

    /// 글상자 안 개체 하나의 페인트 평면 (behind/zOrder) + 명령 묶음
    private struct TextboxObjectPlane {
        let behind: Bool
        let zOrder: Int32
        let commands: [HwpPaintCommand]
    }

    /// 글상자 안 개체의 페인트 명령 (zOrder 오름차순, 동순위는 수집 순서).
    func textboxObjectCommands(
        _ textbox: HwpTextboxFrame,
        origin: CGPoint
    ) -> [(behind: Bool, commands: [HwpPaintCommand])] {
        var objects: [TextboxObjectPlane] = []
        for image in textbox.images {
            objects.append(TextboxObjectPlane(
                behind: image.paintsBehindText,
                zOrder: image.zOrder,
                commands: cellImageCommands(
                    image, rect: image.rect.offsetBy(dx: origin.x, dy: origin.y)
                )
            ))
        }
        for shape in textbox.shapes {
            objects.append(TextboxObjectPlane(
                behind: shape.paintsBehindText,
                zOrder: shape.zOrder,
                commands: shapeCommands(
                    shape.geometry,
                    origin: CGPoint(x: origin.x + shape.rect.minX, y: origin.y + shape.rect.minY)
                )
            ))
        }
        return objects.enumerated().sorted { lhs, rhs in
            lhs.element.zOrder != rhs.element.zOrder
                ? lhs.element.zOrder < rhs.element.zOrder
                : lhs.offset < rhs.offset
        }.map { (behind: $0.element.behind, commands: $0.element.commands) }
    }
}
