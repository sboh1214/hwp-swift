import CoreGraphics
import CoreText
import Foundation

/// OLE 내장 차트 (`HwpChartFrame`)를 근사 렌더하는 페인트 커맨드 생성기.
///
/// 한글.app mac 렌더러 실물 캡처 (2026-07-10, chart 픽스처) 픽셀 실측 기반
/// 3D 상자 기하: 앞 왼쪽 세로 축 + 축-뒷벽 깊이 세그먼트 + 수평 그리드의
/// 뒷벽 + 평행사변형 바닥 위에 계열이 깊이 방향으로 물러나는 원뿔.
/// 한글.app mac의 3D는 소실점 원근이 아니라 평행 (oblique) 투영이다 —
/// 실측: 뒷벽 그리드 수렴 0·눈금 간격 좌우 동일·깊이 세그먼트 평행·원뿔
/// 폭 전 계열 동일. 이 페인터도 같은 평행 투영. pie/line 등 기타 차트
/// 종류는 미재현 (전부 세로 막대 취급).
///
/// 차트 투영 상수는 상호 결합 실측 모델이라 in-place 유지 —
/// `HwpRenderTuning` 규약 (값 변경 시 fidelity+스냅샷+실물 대조) 참조.
enum HwpChartPainter {
    /// 한컴 기본 차트 계열색 — 한글.app mac 렌더러 실측. 캡처 원시값이
    /// 아니라 색 관리(BT.2020 태그) 변환 후 sRGB 값이 실제 색이다
    /// (라운드 8 — 회색 계열이 양쪽 178로 불변인 것으로 확정)
    private static let seriesColors: [HwpRGBColor] = [
        HwpRGBColor(red: 0.380, green: 0.514, blue: 0.835), // #6183D5
        HwpRGBColor(red: 0.996, green: 0.518, blue: 0.227), // #FE843A
        HwpRGBColor(red: 0.698, green: 0.698, blue: 0.698), // #B2B2B2
        HwpRGBColor(red: 1.00, green: 0.78, blue: 0.25), // 노랑 계열 (미실측 — 근사)
        HwpRGBColor(red: 0.47, green: 0.67, blue: 0.86), // 하늘 계열 (미실측 — 근사)
        HwpRGBColor(red: 0.55, green: 0.74, blue: 0.42), // 초록 계열 (미실측 — 근사)
    ]

    /// 실물 격자선 코어 회색 133/255 (라운드 6 픽셀 실측)
    static let gridColor = HwpRGBColor(red: 0.52, green: 0.52, blue: 0.52).cgColor

    /// 축 값 상한 — 비유한(1e309→inf/nan)·거대 값(신뢰 못 할 차트 XML)을 클램프해
    /// axisMax의 Int 변환 트랩을 막는다 (근사 렌더).
    private static let maxAxisValue = 1_000_000
    /// 그리는 축 눈금 최대 개수 — 실측 차트(값 수백 이하)는 정수마다 1개(step 1)라
    /// 기존 렌더와 동일하고, 병적으로 큰 축만 step을 키워 작업량/할당을 상한한다.
    private static let maxDrawnTicks = 1000

    /// 3D 상자 기하 — 차트 프레임 대비 비율은 전부 실물 캡처 실측값.
    /// 바닥 = FL(앞왼)→FR(앞오)→BR(뒤오)→BL(뒤왼) 평행사변형,
    /// 뒷벽 = BL/BR 위 수직 벽 (그리드는 수평), 앞 축 = FL 위 수직선.
    struct Box {
        let frontAxisX: CGFloat // 프레임 폭의 0.140
        let floorFrontY: CGFloat // 프레임 높이의 0.824
        let floorFrontRightX: CGFloat // 프레임 폭의 0.670
        let depth: CGSize // (0.104 W, -0.124 H)
        let wallHeight: CGFloat // 프레임 높이의 0.411
        let axisMax: Double
        let labelSize: CGFloat
        let labelFont: CTFont
        let categoryCount: Int

        var backLeftX: CGFloat {
            frontAxisX + depth.width
        }

        var backRightX: CGFloat {
            floorFrontRightX + depth.width
        }

        var groupWidth: CGFloat {
            (floorFrontRightX - frontAxisX) / CGFloat(max(1, categoryCount))
        }

