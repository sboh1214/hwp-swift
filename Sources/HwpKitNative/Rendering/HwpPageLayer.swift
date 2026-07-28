import CoreGraphics
import CoreText
import Foundation
import HwpKitCore
import QuartzCore

public final class HwpPageLayer: CALayer, @unchecked Sendable {
    public var paintList: HwpPaintList? {
        didSet {
            // 캐시 키가 커맨드 인덱스라 paintList가 바뀌면 전량 무효다. 엔트리
            // 재검증이 2차 방어선이라 이게 새도 오조판은 나지 않지만, 스테일
            // CTLine이 상주하는 것을 막는다 (메모리 위생).
            drawnLineCacheLock.lock()
            drawnLineCache.removeAll()
            cachedLineCount = 0
            drawnLineCacheLock.unlock()
            // 락 밖에서 — CA 콜백이 재진입해 같은 락을 다시 잡을 여지를 없앤다
            setNeedsDisplay()
        }
    }

    public var pageHeight: CGFloat = 0

    /// `.drawImageReference` 명령을 해석할 이미지 공급자.
    /// 디코딩이 끝나면 레이어를 다시 그린다.
    public var imageProvider: HwpPageImageProvider? {
        didSet {
            setNeedsDisplay()
        }
    }

    // MARK: - 줄 배치 캐시

    /// 조판 결과 1건. `attributedString`을 strong으로 들고 있어 캐시가 사는 동안
    /// 그 객체 주소가 다른 문자열에 재사용될 수 없다 (`===` 재검증의 전제).
    private struct DrawnLineEntry {
        let attributedString: NSAttributedString
        let origin: CGPoint
        let lineWidth: CGFloat
        let lines: [HwpDrawnLine]
    }

    /// `.drawText` 재조판 캐시 — 키는 `paintList.commands`의 인덱스다.
    ///
    /// NSAttributedString의 `ObjectIdentifier`를 키로 쓰지 않는다: `drawPlaceholder`가
    /// draw마다 임시 문자열을 만들어 해제된 주소가 재사용되면 rect가 같은
    /// 플레이스홀더끼리 origin·lineWidth까지 일치해 **엉뚱한 히트로 조용한 오조판**이
    /// 난다. 커맨드 인덱스는 `drawPlaceholder`가 가질 수 없어 캐시 우회가 코드가
    /// 아니라 구조로 강제된다. `HwpPaintCommand`도 같은 이유로 identity 해싱을
    /// 의미상 틀린 것으로 배제해 뒀고, 값 타입 키는 `HwpSelectionGeometry.UnitKey`와
    /// 같은 선례다.
    ///
    /// 락은 딕셔너리 조회/저장 순간에만 잡는다 — CoreText 조판이나 CTLineDraw 중에는
    /// 절대 보유하지 않는다 (장래에 그 아래로 텍스트 호출이 추가돼도 재진입
    /// 데드락이 나지 않게). 이 락은 Dictionary 동시 변형이라는 메모리 비안전만
    /// 막을 뿐 레이어를 thread-safe하게 만들지 않는다: 클래스가 `@unchecked Sendable`
    /// 이라 컴파일러가 동시 사용을 막지 않고, 테스트는 임의 스레드에서
    /// `draw(in:)`을 직접 부른다.
    private let drawnLineCacheLock = NSLock()
    private var drawnLineCache: [Int: DrawnLineEntry] = [:]
    private var cachedLineCount = 0
    private var typesetCallCount = 0

    /// 레이어당 캐시가 보유할 CTLine 총량 상한 (기본값).
    ///
    /// 초과 시 축출하지 않고 신규 삽입만 멈춘다 — draw는 커맨드를 항상 같은 순서로
    /// 전량 훑으므로 FIFO 축출은 워킹셋이 상한보다 큰 페이지에서 히트율 0% + 매 draw
    /// 전량 축출/재삽입이 된다 (`HwpSelectionGeometry`의 FIFO가 맞는 건 그쪽이 랜덤
    /// 액세스라서다). 엔트리 수가 아니라 줄 수로 잡는 이유: 엔트리 하나가
    /// `HwpParagraphLayout.maximumLineFrames`(=100,000) 줄까지 담을 수 있어 엔트리 수
    /// 상한은 CTLine 보유량을 전혀 묶지 못한다. 실문서는 페이지당 수십 줄이라
    /// 정상 문서는 걸리지 않고, 병적 대형 표·메모 풍선 다발만 막힌다.
    private static let defaultCachedLineBudget = 8192

