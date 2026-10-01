import CoreGraphics
import Foundation
import HwpKit
import HwpKitCore
import Nimble
import XCTest

/// `table-border-chains` 픽스처 쌍 (#238) — 표 셀 테두리의 원형 점선·긴 점선이 칸 경계에서
/// 다시 시작하지 않고 격자선을 따라 이어지는지, 한글이 다시 시작하는 자리에서만 다시 시작하는지를
/// 페인트 목록으로 잠근다.
///
/// 오라클은 한글 12.30.0(build 6446, macOS)이 같은 편집 세션에서 `PDF로 저장하기…`로 내보낸 벡터
/// 좌표다 (2026-09-27, PyMuPDF; 표 왼 모서리 기준 pt, 0.12pt 장치 격자). 칸 폭은 22.8pt이고, 굵기
/// 1mm 원은 한글처럼 간격 5.76(48u)·칠 지름 3.0(경로 2.88 + 윤곽 0.12), 0.4mm는 간격 2.16이다
/// (#239 — 두께를 장치 단위로 반올림한 격자). 그래서 사슬의 **시작 자리**(무늬 원점·다시 시작하는
/// 칸)와 함께 사슬마다 원 **개수**·간격도 한글에 맞춘다. 한글은 이웃 세로 변이 없는 가로 변을 NONE
/// 변 폭(0.1mm)의 절반만큼 연장해 원점이 −0.12다 (우리도 #246부터 그렇다). 결정론 글꼴로 조판하므로
/// 기기 독립이다.
final class FixtureTableBorderChainTests: XCTestCase {
    /// 한글 PDF 장치 격자 한 칸 + 연장 차
    static let tolerance: CGFloat = 0.15

    enum Ink { case green, blue }

    struct Mark {
        let ink: Ink
        /// 원·대시·물결 조각 하나의 경계 상자 (표 왼 위 모서리 기준)
        let rect: CGRect
    }

    static func ink(of color: CGColor?) -> Ink? {
        guard let components = color?.components, components.count >= 3 else { return nil }
        let (red, green, blue) = (components[0], components[1], components[2])
        if green > 0.9, red < 0.1, blue < 0.1 {
            return .green
        }
        if blue > 0.9, red < 0.1, green < 0.1 {
            return .blue
        }
        return nil
    }

    /// 쪽의 표 10개 (문서 순) 각각의 초록·파랑 테두리 조각
    static func tables(_ format: String, file: String = #file) async throws -> [[Mark]] {
        let url = FixtureRoot.url(
            from: file, subdirectory: format == "hwpx" ? "HwpxFixtures" : "Fixtures"
        ).appendingPathComponent("table-border-chains").appendingPathComponent("document.\(format)")
        let document = try await HwpDocumentLoader(fontResolver: .testDeterministic).load(from: url)
        expect(document.pages.count) == 1
        let page = try XCTUnwrap(document.pages.first)
        let frames = page.blocks.filter { $0.kind == .table }.map(\.frame)
            .sorted { $0.minY < $1.minY }
        expect(frames.count) == 10
        var paths: [(Ink, CGPath)] = []
        for command in page.paintList.commands {
            if case let .drawPath(path, fill, _, _) = command, let ink = ink(of: fill) {
                paths.append((ink, path))
            }
        }
        return frames.map { frame in
            let zone = frame.insetBy(dx: -4, dy: -4)
            return paths.flatMap { ink, path in
                subpathBoxes(path).filter { zone.contains(CGPoint(x: $0.midX, y: $0.midY)) }.map {
                    Mark(ink: ink, rect: $0.offsetBy(dx: -frame.minX, dy: -frame.minY))
                }
            }
        }
    }

    /// 경로의 부분 경로마다 경계 상자
    static func subpathBoxes(_ path: CGPath) -> [CGRect] {
        var boxes: [CGRect] = []
        var current = CGRect.null
        path.applyWithBlock { element in
            let kind = element.pointee.type
            let count = switch kind {
            case .moveToPoint, .addLineToPoint: 1
            case .addQuadCurveToPoint: 2
            case .addCurveToPoint: 3
            default: 0
            }
            if kind == .moveToPoint, !current.isNull {
                boxes.append(current)
                current = .null
            }
            for index in 0 ..< count {
                current = current.union(CGRect(origin: element.pointee.points[index], size: .zero))
            }
        }
        if !current.isNull {
            boxes.append(current)
        }
        return boxes
    }

    /// 원(가로·세로가 같은 작은 조각) 가운데 가로선 y(또는 세로선 x) 위의 것 — 선 방향 중심 자리
    static func circleCenters(
        _ marks: [Mark], ink: Ink = .green,
        horizontalAt y: CGFloat? = nil, verticalAt x: CGFloat? = nil
    ) -> [CGFloat] {
        let centers = marks.filter {
            $0.ink == ink && abs($0.rect.width - $0.rect.height) < 0.01 && $0.rect.width < 4
        }.compactMap { mark -> CGFloat? in
            if let y, abs(mark.rect.midY - y) < 0.05 {
                return mark.rect.midX
            }
            if let x, abs(mark.rect.midX - x) < 0.05 {
                return mark.rect.midY
            }
            return nil
        }
        return Array(Set(centers.map { ($0 * 1000).rounded() / 1000 })).sorted()
    }

