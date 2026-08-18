#if os(iOS)
    import CoreGraphics
    import HwpKitCore
    import UIKit

    // MARK: - 선택 끝점 핸들 (#84)

    /// 선택 끝점 핸들 하나 — 캐럿 바 + 그립.
    ///
    /// **뷰 본체(`HwpDocumentUIView`)의 서브뷰**이자 스크롤 뷰의 형제다.
    /// `contentView` 계층에 두면 두 가지가 따라온다.
    ///
    /// 1. 줌 대상(`viewForZooming` → `contentView`)의 transform을 물려받아
    ///    0.25x에서 점이 되고 5x에서 거대해진다 — 매 갱신 배율 역보정이 필요하다.
    /// 2. 터치가 스크롤 pan·핀치·롱프레스·탭과 같은 계층에서 경합한다. 특히
    ///    탭 핸들러의 첫 분기가 `hasSelection`이면 `clear()`라, 핸들을 톡 치면
    ///    **선택이 통째로 사라진다**.
    ///
    /// 형제로 두면 히트 테스트가 여기서 끝나 그 경합이 아예 생기지 않는다 —
    /// 이 저장소에는 제스처 중재 코드가 한 건도 없으므로(`require(toFail:)`·
    /// `UIGestureRecognizerDelegate` 0건) 중재 계층을 새로 세우는 대신
    /// 계층 배치로 푼다.
    final class HwpSelectionHandleView: UIView {
        let edge: HwpSelectionEdge
        /// 색은 `UIView.backgroundColor`에 **동적 UIColor**로 둔다 — `CALayer`의
        /// `backgroundColor`(CGColor)는 해석 시점 트레잇에 고정돼 다크 모드
        /// 전환에서 옛 색이 남는다.
        private let bar = UIView()
        private let knob = UIView()

        init(edge: HwpSelectionEdge) {
            self.edge = edge
            super.init(frame: .zero)
            backgroundColor = .clear
            // 선택 하이라이트(systemBlue 30%)와 같은 계열로 맞춘다.
            for part in [bar, knob] {
                part.backgroundColor = .systemBlue
                part.isUserInteractionEnabled = false
                addSubview(part)
            }
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            let parts = HwpSelectionHandleGeometry.handleParts(in: bounds, edge: edge)
            bar.frame = parts.bar
            knob.frame = parts.knob
            knob.layer.cornerRadius = parts.knob.width / 2
        }

        /// 손가락은 그립보다 크다 — 그리는 크기보다 넓게 잡는다.
        override func point(inside point: CGPoint, with _: UIEvent?) -> Bool {
            HwpSelectionHandleGeometry.isWithinGrabArea(point, bounds: bounds)
        }
    }

    /// 선택 제스처의 일시 상태.
    ///
    /// 값 타입 하나로 묶는 이유는 순전히 SwiftLint다 — `HwpDocumentUIView`의
    /// 타입 본문이 `type_body_length` **error** 임계(400)에 정확히 닿아 있어
    /// 저장 프로퍼티를 한 줄만 늘려도 Lint 잡이 종료 코드 2로 끝난다. 그래서
    /// 신규 상태만 묶는 것이 아니라 기존 오토스크롤·편집 메뉴 상태까지 함께
    /// 접어 본문 줄 수를 **순감**시킨다.
    struct HwpSelectionInteractionState {
        /// 손가락이 뷰포트 엣지 존에 멈춰 있어도 스크롤을 미는 표시 링크
        var autoscrollLink: CADisplayLink?
        /// 엣지 존 판정에 쓰는 **뷰포트** 좌표. 핸들 드래그에서는 그랩 오프셋을
        /// 이미 더한 캐럿 좌표라, 틱은 이 점 하나만 보고 그대로 확장하면 된다.
        var autoscrollViewportPoint: CGPoint?
        var editMenuInteraction: UIEditMenuInteraction?
        var startHandle: HwpSelectionHandleView?
        var endHandle: HwpSelectionHandleView?
        /// 그랩 순간 (캐럿 중심 − 터치점). 드래그 중 터치점에 더해 캐럿이
        /// 손가락으로 튀지 않게 한다.
        var grabOffset: CGPoint = .zero
    }

    extension HwpDocumentUIView {
        func configureSelectionHandles() {
            selectionInteraction.startHandle = makeSelectionHandle(edge: .start)
            selectionInteraction.endHandle = makeSelectionHandle(edge: .end)
        }

        private func makeSelectionHandle(edge: HwpSelectionEdge) -> HwpSelectionHandleView {
            let handle = HwpSelectionHandleView(edge: edge)
            // 선택이 없으면 그리지도, 잡히지도 않는다 (alpha 0은 히트 테스트 제외).
            handle.alpha = 0
            handle.addGestureRecognizer(UIPanGestureRecognizer(
                target: self, action: #selector(handleSelectionHandlePan(_:))
            ))
            // 스크롤 뷰 **뒤에** 붙어야 히트 테스트가 핸들을 먼저 본다.
            addSubview(handle)
            return handle
        }

        /// 핸들 위치·표시를 다시 잡는다.
        ///
        /// 갱신 진입점은 셋이다. ①선택 변경(`onSelectionChanged`)·②가시 페이지
        /// 갱신(`updateVisiblePages`)·③줌 종료 배율 재적용
        /// (`updateLayerContentsScale`)이 모두 `updateSelectionOverlays()`를
        /// 지나므로 그 안에서 부른다. 스크롤만 예외로 `scrollViewDidScroll`이
        /// 직접 부르는데, 그 함수의 `range != activeVisibleRange` 가드가 가시
        /// 범위가 같은 스크롤을 조기 반환하기 때문이다 — 핸들은 줌 대상 밖에
        /// 살아서 스크롤을 **따라 움직이지 않는다**.
        func updateSelectionHandles() {
            let carets = selectionController.selectionCarets()
            place(carets.first { $0.edge == .start }, on: selectionInteraction.startHandle)
            place(carets.first { $0.edge == .end }, on: selectionInteraction.endHandle)
        }

        /// 숨길 때 `isHidden`이 아니라 `alpha`를 쓰는 이유: 핸들 역할 뒤바뀜
        /// 이후에는 **드래그를 소유한 뷰가 고정단으로 옮겨 가** 화면 밖으로
        /// 스크롤될 수 있다. `alpha == 0`은 히트 테스트에서 제외되면서도 진행
        /// 중인 제스처 인식에는 영향이 없다.
        private func place(_ caret: HwpSelectionCaret?, on handle: HwpSelectionHandleView?) {
            guard let handle else { return }
            guard let caret, let caretRect = selectionCaretRectInView(caret) else {
                handle.alpha = 0
                return
            }
            handle.alpha = 1
            handle.frame = HwpSelectionHandleGeometry.handleFrame(
                caretRect: caretRect, edge: caret.edge
            )
        }

        /// 페이지 로컬 캐럿 rect → 이 뷰의 좌표. 뷰포트 밖이면 nil.
        ///
        /// `contentView.convert`가 줌 transform과 스크롤 오프셋을 함께
        /// 반영하므로 배율 역보정 산식이 따로 필요 없다.
        private func selectionCaretRectInView(_ caret: HwpSelectionCaret) -> CGRect? {
            let pageFrame = selectionPageFrame(at: caret.pageIndex)
            let contentRect = caret.rect.offsetBy(dx: pageFrame.minX, dy: pageFrame.minY)
            let viewRect = contentView.convert(contentRect, to: self)
            guard HwpSelectionHandleGeometry.isCaretVisible(
                caretRect: viewRect, in: bounds
            ) else { return nil }
            return viewRect
        }

        // MARK: 드래그

        @objc private func handleSelectionHandlePan(_ gesture: UIPanGestureRecognizer) {
            guard let handle = gesture.view as? HwpSelectionHandleView else { return }
            let viewPoint = gesture.location(in: self)
            switch gesture.state {
            case .began:
                beginSelectionHandleDrag(handle, at: viewPoint)
            case .changed:
                extendSelectionHandleDrag(to: viewPoint)
            case .ended, .cancelled, .failed:
                endSelectionHandleDrag(at: viewPoint)
            default:
                break
            }
        }

        private func beginSelectionHandleDrag(
            _ handle: HwpSelectionHandleView, at viewPoint: CGPoint
        ) {
            becomeFirstResponder()
            selectionInteraction.editMenuInteraction?.dismissMenu()
            // 오프셋은 조정 성패와 무관하게 **이번 드래그의 것**으로 덮는다 —
            // 아래 guard로 빠져나가면서 지난 드래그 값을 남기면 다음 `.changed`가
            // 그 낡은 값으로 캐럿을 옮긴다.
            selectionInteraction.grabOffset = HwpSelectionHandleGeometry.grabOffset(
                caretCenter: HwpSelectionHandleGeometry.caretCenter(
                    handleFrame: handle.frame, edge: handle.edge
                ),
                touchPoint: viewPoint
            )
            // 잡은 끝점을 focus로 바꾸는 것은 **여기 한 번뿐**이다. 이후 확장은
            // 기존 extend(to:)가 그대로 하고, 오토스크롤 틱도 늘 focus를 밀므로
            // 손댈 곳이 없다.
            selectionController.beginAdjusting(edge: handle.edge)
        }

        private func extendSelectionHandleDrag(to viewPoint: CGPoint) {
            // 핸들 드래그는 **기존 선택을 조정**할 뿐 새로 만들지 않는다.
            // `hasSelection`이 아니라 nil을 보는 이유: 반대 끝점 위에 정확히
            // 겹치면 범위가 비어(`hasSelection == false`) 거기서 다시 끌어낼
            // 길이 막힌다.
            guard selectionController.selection != nil else { return }
            let caretPoint = HwpSelectionHandleGeometry.caretPoint(
                touchPoint: viewPoint, grabOffset: selectionInteraction.grabOffset
            )
            selectionInteraction.autoscrollViewportPoint = caretPoint
            updateSelectionAutoscroll()
            let contentPoint = contentView.convert(caretPoint, from: self)
            guard let position = selectionPosition(at: contentPoint) else { return }
            selectionController.extend(to: position)
        }

        private func endSelectionHandleDrag(at viewPoint: CGPoint) {
            stopSelectionAutoscroll()
            selectionInteraction.grabOffset = .zero
            guard !clearCollapsedSelection() else { return }
            presentEditMenuIfNeeded(at: contentView.convert(viewPoint, from: self))
        }
    }
#endif