        /// 앞 축의 눈금 y (tick 0 = 바닥 전면)
        func frontTickY(_ tick: Int) -> CGFloat {
            floorFrontY - CGFloat(tick) / CGFloat(max(1, Int(axisMax))) * wallHeight
        }

        /// 계열의 깊이 진행률 (0 = 바닥 전면). 라운드 3 실측: 스텝당 가로
        /// 오프셋 = 그룹 간격의 ~0.28배 — 원뿔 밑면이 서로 겹친다.
        func depthStep(seriesCount: Int, seriesIndex: Int) -> CGFloat {
            guard seriesCount > 1 else { return 0.3 }
            // 계열 1도 바닥 전면선에서 살짝 안쪽에서 시작한다 (실물)
            // 라운드 12 실측: 계열 간 스텝 = 깊이의 0.325 (0.65/(n-1), n=3)
            return 0.15 + 0.65 / CGFloat(seriesCount - 1) * CGFloat(seriesIndex)
        }
    }

    static func commands(
        _ chart: HwpChartFrame,
        frame: CGRect,
        fontResolver: HwpFontResolver
    ) -> [HwpPaintCommand] {
        var commands: [HwpPaintCommand] = [
            .fillRect(rect: frame, color: .hwpWhite),
            .strokeRect(
                rect: frame,
                color: HwpRGBColor(red: 0.52, green: 0.52, blue: 0.52).cgColor,
                width: 0.75
            ),
        ]

        if let title = chart.title {
            commands.append(titleCommand(title, frame: frame, fontResolver: fontResolver))
        }

        let categoryCount = max(chart.categories.count, chart.series.first?.values.count ?? 0)
        guard categoryCount > 0, frame.width > 40, frame.height > 40 else { return commands }

        let labelSize = max(6, frame.height * 0.044)
        // 유한 양수만 반영하고 안전 상한으로 클램프한다 — 비유한/거대 값이
        // axisMax의 Int 변환을 트랩시키거나 눈금 루프를 폭주시키는 것을 막는다.
        let maxValue = min(
            chart.series.flatMap(\.values).filter { $0.isFinite && $0 > 0 }.max() ?? 1,
            Double(maxAxisValue)
        )
        let box = Box(
            frontAxisX: frame.minX + frame.width * 0.140,
            floorFrontY: frame.minY + frame.height * 0.824,
            floorFrontRightX: frame.minX + frame.width * 0.670,
            // 라운드 9 실측: 깊이 벡터는 프레임 폭의 0.136 (방향 유지,
            // 라운드 2 값이 19% 과대) → (0.112W, −0.133H)
            depth: CGSize(width: frame.width * 0.112, height: -frame.height * 0.133),
            wallHeight: frame.height * 0.465 * 0.96,
            axisMax: max(1, ceil(maxValue)),
            labelSize: labelSize,
            labelFont: fontResolver.resolve(
                faceName: "함초롬돋움", script: .korean, size: labelSize
            ),
            categoryCount: categoryCount
        )

        commands += axisCommands(box)
        commands += markerCommands(chart, box)
        commands += categoryLabelCommands(chart, box)
        if chart.showLegend, !chart.series.isEmpty {
            commands += legendCommands(chart, box, frame: frame)
        }
        return commands
    }

    // MARK: - 구성 요소별 커맨드

    private static func titleCommand(
        _ title: String,
        frame: CGRect,
        fontResolver: HwpFontResolver
    ) -> HwpPaintCommand {
        let titleFont = fontResolver.resolve(
            faceName: "함초롬돋움", script: .korean,
            size: max(9, frame.height * 0.071)
        )
        let attributed = label(title, font: titleFont)
        let width = labelWidth(attributed)
        return .drawText(
            attributedString: attributed,
            origin: CGPoint(
                x: frame.midX - width / 2,
                y: frame.minY + frame.height * 0.063
            ),
            lineWidth: width + 2
        )
    }

