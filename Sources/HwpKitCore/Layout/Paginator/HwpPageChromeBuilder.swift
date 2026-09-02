import CoreGraphics
import CoreHwp
import CoreText
import Foundation

/// 머리말/꼬리말/쪽 번호 밴드 — 페이지 확정 시점에 크롬 블록을 방출한다.
/// HwpPaginator에서 추출 (동작 불변). 상태는 paginator가 소유하는 값 타입.
struct HwpPageChromeBuilder {
    /// 크롬 전용 mutable 상태 — HwpPaginator가 이 빌더째로 소유한다.
    struct State {
        /// 구역의 활성 머리말/꼬리말 (적용 범위별, 표 141).
        /// 컨트롤을 만난 이후의 모든 페이지에 반복 방출되며, 같은 범위의
        /// 새 컨트롤이 나오면 교체된다.
        var activeHeaders: [CoreHwp.HwpHeaderFooterApplyScope: CoreHwp.HwpListControl] = [:]
        var activeFooters: [CoreHwp.HwpHeaderFooterApplyScope: CoreHwp.HwpListControl] = [:]
        /// 활성 쪽 번호 위치 (pgNumPos, 표 147/148). 컨트롤을 만난 페이지부터
        /// 모든 페이지에 쪽 번호를 방출하며, 새 컨트롤이 나오면 교체된다
        /// (머리말처럼 구역을 넘어도 유지 — 한글의 동작).
        var activePageNumberPosition: CoreHwp.HwpPageNumberPosition?
        /// 이 페이지에서 감출 대상 (pghd, 표 145 bit field). 페이지 확정 시 초기화.
        var pageHideMask: UInt32 = 0
        /// 구역 정의 (표 132)의 감추기 플래그를 표 145 비트로 환산한 마스크.
        /// 이 플래그는 구역의 **첫 쪽**만 감춘다 (HwpSectionDefProperty 문서:
        /// "첫 쪽의 머리말/꼬리말/바탕쪽 감춤") — 페이지 확정 시 소비해
        /// 2쪽부터는 크롬이 되살아난다.
        var sectionHideMask: UInt32 = 0
        /// (컨트롤, 밴드 프레임)별 머리말/꼬리말 블록 캐시
        var bandBlocksCache: [BandBlocksKey: [AnyHwpBlock]] = [:]
    }

    /// 밴드 블록 캐시 키: 같은 컨트롤 + 같은 밴드 프레임이면 매 페이지 재조판하지 않는다.
    struct BandBlocksKey: Hashable {
        let isHeader: Bool
        let list: CoreHwp.HwpListControl
        let bandX: Int
        let bandY: Int
        let bandWidth: Int
    }

    private let index: HwpIndex
    private let fontResolver: HwpFontResolver
    /// 글자 모양별 속성 캐시 (소유는 `HwpPaginator`) — 머리말/꼬리말 문단도
    /// 본문과 같은 캐시를 쓴다.
    private let attributeCache: HwpTextAttributeCache?
    private var state = State()

    init(
        index: HwpIndex,
        fontResolver: HwpFontResolver,
        attributeCache: HwpTextAttributeCache? = nil
    ) {
        self.index = index
        self.fontResolver = fontResolver
        self.attributeCache = attributeCache
    }

    // MARK: 컨트롤 등록

    /// 페이지 크롬 (머리말/꼬리말/쪽 번호 위치/쪽 감추기) 컨트롤을 활성 상태로
    /// 등록한다. 감추기 (표 145)는 컨트롤이 놓인 문단이 확정되는 페이지에만
    /// 적용된다.
    mutating func register(_ ctrl: CoreHwp.HwpCtrlId) {
        switch ctrl {
        case let .header(list):
            state.activeHeaders[list.headerFooterApplyScope] = list
        case let .footer(list):
            state.activeFooters[list.headerFooterApplyScope] = list
        case let .pageNumberPosition(position):
            state.activePageNumberPosition = position
        case let .pageHide(other):
            state.pageHideMask |= other.pageHideInfo?.rawValue ?? 0
        default:
            break
        }
    }