    /// 원 중심 사이 간격 (처음·끝 중심과 개수로) — 이어진 사슬 하나에서만 뜻이 있다
    static func pitch(_ centers: [CGFloat]) -> CGFloat {
        guard let first = centers.first, let last = centers.last, centers.count > 1 else {
            return 0
        }
        return (last - first) / CGFloat(centers.count - 1)
    }

    /// 같은 간격으로 이어진 원 무리의 시작 자리들 — 이웃 원 사이가 간격(가운데값)과 다르면 거기서
    /// 다시 시작한 것이다 (다시 시작하면 앞 무리의 마지막 원과 새 무리의 첫 원이 간격보다 좁거나 넓다)
    static func runStarts(_ centers: [CGFloat]) -> [CGFloat] {
        guard let first = centers.first else { return [] }
        let gaps = zip(centers, centers.dropFirst()).map { $1 - $0 }.sorted()
        guard !gaps.isEmpty else { return [first] }
        let pitch = gaps[gaps.count / 2]
        var starts = [first]
        for (previous, center) in zip(centers, centers.dropFirst())
            where abs(center - previous - pitch) > 0.01
        {
            starts.append(center)
        }
        return starts
    }

    /// 이어지는 사슬 — 칸 경계(22.8·45.6)에서 다시 시작하지 않고 한글의 무늬 원점에서 시작한다
    func testContinuousChainsStartAtHancomsOrigin() async throws {
        let tolerance = Self.tolerance
        for format in ["hwp", "hwpx"] {
            let tables = try await Self.tables(format)
            // A 1×3 위 변 원형 점선 — 한글 원 중심 −0.12 … 63.24 한 간격, 12개 (간격 5.76)
            let plain = Self.circleCenters(tables[0], horizontalAt: 0)
            expect(Self.runStarts(plain)).to(haveCount(1), description: format)
            expect(plain.first).to(beCloseTo(-0.12, within: tolerance), description: format)
            expect(plain.last ?? 0) > 60
            expect(plain).to(haveCount(12), description: format)
            expect(Self.pitch(plain)).to(beCloseTo(5.76, within: 1e-6), description: format)
            // B 같은 표 + 세로 변 파랑 1mm — 원점이 첫 칸 연장 시작 (한글 −1.44)
            let extended = Self.circleCenters(tables[1], horizontalAt: 0)
            expect(Self.runStarts(extended)).to(haveCount(1), description: format)
            expect(extended.first).to(beCloseTo(-1.44, within: tolerance), description: format)
            expect(extended).to(haveCount(13), description: format)
            // E 위 [원, 없음, 원] · 아래 [없음, 원, 없음] — 없는 쪽을 다른 쪽이 이어 한 간격
            let bridged = Self.circleCenters(tables[4], horizontalAt: 15)
            expect(Self.runStarts(bridged)).to(haveCount(1), description: format)
            expect(bridged.last ?? 0) > 60
            expect(bridged).to(haveCount(12), description: format)
            // F 3×1 왼 변 — 세로 사슬은 연장 없이 위 모서리에서 한 간격으로 세 행을 지난다
            let vertical = Self.circleCenters(tables[5], verticalAt: 0)
            expect(Self.runStarts(vertical)).to(haveCount(1), description: format)
            expect(vertical.first).to(beCloseTo(0, within: tolerance), description: format)
            expect(vertical.last ?? 0) > 60
            expect(vertical).to(haveCount(12), description: format)
            // I 병합 칸 — 위 선·안쪽 선 모두 한 간격
            for y: CGFloat in [0, 15] {
                let merged = Self.circleCenters(tables[8], horizontalAt: y)
                expect(Self.runStarts(merged)).to(haveCount(1), description: "\(format) y \(y)")
                expect(merged).to(haveCount(12), description: "\(format) y \(y)")
            }
        }
    }