    /// 3D 상자 선: 앞 축 + 눈금별 깊이 세그먼트 + 뒷벽 수평 그리드 +
    /// 뒷벽 오른쪽 모서리 + 바닥 전면/오른쪽 모서리 + y축 라벨
    private static func axisCommands(_ box: Box) -> [HwpPaintCommand] {
        var commands: [HwpPaintCommand] = []
        let lines = CGMutablePath()
        let tickCount = max(1, Int(box.axisMax))
        // 눈금 간격: 그리는 눈금 수를 maxDrawnTicks로 상한한다. 실측 차트는
        // step 1로 정수마다 그려 기존 렌더와 동일하고, 병적 축만 성기게 그린다.
        let step = max(1, (tickCount + maxDrawnTicks - 1) / maxDrawnTicks)
        for tick in stride(from: 0, through: tickCount, by: step) {
            let frontY = box.frontTickY(tick)
            let backY = frontY + box.depth.height
            // 깊이 세그먼트 (앞 축 → 뒷벽 왼쪽)
            lines.move(to: CGPoint(x: box.frontAxisX, y: frontY))
            lines.addLine(to: CGPoint(x: box.backLeftX, y: backY))
            // 뒷벽 수평 그리드
            lines.move(to: CGPoint(x: box.backLeftX, y: backY))
            lines.addLine(to: CGPoint(x: box.backRightX, y: backY))

            let attributed = label("\(tick)", font: box.labelFont)
            let width = labelWidth(attributed)
            commands.append(.drawText(
                attributedString: attributed,
                origin: CGPoint(
                    x: box.frontAxisX - width - 12,
                    y: frontY - box.labelSize * 0.55
                ),
                lineWidth: width + 2
            ))
        }
        // 값축 눈금 틱 (축 왼쪽 돌출 — 실물 라운드 9)
        for tick in stride(from: 0, through: tickCount, by: step) {
            let frontY = box.frontTickY(tick)
            lines.move(to: CGPoint(x: box.frontAxisX - 3, y: frontY))
            lines.addLine(to: CGPoint(x: box.frontAxisX, y: frontY))
        }
        // 앞 축 세로선
        lines.move(to: CGPoint(x: box.frontAxisX, y: box.frontTickY(tickCount)))
        lines.addLine(to: CGPoint(x: box.frontAxisX, y: box.floorFrontY))
        // 뒷벽 오른쪽 모서리
        lines.move(to: CGPoint(
            x: box.backRightX, y: box.frontTickY(tickCount) + box.depth.height
        ))
        lines.addLine(to: CGPoint(x: box.backRightX, y: box.floorFrontY + box.depth.height))
        // 바닥 전면 모서리 + 오른쪽 깊이 모서리
        lines.move(to: CGPoint(x: box.frontAxisX, y: box.floorFrontY))
        lines.addLine(to: CGPoint(x: box.floorFrontRightX, y: box.floorFrontY))
        lines.addLine(to: CGPoint(x: box.backRightX, y: box.floorFrontY + box.depth.height))
        // 실물은 논리 1px 헤어라인 — 0.5는 AA 커버리지 ~61%로 연해 보인다
        commands.append(.drawPath(path: lines, fill: nil, stroke: gridColor, strokeWidth: 1.0))
        return commands
    }

    private static func markerCommands(
        _ chart: HwpChartFrame,
        _ box: Box
    ) -> [HwpPaintCommand] {
        let seriesCount = max(1, chart.series.count)
        // 실물 (2026-07-10 그룹1 픽셀 실측): 원뿔 밑면 폭 = 그룹폭의 0.30으로
        // 전 계열 동일 (깊이 감쇠 없음 — 평행 투영), 가로 위치도 그룹 안
        // 고정 지점 (0.625 그룹폭)이고 계열 분리는 깊이 이동이 전부 만든다
        // 실물 (라운드 6): 밑면 폭 = 카테고리 간격의 0.42 (인접 원뿔 맞닿음)
        let markerWidth = box.groupWidth * 0.42
        let isCone: Bool = switch chart.kind {
        case let .bar(cone): cone
        }

        var commands: [HwpPaintCommand] = []
        // 뒤 계열부터 그려 앞 계열이 겹쳐 보이게 (실물)
        for (seriesIndex, series) in chart.series.enumerated().reversed() {
            let color = seriesColors[seriesIndex % seriesColors.count].cgColor
            let step = box.depthStep(seriesCount: seriesCount, seriesIndex: seriesIndex)
            let baseY = box.floorFrontY + box.depth.height * step
            for (categoryIndex, value) in series.values.enumerated()
                where categoryIndex < box.categoryCount
            {
                // 실물 (라운드 9 회귀 실측): 높이 = 격자 × 값 + 밑면 타원
                // 처짐 절편 (0.13 격자 단위) — 기울기 보정 ×1.09는 과대
                let height = CGFloat(value / box.axisMax) * box.wallHeight
                    + 0.13 / CGFloat(box.axisMax) * box.wallHeight
                guard height > 0 else { continue }
                let groupStart = box.frontAxisX + box.groupWidth * CGFloat(categoryIndex)
                // depthStep 시작 오프셋 (+0.15)의 가로 밀림을 보상해 실물의
                // 원뿔 x 위치를 유지한다 (라운드 6 실측: 원뿔만 +0.017W)
                let centerX = groupStart + box.groupWidth * 0.625
                    + box.depth.width * (step - 0.15)
                commands.append(.drawPath(
                    path: markerPath(
                        centerX: centerX, baseY: baseY,
                        width: markerWidth, height: height, cone: isCone
                    ),
                    fill: color, stroke: nil, strokeWidth: 0
                ))
                if isCone {
                    commands += coneShadingCommands(
                        centerX: centerX, baseY: baseY,
                        width: markerWidth, height: height
                    )
                }
            }
        }
        return commands
    }