    /// 구역 정의 (표 132)의 감추기 플래그를 표 145 비트 (0x01 머리말 /
    /// 0x02 꼬리말 / 0x20 쪽 번호)로 환산해 구역 마스크로 둔다. 구역의 첫 쪽에서
    /// pageHide 컨트롤 마스크와 OR로 합쳐 한 번 소비되고, 다음 구역 정의에서
    /// 다시 채워진다.
    mutating func applySectionHideFlags(_ sectionDef: CoreHwp.HwpSectionDef) {
        let property = sectionDef.propertyInfo
        var mask: UInt32 = 0
        if property.hideHeader {
            mask |= 0x01
        }
        if property.hideFooter {
            mask |= 0x02
        }
        if property.hidePageNumberPosition {
            mask |= 0x20
        }
        state.sectionHideMask = mask
    }

    // MARK: 페이지 확정 방출

    /// 페이지 확정 시점: 감추기 마스크 (표 145: 0x01 머리말, 0x02 꼬리말,
    /// 0x20 쪽 번호)를 소비하고 이 페이지의 크롬 블록을 방출 순서대로 돌려준다.
    mutating func blocks(forPage pageNumber: Int, geometry: HwpPageGeometry) -> [AnyHwpBlock] {
        let hideMask = state.pageHideMask | state.sectionHideMask
        state.pageHideMask = 0
        state.sectionHideMask = 0
        var blocks = activeBandBlocks(
            pageNumber: pageNumber,
            hideMask: hideMask,
            geometry: geometry
        )
        if let numberBlock = pageNumberBlock(
            pageNumber: pageNumber,
            hideMask: hideMask,
            geometry: geometry
        ) {
            blocks.append(numberBlock)
        }
        return blocks
    }

    // MARK: 머리말/꼬리말

    /// 페이지 번호(1-based)와 적용 범위(표 141)에 맞는 활성 머리말/꼬리말을 고른다.
    /// 짝수/홀수 전용이 양쪽보다 우선한다.
    func resolvedBand(
        from bands: [CoreHwp.HwpHeaderFooterApplyScope: CoreHwp.HwpListControl],
        pageNumber: Int
    ) -> CoreHwp.HwpListControl? {
        let parity: CoreHwp.HwpHeaderFooterApplyScope = pageNumber.isMultiple(of: 2)
            ? .evenPagesOnly
            : .oddPagesOnly
        return bands[parity] ?? bands[.bothPages]
    }

    /// 이 페이지에 적용되는 머리말/꼬리말 밴드 블록을 방출한다 (페이지 확정 전용).
    /// hideMask (표 145): 0x01이면 머리말, 0x02면 꼬리말을 이 페이지에서 감춘다.
    private mutating func activeBandBlocks(
        pageNumber: Int,
        hideMask: UInt32,
        geometry: HwpPageGeometry
    ) -> [AnyHwpBlock] {
        var blocks: [AnyHwpBlock] = []
        if hideMask & 0x01 == 0,
           let header = resolvedBand(from: state.activeHeaders, pageNumber: pageNumber)
        {
            blocks += bandBlocks(
                header,
                band: geometry.headerFrame,
                isHeader: true,
                pageNumber: pageNumber,
                geometry: geometry
            )
        }
        if hideMask & 0x02 == 0,
           let footer = resolvedBand(from: state.activeFooters, pageNumber: pageNumber)
        {
            blocks += bandBlocks(
                footer,
                band: geometry.footerFrame,
                isHeader: false,
                pageNumber: pageNumber,
                geometry: geometry
            )
        }
        return blocks
    }

