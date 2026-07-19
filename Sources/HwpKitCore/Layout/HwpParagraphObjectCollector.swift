import CoreGraphics
import CoreHwp
import Foundation

/// 컨테이너 (표 셀/글상자) 문단에 붙은 개체 컨트롤 (그림/도형/글상자)을
/// 컨테이너-로컬 rect로 수집한다. 줄 안 U+FFFC 앵커가 있으면 (treatAsChar)
/// 그 줄 위치에, 없으면 문단 rect 왼쪽부터 커서로 쌓는다 (한글: 컨테이너 안
/// 개체는 컨테이너 콘텐츠 — 페이지 흐름으로 방출하면 컨테이너 밖에 그려진다).
/// ole (내장 차트)·수식 컨트롤은 대상이 아니다 — 페이지 흐름 경로가 그린다.
struct HwpParagraphObjectCollector {
    let index: HwpIndex
    let fontResolver: HwpFontResolver
    let sizeResolver: HwpObjectSizeResolver?
    /// 글상자 수집 여부 — 글상자 안 글상자 재귀를 막는다 (표 셀만 참)
    let collectsTextboxes: Bool

    struct Objects {
        var images: [HwpCellImage] = []
        var shapes: [HwpCellShape] = []
        var textboxes: [HwpCellTextbox] = []
    }

    typealias HandledControl = (
        commonProperty: CoreHwp.HwpCommonCtrlProperty?,
        components: [CoreHwp.HwpShapeComponent]
    )

    /// 컨테이너 레이아웃이 처리하는 컨트롤의 (공통 속성, 개체 요소) 추출.
    /// HwpPaginator의 페이지 흐름 억제 술어와 수집 대상이 여기서 일치한다.
    /// 수식 (equation)은 흐름 경로의 스크립트 근사 텍스트를 유지하려 제외.
    static func handledControl(
        _ ctrl: CoreHwp.HwpCtrlId
    ) -> HandledControl? {
        switch ctrl {
        case let .genShapeObject(genShape):
            (genShape.commonCtrlProperty, genShape.shapeComponentArray)
        case let .shape(shape),
             let .line(shape),
             let .rectangle(shape),
             let .ellipse(shape),
             let .arc(shape),
             let .polygon(shape),
             let .curve(shape),
             let .picture(shape):
            (shape.commonCtrlProperty, shape.shapeComponentArray)
        default:
            nil
        }
    }

    /// 컨트롤 단위 수집 판정 — HwpPaginator의 페이지 흐름 억제
    /// (rendersInsideContainer)와 반드시 일치해야 한다 (불일치 = 소실 또는
    /// 이중 렌더). ole (내장 차트) 또는 미수집 글상자를 품은 컨트롤은
    /// 통째로 흐름 경로에 남긴다.
    static func collectible(
        _ components: [CoreHwp.HwpShapeComponent],
        collectsTextboxes: Bool
    ) -> Bool {
        guard components.allSatisfy(\.oleArray.isEmpty) else { return false }
        if !collectsTextboxes,
           components.contains(where: { !$0.textBoxListArray.isEmpty })
        {
            return false
        }
        return true
    }

    func objects(
        in paragraph: CoreHwp.HwpParagraph,
        frame: HwpParagraphFrame,
        paragraphRect: CGRect
    ) -> Objects {
        var collected = Objects()
        var cursorX = paragraphRect.minX
        for (controlIndex, ctrl) in (paragraph.ctrlHeaderArray ?? []).enumerated() {
            guard let (commonProperty, components) = Self.handledControl(ctrl),
                  Self.collectible(components, collectsTextboxes: collectsTextboxes)
            else { continue }
            let placement = Placement(
                anchor: anchorOrigin(
                    for: controlIndex, frame: frame, paragraphRect: paragraphRect
                ),
                paragraphRect: paragraphRect
            )
            for component in components {
                collect(
                    component: component,
                    commonProperty: commonProperty,
                    placement: placement,
                    cursorX: &cursorX,
                    into: &collected
                )
            }
        }
        return collected
    }

    /// 개체 배치 문맥 — 줄 앵커 (없으면 커서 흐름 배치)와 문단 rect
    private struct Placement {
        let anchor: CGPoint?
        let paragraphRect: CGRect

        func origin(cursorX: CGFloat) -> CGPoint {
            anchor ?? CGPoint(x: cursorX, y: paragraphRect.minY)
        }
    }