    private static func categoryLabelCommands(
        _ chart: HwpChartFrame,
        _ box: Box
    ) -> [HwpPaintCommand] {
        var commands: [HwpPaintCommand] = chart.categories.enumerated().map { index, category in
            let attributed = label(category, font: box.labelFont)
            let width = labelWidth(attributed)
            let centerX = box.frontAxisX + box.groupWidth * (CGFloat(index) + 0.5)
            return .drawText(
                attributedString: attributed,
                origin: CGPoint(
                    x: centerX - width / 2,
                    y: box.floorFrontY + box.labelSize * 1.55
                ),
                lineWidth: width + 2
            )
        }
        // 카테고리 경계 눈금 (바닥 전면선 아래 — 실물)
        let ticks = CGMutablePath()
        for index in 0 ... box.categoryCount {
            let x = box.frontAxisX + box.groupWidth * CGFloat(index)
            ticks.move(to: CGPoint(x: x, y: box.floorFrontY))
            ticks.addLine(to: CGPoint(x: x, y: box.floorFrontY + 3))
        }
        commands.append(.drawPath(path: ticks, fill: nil, stroke: gridColor, strokeWidth: 1.0))
        return commands
    }

    /// 범례 (실물: 프레임 폭 0.917 지점, 세로 중앙 0.585H, 행 간격 라벨×1.67)
    private static func legendCommands(
        _ chart: HwpChartFrame,
        _ box: Box,
        frame: CGRect
    ) -> [HwpPaintCommand] {
        var commands: [HwpPaintCommand] = []
        let rowHeight = box.labelSize * 1.67
        let totalHeight = rowHeight * CGFloat(chart.series.count)
        var y = frame.minY + frame.height * 0.585 - totalHeight / 2
        // 스와치+텍스트가 프레임 오른쪽 테두리를 넘지 않게 오른쪽 정렬
        // (실물: 범례 텍스트 끝이 테두리 안 — 2026-07-10 검증)
        let maxNameWidth = chart.series
            .map { labelWidth(label($0.name, font: box.labelFont)) }
            .max() ?? 0
        let x = min(
            frame.minX + frame.width * 0.870,
            frame.maxX - 4 - box.labelSize * 1.1 - maxNameWidth
        )
        for (index, series) in chart.series.enumerated() {
            commands.append(.fillRect(
                rect: CGRect(
                    x: x, y: y + box.labelSize * 0.15,
                    width: box.labelSize * 0.8, height: box.labelSize * 0.8
                ),
                color: seriesColors[index % seriesColors.count].cgColor
            ))
            let name = label(series.name, font: box.labelFont)
            commands.append(.drawText(
                attributedString: name,
                origin: CGPoint(x: x + box.labelSize * 1.1, y: y),
                lineWidth: labelWidth(name) + 4
            ))
            y += rowHeight
        }
        return commands
    }
}

// MARK: - 프리미티브