    /// 인스턴스 상한 (기본 = 전역 상한) — 테스트가 예산 초과 경로를 작은 문서로
    /// 재현할 수 있게 재정의를 허용한다.
    var cachedLineBudget = HwpPageLayer.defaultCachedLineBudget

    /// `HwpDrawnTextLayout.lines` 실제 호출 횟수 — 캐시가 재조판을 실제로 없애는지,
    /// 플레이스홀더가 캐시를 우회하는지 테스트가 관측하는 지점
    /// (`HwpFontResolver.matchCounter`와 같은 계측 관례). static이 아니라 인스턴스인
    /// 이유: 레이어가 여럿 동시에 그려져 static 카운터는 테스트를 순서 의존으로 만든다.
    var typesetCount: Int {
        drawnLineCacheLock.lock()
        defer { drawnLineCacheLock.unlock() }
        return typesetCallCount
    }

    /// 캐시 엔트리 수 — 플레이스홀더 우회를 직접 단언하기 위한 관측 지점.
    var cachedDrawnLineEntryCount: Int {
        drawnLineCacheLock.lock()
        defer { drawnLineCacheLock.unlock() }
        return drawnLineCache.count
    }

    override public init() {
        super.init()
        needsDisplayOnBoundsChange = true
    }

    override public init(layer: Any) {
        if let layer = layer as? HwpPageLayer {
            // 줄 배치 캐시는 복사하지 않는다 — 사본은 빈 캐시로 시작한다. (이 대입은
            // super.init 이전이라 didSet이 발화하지 않고, 사본은 같은 paintList를
            // 공유하므로 스스로 다시 채우면 정확하다.)
            paintList = layer.paintList
            pageHeight = layer.pageHeight
            imageProvider = layer.imageProvider
        }
        super.init(layer: layer)
        needsDisplayOnBoundsChange = true
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func draw(in ctx: CGContext) {
        guard let paintList else { return }

        ctx.saveGState()
        defer { ctx.restoreGState() }

        #if os(macOS)
            // macOS의 layer 컨텍스트는 기본 bottom-left(y-up)다. 조상 계층의
            // geometry flip 횟수가 홀수면 (예: isFlipped NSView 안) CA가 이미
            // top-down으로 보정해 준다. paint 명령은 top-left 기준이므로
            // 보정이 없을 때만 직접 뒤집는다. 레이어 자체에 isGeometryFlipped를
            // 켜지 않는 이유: flipped 뷰 안에서 이중 flip이 되어 상하 반전된다.
            if !contentsAreFlipped() {
                ctx.translateBy(x: 0, y: bounds.height)
                ctx.scaleBy(x: 1, y: -1)
            }
        #else
            // iOS: CA가 주는 인앱 레이어 컨텍스트는 이미 top-down (CTM d < 0)
            // 이지만, 테스트·오프스크린 렌더의 원시 bitmap 컨텍스트는 y-up
            // (d > 0)이다. CTM 방향으로 판별해 y-up일 때만 뒤집는다 —
            // 인앱 경로는 불변.
            if ctx.ctm.d > 0 {
                ctx.translateBy(x: 0, y: bounds.height)
                ctx.scaleBy(x: 1, y: -1)
            }
        #endif

        for (index, command) in paintList.commands.enumerated() {
            execute(command, at: index, in: ctx)
        }
    }

    private func execute(_ command: HwpPaintCommand, at commandIndex: Int, in ctx: CGContext) {
        switch command {
        case let .fillRect(rect, color):
            ctx.setFillColor(color)
            ctx.fill(rect)

        case let .strokeRect(rect, color, width):
            ctx.setStrokeColor(color)
            ctx.setLineWidth(width)
            ctx.stroke(rect)

        case let .drawText(attributedString, origin, lineWidth):
            drawTextLines(
                cachedDrawnLines(
                    commandIndex: commandIndex,
                    attributedString: attributedString,
                    origin: origin,
                    lineWidth: lineWidth
                ),
                in: ctx
            )

        case let .drawPath(path, fill, stroke, strokeWidth):
            drawPath(path, fill: fill, stroke: stroke, strokeWidth: strokeWidth, in: ctx)

        case let .drawImage(image, rect):
            drawFlippedImage(image, in: rect, context: ctx)

        case let .drawImageReference(binItemId, rect, style, clipRect):
            drawImageReference(binItemId, style: style, in: rect, clipTo: clipRect, context: ctx)

        case let .drawPlaceholder(rect, text):
            drawPlaceholder(text, in: rect, context: ctx)

        case .hyperlink:
            // 시각 표시 없음 (한글.app: 하이퍼링크는 글자 장식만) —
            // rect는 히트 테스트용으로만 유지된다
            break
        }
    }

    /// 커맨드 인덱스로 조판 결과를 재사용한다. 인덱스만 믿지 않고 페이로드까지
    /// 대조하는 이유: `init(layer:)`의 대입은 didSet을 타지 않고, 프로그레시브
    /// 갱신 경로는 기존 레이어의 paintList를 재대입하지 않는다 (양쪽 뷰의
    /// `paintList == nil` 가드). 무효화가 새더라도 스테일 배치를 그리지 않게 하는
    /// 2차 방어선이고, 덕분에 origin·lineWidth 비유한값도 바운드된 미스로 끝난다.
    private func cachedDrawnLines(
        commandIndex: Int,
        attributedString: NSAttributedString,
        origin: CGPoint,
        lineWidth: CGFloat
    ) -> [HwpDrawnLine] {
        drawnLineCacheLock.lock()
        let hit = drawnLineCache[commandIndex]
        drawnLineCacheLock.unlock()
        if let hit,
           hit.attributedString === attributedString,
           hit.origin == origin,
           hit.lineWidth == lineWidth
        {
            return hit.lines
        }

        // 조판은 락 밖에서 — 비싸고, 드문 중복 계산은 순수 함수라 결과가 같다.
        let lines = typesetLines(attributedString, origin: origin, lineWidth: lineWidth)

        drawnLineCacheLock.lock()
        if let stale = drawnLineCache.removeValue(forKey: commandIndex) {
            cachedLineCount -= stale.lines.count
        }
        if cachedLineCount + lines.count <= cachedLineBudget {
            drawnLineCache[commandIndex] = DrawnLineEntry(
                attributedString: attributedString,
                origin: origin,
                lineWidth: lineWidth,
                lines: lines
            )
            cachedLineCount += lines.count
        }
        drawnLineCacheLock.unlock()
        return lines
    }

    /// 캐시를 모르는 순수 조판. `drawPlaceholder`처럼 매 draw마다 새 문자열을 만드는
    /// 경로는 이걸 직접 부른다 — 그 문자열은 draw 종료와 함께 해제되므로 캐시에
    /// 넣으면 엔트리가 무한 증식하거나 주소 재사용으로 오조판이 난다.
    ///
    /// `maxLineFrames`는 항상 기본값 (`HwpParagraphLayout.maximumLineFrames` — static
    /// let 상수)이라 캐시 키에서 생략한다. 여기에 인자를 노출하게 되면 키에도
    /// 반드시 넣어야 한다.
    private func typesetLines(
        _ attributedString: NSAttributedString,
        origin: CGPoint,
        lineWidth: CGFloat
    ) -> [HwpDrawnLine] {
        drawnLineCacheLock.lock()
        typesetCallCount += 1
        drawnLineCacheLock.unlock()
        return HwpDrawnTextLayout.lines(
            attributedString: attributedString,
            origin: origin,
            lineWidth: lineWidth
        )
    }

    /// 줄 배치는 `HwpDrawnTextLayout` (렌더·텍스트 선택 공유 — slight-overflow
    /// 단일 줄, 양쪽 정렬 재조판, baselineLift 포함)이 계산하고, 여기서는
    /// top-down 결과를 이 레이어의 y-up 텍스트 공간으로 변환해 그리기만 한다.
    /// 배치가 `pageHeight`·`bounds`·`contentsScale`에 무관하다는 것이 이 분리의
    /// 요점이다 — 줌 종료·재래스터 재드로에서 캐시가 그대로 유효하다.
    private func drawTextLines(_ drawnLines: [HwpDrawnLine], in ctx: CGContext) {
        guard !drawnLines.isEmpty else { return }
        let effectivePageHeight = pageHeight > 0 ? pageHeight : bounds.height
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.translateBy(x: 0, y: effectivePageHeight)
        ctx.scaleBy(x: 1, y: -1)
        for drawnLine in drawnLines {
            let lineOrigin = CGPoint(
                x: drawnLine.baselineOrigin.x,
                y: effectivePageHeight - drawnLine.baselineOrigin.y
            )
            ctx.textPosition = lineOrigin
            drawDecoratedLine(drawnLine.line, origin: lineOrigin, in: ctx)
        }
        ctx.restoreGState()
    }

    /// paint list가 해당 BinItem 이미지를 참조하는지 (targeted redraw 판단용)
    public func containsImageReference(_ binItemId: UInt32) -> Bool {
        guard let paintList else { return false }
        return paintList.commands.contains {
            if case let .drawImageReference(key, _, _, _) = $0 {
                key == binItemId
            } else {
                false
            }
        }
    }

    /// 컨텍스트가 top-left 기준으로 뒤집혀 있으므로 이미지는 rect 기준으로 재반전해 그린다.
    private func drawFlippedImage(_ image: CGImage, in rect: CGRect, context ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: rect.minY + rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: rect)
        ctx.restoreGState()
    }