    /// 컴포넌트 하나를 종류별 (그림 → 글상자 → 도형)로 수집한다.
    private func collect(
        component: CoreHwp.HwpShapeComponent,
        commonProperty: CoreHwp.HwpCommonCtrlProperty?,
        placement: Placement,
        cursorX: inout CGFloat,
        into collected: inout Objects
    ) {
        if !component.pictureArray.isEmpty {
            guard let size = resolvedSize(
                commonProperty: commonProperty, component: component
            ) else { return }
            for picture in component.pictureArray {
                guard let image = image(
                    picture: picture,
                    size: size,
                    instanceId: commonProperty?.instanceId ?? 0,
                    paragraphRect: placement.paragraphRect,
                    origin: placement.origin(cursorX: cursorX)
                ) else { continue }
                collected.images.append(image)
                if placement.anchor == nil {
                    cursorX += image.rect.width
                }
            }
            return
        }
        let origin = placement.origin(cursorX: cursorX)
        if !component.textBoxListArray.isEmpty {
            guard collectsTextboxes, let textbox = textbox(
                component: component,
                commonProperty: commonProperty,
                paragraphRect: placement.paragraphRect,
                origin: origin
            ) else { return }
            collected.textboxes.append(textbox)
            if placement.anchor == nil {
                cursorX += textbox.rect.width
            }
            return
        }
        guard let shape = shape(
            component: component, commonProperty: commonProperty, origin: origin
        ) else { return }
        collected.shapes.append(shape)
        if placement.anchor == nil {
            cursorX += shape.rect.width
        }
    }

    /// controlIndex 마커의 줄 앵커 좌표 (문단 rect 기준) —
    /// HwpPaginator.inlineAnchorMap과 같은 산식 (baseline − ascent = 개체 상단).
    private func anchorOrigin(
        for controlIndex: Int,
        frame: HwpParagraphFrame,
        paragraphRect: CGRect
    ) -> CGPoint? {
        guard let firstBaseline = frame.lines.first?.baseline else { return nil }
        for line in frame.lines {
            for anchor in line.inlineAnchors where anchor.controlIndex == controlIndex {
                return CGPoint(
                    x: paragraphRect.minX + line.origin.x + anchor.xOffset,
                    y: paragraphRect.minY + firstBaseline + line.origin.y - anchor.ascent
                )
            }
        }
        return nil
    }

    /// 개체의 해석 크기 — 저장 크기가 0 이하이면 개체 요소 detail의
    /// 현재 크기로 폴백하고, 그래도 0 이하이면 nil (그리지 않음).
    private func resolvedSize(
        commonProperty: CoreHwp.HwpCommonCtrlProperty?,
        component: CoreHwp.HwpShapeComponent
    ) -> CGSize? {
        let stored = commonProperty.map {
            HwpObjectSizeResolver.size(of: $0, resolver: sizeResolver)
        } ?? .zero
        var width = stored.width
        var height = stored.height
        if width <= 0 || height <= 0, let detail = component.detail {
            if width <= 0 {
                width = HwpUnits.points(fromHwpUnitU: detail.currentWidth)
            }
            if height <= 0 {
                height = HwpUnits.points(fromHwpUnitU: detail.currentHeight)
            }
        }
        guard width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    private func image(
        picture: CoreHwp.HwpShapeComponentPicture,
        size: CGSize,
        instanceId: UInt32,
        paragraphRect: CGRect,
        origin: CGPoint
    ) -> HwpCellImage? {
        let property = picture.pictureProperty
        guard let binItemId = property.map({ UInt32($0.binItemId) })
            ?? picture.binaryDataId.map(UInt32.init)
        else { return nil }
        let width = min(size.width, max(1, paragraphRect.maxX - origin.x))
        var borderColor: HwpRGBColor?
        var borderWidth: CGFloat = 0
        if let property, property.borderThickness > 0 {
            borderColor = HwpRGBColor(property.borderColor)
            borderWidth = HwpUnits.points(fromHwpUnit: property.borderThickness)
        }
        return HwpCellImage(
            rect: CGRect(x: origin.x, y: origin.y, width: width, height: size.height),
            binItemId: binItemId,
            style: property.map { HwpImageRenderStyle(pictureProperty: $0) },
            borderColor: borderColor,
            borderWidth: borderWidth,
            controlInstanceId: instanceId
        )
    }

    private func textbox(
        component: CoreHwp.HwpShapeComponent,
        commonProperty: CoreHwp.HwpCommonCtrlProperty?,
        paragraphRect: CGRect,
        origin: CGPoint
    ) -> HwpCellTextbox? {
        guard let commonProperty, let frame = HwpTextboxLayout(fontResolver: fontResolver).layout(
            components: [component],
            commonProperty: commonProperty,
            fallbackWidth: paragraphRect.width,
            index: index,
            sizeResolver: sizeResolver
        ) else { return nil }
        return HwpCellTextbox(
            rect: CGRect(origin: origin, size: frame.outerFrame.size),
            textbox: frame,
            controlInstanceId: commonProperty.instanceId
        )
    }

    private func shape(
        component: CoreHwp.HwpShapeComponent,
        commonProperty: CoreHwp.HwpCommonCtrlProperty?,
        origin: CGPoint
    ) -> HwpCellShape? {
        guard let size = resolvedSize(commonProperty: commonProperty, component: component),
              let geometry = HwpShapeGeometry.build(component: component, size: size)
        else { return nil }
        return HwpCellShape(
            rect: CGRect(origin: origin, size: size),
            geometry: geometry,
            controlInstanceId: commonProperty?.instanceId ?? 0
        )
    }
}