    private mutating func bandBlocks(
        _ list: CoreHwp.HwpListControl,
        band: CGRect?,
        isHeader: Bool,
        pageNumber: Int,
        geometry: HwpPageGeometry
    ) -> [AnyHwpBlock] {
        let paragraphs = list.listArray.flatMap(\.paragraphArray)
        guard !paragraphs.isEmpty else { return [] }
        let contentFrame = geometry.contentFrame
        let bandFrame: CGRect = band ?? CGRect(
            x: contentFrame.minX,
            y: isHeader ? max(0, contentFrame.minY - 20) : contentFrame.maxY,
            width: contentFrame.width,
            height: 20
        )

        // 자동 쪽 번호 (atno kind 0)가 있는 밴드는 페이지마다 내용이 달라
        // 캐시하지 않는다.
        let containsPageNumber = paragraphs.contains { paragraph in
            (paragraph.ctrlHeaderArray ?? []).contains { ctrl in
                if case let .autoNumber(other) = ctrl {
                    return other.autoNumberInfo?.kind == .page
                }
                return false
            }
        }
        let cacheKey = BandBlocksKey(
            isHeader: isHeader,
            list: list,
            bandX: Int(bandFrame.minX * 100),
            bandY: Int(bandFrame.minY * 100),
            bandWidth: Int(bandFrame.width * 100)
        )
        if !containsPageNumber, let cached = state.bandBlocksCache[cacheKey] {
            return cached
        }

        let blocks = layoutBandBlocks(
            paragraphs: paragraphs,
            bandFrame: bandFrame,
            pageNumber: pageNumber
        )
        if !containsPageNumber {
            state.bandBlocksCache[cacheKey] = blocks
        }
        return blocks
    }

    /// 밴드 프레임 안에 문단들을 위에서 아래로 조판한 텍스트 블록을 만든다.
    /// 자동 쪽 번호 (atno kind 0) 마커는 논리 쪽 번호 문자열로 치환한다.
    private func layoutBandBlocks(
        paragraphs: [CoreHwp.HwpParagraph],
        bandFrame: CGRect,
        pageNumber: Int
    ) -> [AnyHwpBlock] {
        let builder = HwpTextRunBuilder(
            index: index, fontResolver: fontResolver, attributeCache: attributeCache
        )
        let paragraphLayout = HwpParagraphLayout()
        var cursorY = bandFrame.minY
        var blocks: [AnyHwpBlock] = []
        for paragraph in paragraphs {
            var replacements: [Int: HwpControlMarkerReplacement] = [:]
            for (ctrlIndex, ctrl) in (paragraph.ctrlHeaderArray ?? []).enumerated() {
                guard case let .autoNumber(other) = ctrl,
                      let info = other.autoNumberInfo, info.kind == .page
                else { continue }
                replacements[ctrlIndex] = HwpControlMarkerReplacement(
                    text: HwpTextRunBuilder.decoratedNoteNumber(
                        number: pageNumber,
                        shape: info.numberShapeRawValue,
                        decorationHead: info.decorationHead,
                        decorationTail: info.decorationTail
                    )
                )
            }
            let attributed = builder.build(
                paragraph: paragraph,
                controlReplacements: replacements
            )
            guard attributed.length > 0 else { continue }
            let frame = paragraphLayout.layout(
                attributedString: attributed,
                paraShape: index.paraShapeOrDefault(for: paragraph),
                columnWidth: bandFrame.width
            )
            let blockHeight = max(1, frame.totalHeight)
            blocks.append(AnyHwpBlock(
                frame: CGRect(
                    x: bandFrame.minX,
                    y: cursorY,
                    width: bandFrame.width,
                    height: blockHeight
                ),
                kind: .text,
                attributedString: NSAttributedString(attributedString: attributed),
                source: HwpBlockSource(paragraphId: paragraph.paraHeader.paraId),
                role: .pageChrome
            ))
            cursorY += blockHeight
        }
        return blocks
    }

    // MARK: 쪽 번호 (표 147/148)