    private func drawImageReference(
        _ binItemId: UInt32,
        style: HwpImageRenderStyle?,
        in rect: CGRect,
        clipTo clipRect: CGRect?,
        context ctx: CGContext
    ) {
        // 절단면에 걸친 분할 셀 그림 — rect (저작 기하) 그대로 그리되 가시
        // 영역만 남긴다 (로딩 표시·플레이스홀더 포함, R32 #2)
        if let clipRect {
            ctx.saveGState()
            ctx.clip(to: clipRect)
        }
        defer {
            if clipRect != nil {
                ctx.restoreGState()
            }
        }
        guard let imageProvider else {
            drawPlaceholder("[이미지]", in: rect, context: ctx)
            return
        }
        if let image = imageProvider.cachedImage(for: binItemId, style: style) {
            drawFlippedImage(image, in: rect, context: ctx)
            return
        }
        if imageProvider.didFail(for: binItemId, style: style) {
            drawPlaceholder("[이미지]", in: rect, context: ctx)
            return
        }
        // 로딩 중 표시 후 비동기 디코딩을 트리거한다.
        ctx.setFillColor(CGColor(gray: 0.95, alpha: 1))
        ctx.fill(rect)
        imageProvider.requestImage(for: binItemId, style: style)
    }

    private func drawPath(
        _ path: CGPath,
        fill: CGColor?,
        stroke: CGColor?,
        strokeWidth: CGFloat,
        in ctx: CGContext
    ) {
        if let fill {
            ctx.addPath(path)
            ctx.setFillColor(fill)
            ctx.fillPath()
        }

        if let stroke {
            ctx.addPath(path)
            ctx.setStrokeColor(stroke)
            ctx.setLineWidth(strokeWidth)
            ctx.strokePath()
        }
    }

    private static let placeholderFont = CTFontCreateWithName("Helvetica" as CFString, 12, nil)

    private func drawPlaceholder(_ text: String, in rect: CGRect, context ctx: CGContext) {
        ctx.setFillColor(CGColor(gray: 0.9, alpha: 1))
        ctx.fill(rect)

        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: CGColor(gray: 0, alpha: 1),
            .font: Self.placeholderFont,
        ]
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let textSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: attributedString.length),
            nil,
            rect.size,
            nil
        )
        let origin = CGPoint(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2
        )
        // 캐시 우회 — 이 attributedString은 호출마다 새로 만들어져 draw 종료와 함께
        // 해제된다. 커맨드 인덱스가 없으니 캐시에 닿을 통로 자체가 없다.
        drawTextLines(
            typesetLines(
                attributedString,
                origin: origin,
                lineWidth: max(textSize.width, 1)
            ),
            in: ctx
        )
    }
}