private extension HwpChartPainter {
    /// 원뿔 (삼각형 + 바닥 타원 불룩) 또는 사각 막대 path
    static func markerPath(
        centerX: CGFloat,
        baseY: CGFloat,
        width: CGFloat,
        height: CGFloat,
        cone: Bool
    ) -> CGPath {
        let halfWidth = width / 2
        guard cone else {
            return CGPath(
                rect: CGRect(
                    x: centerX - halfWidth, y: baseY - height,
                    width: width, height: height
                ),
                transform: nil
            )
        }
        let path = CGMutablePath()
        // 실물 밑면 타원은 훨씬 납작하다 (라운드 7 실측: 곡률 절반)
        let baseEllipseHeight = min(halfWidth * 0.2, height * 0.09)
        path.move(to: CGPoint(x: centerX - halfWidth, y: baseY - baseEllipseHeight / 2))
        path.addLine(to: CGPoint(x: centerX, y: baseY - height))
        path.addLine(to: CGPoint(x: centerX + halfWidth, y: baseY - baseEllipseHeight / 2))
        path.addQuadCurve(
            to: CGPoint(x: centerX - halfWidth, y: baseY - baseEllipseHeight / 2),
            control: CGPoint(x: centerX, y: baseY + baseEllipseHeight)
        )
        path.closeSubpath()
        return path
    }

    /// 원뿔 명암: 오른쪽 절반 어둡게 + 왼쪽 중앙 밝은 띠.
    /// 한글.app mac 렌더러는 거의 평면으로 칠하므로 아주 미세하게만.
    static func coneShadingCommands(
        centerX: CGFloat,
        baseY: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> [HwpPaintCommand] {
        let halfWidth = width / 2
        // 실물 밑면 타원은 훨씬 납작하다 (라운드 7 실측: 곡률 절반)
        let baseEllipseHeight = min(halfWidth * 0.2, height * 0.09)
        let apex = CGPoint(x: centerX, y: baseY - height)
        let baseEdgeY = baseY - baseEllipseHeight / 2

        // 우측 가장자리의 좁고 진한 음영 스트립 (실물: 몸통 대비 휘도 절반)
        // 실물은 넓은 그라데이션이 아니라 가는 모서리 선 (라운드 12 실측:
        // 가시 폭의 ~5%) — 스트립을 능선 쪽 좁은 조각으로 한정
        let dark = CGMutablePath()
        dark.move(to: apex)
        dark.addLine(to: CGPoint(x: centerX + halfWidth, y: baseEdgeY))
        dark.addQuadCurve(
            to: CGPoint(x: centerX + halfWidth * 0.88, y: baseY - baseEllipseHeight * 0.05),
            control: CGPoint(x: centerX + halfWidth * 0.97, y: baseY + baseEllipseHeight * 0.1)
        )
        dark.closeSubpath()

        let light = CGMutablePath()
        light.move(to: apex)
        light.addLine(to: CGPoint(
            x: centerX - halfWidth * 0.45, y: baseEdgeY + baseEllipseHeight * 0.3
        ))
        light.addLine(to: CGPoint(
            x: centerX - halfWidth * 0.12, y: baseEdgeY + baseEllipseHeight * 0.5
        ))
        light.closeSubpath()

        // 오른쪽 능선의 가는 진한 모서리 선 (실물: 면-선-면 구조)
        let ridge = CGMutablePath()
        ridge.move(to: apex)
        ridge.addQuadCurve(
            to: CGPoint(x: centerX + halfWidth * 0.72, y: baseEdgeY + baseEllipseHeight * 0.2),
            control: CGPoint(x: centerX + halfWidth * 0.5, y: baseY - height * 0.4)
        )
        return [
            .drawPath(
                path: dark,
                fill: CGColor(gray: 0, alpha: 0.42),
                stroke: nil, strokeWidth: 0
            ),
            .drawPath(
                path: light,
                fill: CGColor(gray: 1, alpha: 0.10),
                stroke: nil, strokeWidth: 0
            ),
            .drawPath(
                path: ridge,
                fill: nil,
                stroke: CGColor(gray: 0, alpha: 0.5),
                strokeWidth: 0.5
            ),
        ]
    }

    static func label(_ text: String, font: CTFont) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor.hwpBlack,
        ])
    }

    /// CTLine 실측 폭 (중앙/우측 정렬 origin 계산용)
    static func labelWidth(_ attributed: NSAttributedString) -> CGFloat {
        let line = CTLineCreateWithAttributedString(attributed)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}