    /// 다시 시작하는 사슬 — 한글이 다시 시작하는 칸에서만 다시 시작한다
    func testChainsRestartWhereHancomRestartsThem() async throws {
        let tolerance = Self.tolerance
        for format in ["hwp", "hwpx"] {
            let tables = try await Self.tables(format)
            // D 위 행 아래 변 [초록 ×3], 아래 행 위 변 [초록, 파랑, 초록] — 초록은 둘째 칸까지 잇고
            // 셋째 칸에서 다시 시작한다 (한글 45.48), 파랑은 둘째 칸 모서리에서 (22.68)
            let otherSideCenters = Self.circleCenters(tables[3], horizontalAt: 15)
            let otherSide = Self.runStarts(otherSideCenters)
            expect(otherSide).to(haveCount(2), description: format)
            // 한글 초록 8 + 4개, 파랑 4개
            expect(otherSideCenters).to(haveCount(12), description: format)
            expect(otherSide.first).to(beCloseTo(-0.12, within: tolerance), description: format)
            expect(otherSide.last).to(beCloseTo(45.48, within: tolerance), description: format)
            let otherSideBlue = Self.circleCenters(tables[3], ink: .blue, horizontalAt: 15)
            expect(otherSideBlue.first).to(beCloseTo(22.68, within: tolerance), description: format)
            expect(otherSideBlue).to(haveCount(4), description: format)
            // J 가운데 칸만 파랑 — 색이 다르면 다시 시작한다 (한글 초록 −0.12 · 45.48, 파랑 22.68)
            let colorBreakCenters = Self.circleCenters(tables[9], horizontalAt: 0)
            let colorBreak = Self.runStarts(colorBreakCenters)
            expect(colorBreak).to(haveCount(2), description: format)
            expect(colorBreakCenters).to(haveCount(8), description: format)
            expect(colorBreak.last).to(beCloseTo(45.48, within: tolerance), description: format)
            let colorBreakBlue = Self.circleCenters(tables[9], ink: .blue, horizontalAt: 0)
            expect(colorBreakBlue.first)
                .to(beCloseTo(22.68, within: tolerance), description: format)
            expect(colorBreakBlue).to(haveCount(4), description: format)
            // H 물결은 한글도 칸마다 다시 시작한다 — 대각선이 칸 모서리 22.8·45.6에서 시작한다 (이어
            // 그렸다면 반주기 2.955의 배수 20.69·23.64 …라 모서리에서 0.4 안에 시작하는 대각선이 없다;
            // 조각 상자는 획 모서리만큼 앞선다)
            let waveStarts = tables[7].filter { $0.ink == .green }.map(\.rect.minX)
            for corner: CGFloat in [22.8, 45.6] {
                let atCorner = waveStarts.contains { abs($0 - corner) < 0.4 }
                expect(atCorner).to(beTrue(), description: format)
            }
        }
    }

    /// 긴 점선과 격자 — 대시도 사슬 전체로 잇고, 2×2 격자는 가로·세로 선마다 두 칸을 한 무늬로 지난다
    func testDashChainsAndGridLinesContinue() async throws {
        let tolerance = Self.tolerance
        for format in ["hwp", "hwpx"] {
            let tables = try await Self.tables(format)
            // C 긴 점선 + 세로 변 — 한글 대시 [−1.44, 19.32] · [31.92, 52.68] · [65.28, 69.84]: 첫 대시가
            // 원점에서 시작하고 둘째 대시는 둘째 칸(22.8) 모서리가 아니라 한 주기 뒤에서 시작한다
            let dashes = tables[2].filter { $0.ink == .green && $0.rect.width > 4 }
                .map(\.rect).sorted { $0.minX < $1.minX }
            expect(dashes.count).to(equal(3), description: format)
            expect(dashes.first?.minX).to(beCloseTo(-1.44, within: tolerance), description: format)
            expect(dashes.dropFirst().first?.minX ?? 0) > 30
            expect(dashes.last?.maxX).to(beCloseTo(69.84, within: tolerance), description: format)
            // G 2×2 네 변 0.4mm — 가로선 셋은 −t/2(한글 −0.48)에서, 세로선 셋은 위 모서리에서 각각 한
            // 간격(2.16, 한글 22개씩)으로 두 칸을 지난다
            let corners: [CGFloat] = [0, 22.8, 45.6]
            for y in corners {
                // 세로선의 첫 원(칸 모서리 위)은 가로선 위에도 놓이므로 뺀다
                let line = Self.circleCenters(tables[6], horizontalAt: y).filter { center in
                    !corners.contains { abs($0 - center) < 0.05 }
                }
                expect(Self.runStarts(line)).to(haveCount(1), description: "\(format) y \(y)")
                expect(line.first)
                    .to(beCloseTo(-0.48, within: tolerance), description: "\(format) y \(y)")
                expect(line).to(haveCount(22), description: "\(format) y \(y)")
                expect(Self.pitch(line))
                    .to(beCloseTo(2.16, within: 1e-6), description: "\(format) y \(y)")
            }
            for x in corners {
                let line = Self.circleCenters(tables[6], verticalAt: x)
                expect(Self.runStarts(line)).to(haveCount(1), description: "\(format) x \(x)")
                // 세로 사슬은 위·아래 변이 있어도 연장 없이 위 모서리에서 (한글 첫 원 = 모서리)
                expect(line.first)
                    .to(beCloseTo(0, within: tolerance), description: "\(format) x \(x)")
                expect(line.last ?? 0) > 40
                expect(line).to(haveCount(22), description: "\(format) x \(x)")
            }
        }
    }
}