    /// 활성 쪽 번호 위치에 따라 논리 쪽 번호 텍스트 블록을 방출한다.
    /// hideMask 0x20 (쪽 번호 감추기, 표 145)이 켜진 페이지는 건너뛴다.
    private func pageNumberBlock(
        pageNumber: Int,
        hideMask: UInt32,
        geometry: HwpPageGeometry
    ) -> AnyHwpBlock? {
        guard hideMask & 0x20 == 0,
              let position = state.activePageNumberPosition,
              let placement = pageNumberPlacement(
                  displayPosition: position.propertyInfo.displayPosition,
                  pageNumber: pageNumber,
                  geometry: geometry
              )
        else { return nil }

        var text = HwpTextRunBuilder.decoratedNoteNumber(
            number: pageNumber,
            shape: position.propertyInfo.numberFormat,
            decorationHead: position.headDecoration,
            decorationTail: position.tailDecoration
        )
        // 앞/뒤 장식 문자가 없으면 줄표 필드(표 147 4번째 WCHAR)를 따른다. 공개
        // 문서는 '항상 -'라 적지만 실물은 줄표 문자 또는 0이다 — 헌법주석은 0x2D라
        // 한글.app 실측 "- xi -"처럼 감싸고, noori는 0이라 "1"만 그린다 (#138).
        if position.headDecoration == 0, position.tailDecoration == 0,
           position.unused != 0, let scalar = Unicode.Scalar(position.unused)
        {
            let sideChar = String(Character(scalar))
            text = "\(sideChar) \(text) \(sideChar)"
        }
        let attributed = pageNumberAttributedString(text: text, alignment: placement.alignment)
        return AnyHwpBlock(
            frame: placement.frame,
            kind: .text,
            attributedString: attributed,
            role: .pageChrome
        )
    }

    /// 표 148 bit 8-11 표시 위치 → 페이지 프레임/정렬.
    /// 0 없음이면 nil. 바깥쪽/안쪽은 짝/홀 페이지에 따라 좌/우가 바뀐다.
    private func pageNumberPlacement(
        displayPosition: Int,
        pageNumber: Int,
        geometry: HwpPageGeometry
    ) -> (frame: CGRect, alignment: CTTextAlignment)? {
        let contentFrame = geometry.contentFrame
        let isTop: Bool
        switch displayPosition {
        case 1, 2, 3, 7, 9: isTop = true
        case 4, 5, 6, 8, 10: isTop = false
        default: return nil
        }
        let isEven = pageNumber.isMultiple(of: 2)
        let alignment: CTTextAlignment = switch displayPosition {
        case 1, 4: .left
        case 2, 5: .center
        case 3, 6: .right
        case 7, 8: isEven ? .left : .right // 바깥쪽 (홀수쪽 = 오른쪽)
        case 9, 10: isEven ? .right : .left // 안쪽
        default: .center
        }
        let blockHeight = pageNumberBlockHeight
        let frame: CGRect = if isTop {
            geometry.headerFrame ?? CGRect(
                x: contentFrame.minX,
                y: max(0, contentFrame.minY - blockHeight),
                width: contentFrame.width,
                height: blockHeight
            )
        } else {
            geometry.footerFrame ?? CGRect(
                x: contentFrame.minX,
                y: min(geometry.pageSize.height - blockHeight, contentFrame.maxY),
                width: contentFrame.width,
                height: blockHeight
            )
        }
        return (frame, alignment)
    }

    private var pageNumberBlockHeight: CGFloat {
        let shape = index.charShape(id: 0) ?? CoreHwp.HwpCharShape()
        return max(10, HwpUnits.points(fromHwpUnit: shape.baseSize) * 1.4)
    }

    /// 기본 글자 모양 (charShape 0)의 글꼴로 쪽 번호 문자열을 만든다.
    private func pageNumberAttributedString(
        text: String,
        alignment: CTTextAlignment
    ) -> NSAttributedString {
        let shape = index.charShape(id: 0) ?? CoreHwp.HwpCharShape()
        let size = max(6, HwpUnits.points(fromHwpUnit: shape.baseSize))
        let faceId = UInt32(shape.faceId.first ?? 0)
        let face = index.faceName(for: faceId, script: .korean)
        let font = fontResolver.resolve(
            faceName: face?.faceName ?? "Helvetica",
            alternatives: [face?.alternativeFaceName, face?.defaultFaceName].compactMap { $0 },
            script: .korean, size: size
        )

        var alignmentValue = alignment
        let style = withUnsafeMutablePointer(to: &alignmentValue) { pointer in
            var setting = CTParagraphStyleSetting(
                spec: .alignment,
                valueSize: MemoryLayout<CTTextAlignment>.size,
                value: pointer
            )
            return CTParagraphStyleCreate(&setting, 1)
        }
        return NSAttributedString(string: text, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: shape.faceColor.cgColor,
            kCTParagraphStyleAttributeName as NSAttributedString.Key: style,
        ])
    }
}
