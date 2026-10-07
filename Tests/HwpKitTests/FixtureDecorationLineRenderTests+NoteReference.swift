import CoreGraphics
import Foundation
import HwpKit
import HwpKitCore
import HwpKitNative
import Nimble
import XCTest

/// `note-reference-strikethrough` 쌍의 실물 핀 (#256) — 각주·미주 참조 번호(0.75배 글꼴·설정 크기의
/// 0.21배 올림, #204)의 취소선·글자 가운데 밑줄은 **번호가 놓인 글자 모양의 자리**에 그려진다. 위 첨자
/// 글자 모양 안의 번호는 그 첨자의 선 자리다. 번호는 앞뒤 글자와 **따로 된 글자 모양 run**이라 긴 점선
/// 무늬가 번호 시작·번호 뒤 글자 시작에서 다시 시작하고, MS 워드 호환 문서의 취소선 글꼴은 번호 = 번호
/// 자신의 글꼴, 번호 뒤 글자 = 자기 첫 글리프 글꼴이다. 두 포맷이 같은 자리에 그린다.
///
/// 오라클은 한글.app 12.30.0 build 6523의 PDF 내보내기다 (2026-10-06, 벡터 좌표, 쪽 위에서부터 pt). 이
/// 문서는 MS 워드 호환 문서(한글 슬롯 Apple SD 산돌고딕 Neo·라틴 슬롯 Menlo — 결정론 resolver
/// `HwpFontResolver.testDeterministic`과 같은 글꼴)이고 한글이 줄 배치 캐시를 적어 두었으므로 본문 쪽
/// 좌표를 그대로 핀한다. 각주 영역은 MS 워드 호환 각주 내용의 줄 간격이 아직 한글과 달라(우리 첫 내용
/// 줄이 21pt 낮다 — #268) 같은 줄 안의 관계만 핀한다. 문단 6은 쪽 나누기로 2쪽에서 시작한다 —
/// 80pt·160% 줄 간격 문단의 프레임 아래 여분이 1쪽 각주 영역에 닿으면 각주 겹침 가드가 그 여분까지
/// 본문으로 재어 실패한다(#271).
///
/// | 문단 | 표본 | 베이스라인 | 앞 글자 선 | 번호 선 | 뒤 글자 선 |
/// |---|---|---:|---:|---:|---:|
/// | 1 | Menlo 20pt 취소선 + 각주 | 121.32 | 116.28 | 116.28 | 116.28 |
/// | 2 | Menlo 40pt 취소선 + 미주 | 191.88 | 181.68 | 181.68 | 181.68 |
/// | 3 | Menlo 20pt 글자 가운데 밑줄(자홍) + 각주 | 266.64 | 261.60 | 261.60 | 261.60 |
/// | 4 | 40pt 보통 + **위 첨자** `yy` + 각주 + `yy` + 보통 | 337.20 | 312.48 (첨자) | 312.48 | 312.48 (첨자) |
/// | 6 (2쪽) | 80pt `가나K` + 각주 + `AB` | 187.56 | 167.64 (SD) | 167.28 (M) | 167.28 (M) |
/// | 7 (2쪽) | 80pt `AB` + 각주 + `가나` | 387.12 | 366.84 (M) | 366.84 (M) | 367.32 (SD) |
///
/// (SD = 첫 글리프가 Apple SD 산돌고딕 Neo인 run의 MS 워드 취소선 자리, M = Menlo 자리)
///
/// 4번의 보통 글자 선은 327.00이다. 5번(40pt 긴 점선 취소선, 423.96)은 대시 구간으로 핀한다. 선 두께는
/// 번호도 본문과 같다 (20pt 0.84·40pt 1.56·80pt 3.12pt). 각주 1의 내용(Menlo 20pt 취소선, 구역 각주
/// 모양이 위 첨자라 내용 번호도 참조 번호 규칙)도 번호 선 = 내용 선이다 (한글 672.84 — 내용
/// 베이스라인 678.00 위 5.16pt).
///
/// 수정 전에는 번호 선이 번호를 따라 올라갔다 — 1번 113.53(한글 116.28), 2번 176.30(181.68), 4번 번호
/// 304.07(312.48). 2쪽의 네 선은 한글과 0.16pt 안이다 — 우리 베이스라인이 한글보다 약 0.1pt 높은 몫을
/// 품는다 (6번 `가나K` 167.56·번호·`AB` 167.14, 7번 `AB`·번호 366.74·`가나` 367.16). #257 전에는 MS 워드
/// 보통 선 모형(0.273 × `ascent`)이 Apple SD 자리를 한글보다 0.26pt 낮게 그려 그 몫과 상쇄돼 있었다.
///
/// `extension`에 두는 이유는 `FixtureDecorationLineRenderTests` 본문이
/// `type_body_length` 경고선에 닿아 있어서다.
extension FixtureDecorationLineRenderTests {
    private static let noteReference = "note-reference-strikethrough"
    /// 이 픽스처의 쪽 크기 (A4, `hp:pagePr` 59528 × 84186 HWPUNIT)
    private static let noteReferencePageSize = CGSize(width: 595.28, height: 841.86)

    private enum NoteLineColor {
        case red, magenta

        /// 흰 바탕에 칠한 순색 선의 커버리지(0…1) — 빨강은 G·B, 자홍은 G가 빠진 몫이다. 무채색
        /// 글리프 잉크·안티앨리어싱은 0이다.
        func coverage(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Double {
            let (red, green, blue) = (Double(red), Double(green), Double(blue))
            switch self {
            case .red: return max(0, red - max(green, blue)) / 255
            case .magenta: return max(0, min(red, blue) - green) / 255
            }
        }
    }

    /// 한 선 조각 — 쪽 좌표 x 구간(글자 경계에서 2pt 안쪽)과 한글 선 중심
    private struct NoteLinePiece {
        let label: String
        let x: ClosedRange<CGFloat>
        let hancom: CGFloat
    }

    /// `x` 구간·`near` ± `reach`(pt) 행에서 잰 선 중심 — 선 색 커버리지 가중 중심을 실제 세로 배율로
    /// pt에 옮긴다 (`+MsWordScript`의 `coverageCenter`와 같은 방식, 가로 구간만 더했다).
    private static func noteLineCenter(
        _ raster: Raster, x: ClosedRange<CGFloat>, near: CGFloat, color: NoteLineColor,
        reach: CGFloat = 2
    ) -> CGFloat? {
        let perPointY = CGFloat(raster.pixelHeight) / noteReferencePageSize.height
        let perPointX = CGFloat(raster.pixelWidth) / noteReferencePageSize.width
        let top = max(0, Int(((near - reach) * perPointY).rounded(.down)))
        let bottom = min(raster.pixelHeight - 1, Int(((near + reach) * perPointY).rounded(.up)))
        let left = max(0, Int((x.lowerBound * perPointX).rounded(.down)))
        let right = min(raster.pixelWidth - 1, Int((x.upperBound * perPointX).rounded(.up)))
        guard top <= bottom, left <= right else { return nil }
        var weighted = 0.0
        var total = 0.0
        for row in top ... bottom {
            for column in left ... right {
                let offset = row * raster.bytesPerRow + column * 4
                let weight = color.coverage(
                    raster.data[offset], raster.data[offset + 1], raster.data[offset + 2]
                )
                guard weight > 0.02 else { continue }
                weighted += (Double(row) + 0.5) * weight
                total += weight
            }
        }
        guard total > 0 else { return nil }
        return CGFloat(weighted / total) / perPointY
    }

    /// `row`(pt) 행에서 빨강 커버리지가 절반을 넘는 열이 이어진 구간들 (pt, 쪽 좌표) — 대시 무늬.
    private static func redRuns(
        _ raster: Raster, row: CGFloat, x: ClosedRange<CGFloat>
    ) -> [ClosedRange<CGFloat>] {
        let perPointY = CGFloat(raster.pixelHeight) / noteReferencePageSize.height
        let perPointX = CGFloat(raster.pixelWidth) / noteReferencePageSize.width
        let y = Int(row * perPointY)
        var runs: [ClosedRange<CGFloat>] = []
        var start: Int?
        let left = Int(x.lowerBound * perPointX)
        let right = Int(x.upperBound * perPointX)
        for column in left ... right {
            let offset = y * raster.bytesPerRow + column * 4
            let red = NoteLineColor.red.coverage(
                raster.data[offset], raster.data[offset + 1], raster.data[offset + 2]
            ) > 0.5
            if red, start == nil {
                start = column
            } else if !red, let begin = start {
                runs.append(CGFloat(begin) / perPointX ... CGFloat(column) / perPointX)
                start = nil
            }
        }
        if let begin = start {
            runs.append(CGFloat(begin) / perPointX ... CGFloat(right + 1) / perPointX)
        }
        return runs
    }

    private static func pieces(_ label: String, _ entries: [(ClosedRange<CGFloat>, CGFloat)])
        -> [NoteLinePiece]
    {
        let names = ["앞 글자", "번호", "뒤 글자"]
        return entries.enumerated().map { index, entry in
            NoteLinePiece(
                label: "\(label) \(index < names.count ? names[index] : "\(index)")",
                x: entry.0, hancom: entry.1
            )
        }
    }

    /// 1쪽 본문 선 조각 (빨강) — 문단 1·2·4
    private static let noteReferenceRedPieces: [NoteLinePiece] =
        pieces("1번", [(87 ... 107, 116.28), (111 ... 125, 116.28), (129 ... 149, 116.28)])
            + pieces("2번", [(87 ... 131, 181.68), (135 ... 167, 181.68), (171 ... 215, 181.68)])
            + [
                NoteLinePiece(label: "4번 보통", x: 87 ... 131, hancom: 327.00),
                NoteLinePiece(label: "4번 위 첨자", x: 135 ... 162, hancom: 312.48),
                NoteLinePiece(label: "4번 번호", x: 166 ... 185, hancom: 312.48),
                NoteLinePiece(label: "4번 뒤 위 첨자", x: 189 ... 216, hancom: 312.48),
                NoteLinePiece(label: "4번 뒤 보통", x: 220 ... 264, hancom: 327.00),
            ]

    /// 본문 선이 한글 쪽 좌표에 있고, 번호 선이 같은 줄 이웃 선과 같은 행이다. 두 포맷이 같은 행이다.
    /// 오차 예산: 쪽 좌표 0.2 (`+MsWordScript`와 같다 — 한글 PDF 장치 좌표 0.12pt; 이 1쪽 선은 모두
    /// Menlo이고 실측 최대 0.10pt, 2쪽은 `testNoteReferenceSplitsTheMsWordStrikethroughFont`), 같은 줄
    /// 관계 0.05 (같은 글자 모양의 선은 우리 렌더에서 같은 산식).
    func testNoteReferenceStrikethroughsMatchHancomCoordinatesInBothFormats() async throws {
        var centers: [[CGFloat]] = []
        for hwpx in [false, true] {
            let format = hwpx ? "HWPX" : "HWP"
            let raster = try await Self.raster(Self.noteReference, hwpx: hwpx)
            var measured: [CGFloat] = []
            for piece in Self.noteReferenceRedPieces {
                let center = try XCTUnwrap(
                    Self.noteLineCenter(raster, x: piece.x, near: piece.hancom, color: .red),
                    "\(format) \(piece.label): 선을 못 찾았다"
                )
                expect(center).to(
                    beCloseTo(piece.hancom, within: 0.2), description: "\(format) \(piece.label)"
                )
                measured.append(center)
            }
            for piece in Self.pieces(
                "3번 가운데 밑줄",
                [(87 ... 107, 261.60), (111 ... 125, 261.60), (129 ... 149, 261.60)]
            ) {
                let center = try XCTUnwrap(
                    Self.noteLineCenter(raster, x: piece.x, near: piece.hancom, color: .magenta),
                    "\(format) \(piece.label): 선을 못 찾았다"
                )
                expect(center).to(
                    beCloseTo(piece.hancom, within: 0.2), description: "\(format) \(piece.label)"
                )
                measured.append(center)
            }
            // 같은 줄 관계 — 번호 선 = 앞 글자 선(1·2·3번), 번호 선 = 둘러싼 위 첨자 선(4번).
            for (number, neighbor, label) in [
                (1, 0, "1번"), (1, 2, "1번 뒤"), (4, 3, "2번"), (12, 11, "3번"), (8, 7, "4번"),
                (8, 9, "4번 뒤"),
            ] {
                expect(measured[number]).to(
                    beCloseTo(measured[neighbor], within: 0.05),
                    description: "\(format) \(label): 번호 선 = 이웃 선"
                )
            }
            centers.append(measured)
        }
        for index in centers[0].indices {
            expect(centers[0][index]).to(
                beCloseTo(centers[1][index], within: 0.01),
                description: "선 \(index): HWP와 HWPX가 같은 자리"
            )
        }
    }

    /// MS 워드 호환 문서의 취소선 글꼴은 번호에서 끊긴다 (2쪽) — 6번 `가나K`(첫 글리프 Apple SD)의 선과
    /// 번호·`AB`(Menlo)의 선이 다른 행이고 번호 = `AB`, 7번 번호 = `AB`(Menlo)이고 번호 뒤 `가나`는 다시
    /// Apple SD 행이다. 한글: Apple SD 자리가 Menlo 자리보다 0.36·0.48pt 낮다 — 우리는 두 글꼴의 줄 상자
    /// 베이스라인 높이 차 × 0.23 × 80pt = 0.42pt다 (#257; 종전 `ascent` × 0.273 모형은 0.62pt). 수정
    /// 전에는 같은 글자 모양 id라 줄 전체가 첫 글리프 글꼴 하나여서 6번 `AB`가 `가나K` 행(167.77)에,
    /// 7번 `가나`가 Menlo 행에 붙었다 — 6번 번호는 그 글꼴의 첨자 자리(올림 16.8 + 보통 높이의 0.696배,
    /// 156.95)였다. 번호 신원만 없애면 6번 번호·`AB`가 `가나K` 행에 붙는다.
    func testNoteReferenceSplitsTheMsWordStrikethroughFont() async throws {
        for hwpx in [false, true] {
            let format = hwpx ? "HWPX" : "HWP"
            let raster = try await Self.raster(Self.noteReference, hwpx: hwpx, pageIndex: 1)
            func centers(_ label: String, _ entries: [(ClosedRange<CGFloat>, CGFloat)]) throws
                -> [CGFloat]
            {
                try Self.pieces(label, entries).map { piece in
                    let center = try XCTUnwrap(
                        Self.noteLineCenter(raster, x: piece.x, near: piece.hancom, color: .red),
                        "\(format) \(piece.label)"
                    )
                    expect(center).to(
                        beCloseTo(piece.hancom, within: 0.2),
                        description: "\(format) \(piece.label)"
                    )
                    return center
                }
            }
            let sixth = try centers(
                "6번", [(90 ... 265, 167.64), (275 ... 340, 167.28), (348 ... 436, 167.28)]
            )
            expect(sixth[1]).to(beCloseTo(sixth[2], within: 0.05), description: "\(format) 6번")
            expect(sixth[0] - sixth[1]).to(
                beGreaterThan(0.3), description: "\(format) 6번: Apple SD 행이 Menlo 행보다 아래"
            )
            // 행 간격 = 두 글꼴의 베이스라인 높이 차 × 0.23 × 80pt (#257: Menlo 1.1028 − Apple SD
            // 1.08 → 0.42pt; 한글 0.36·0.48pt는 그 값이 장치 단위로 반올림된 두 표본, 종전 모형 0.62pt)
            expect(sixth[0] - sixth[1]).to(
                beCloseTo(0.42, within: 0.08), description: "\(format) 6번 행 간격"
            )
            let seventh = try centers(
                "7번", [(88 ... 178, 366.84), (185 ... 250, 366.84), (257 ... 389, 367.32)]
            )
            expect(seventh[1]).to(beCloseTo(seventh[0], within: 0.05), description: "\(format) 7번")
            expect(seventh[2] - seventh[1]).to(
                beGreaterThan(0.3), description: "\(format) 7번: 번호 뒤 `가나`가 Apple SD 행"
            )
            expect(seventh[2] - seventh[1]).to(
                beCloseTo(0.42, within: 0.08), description: "\(format) 7번 행 간격"
            )
        }
    }

    /// 긴 점선 취소선(5번, 40pt — 대시 22.92·틈 6.96pt)의 무늬가 번호 시작과 번호 뒤 글자 시작에서 다시
    /// 시작한다. 한글 대시 구간: 85.08–108.00 · 114.96–137.88 · 144.84–167.76 · 174.72–197.64 ·
    /// 204.60–228.36(본문 마지막 대시가 번호 시작 205.44에서 끊기고 번호의 첫 대시가 이어 붙는다) ·
    /// 235.32–264.48(번호의 둘째 대시가 번호 끝 241.68에서 끊기고 뒤 글자의 첫 대시가 이어 붙는다) ·
    /// 271.44–294.36 · …. 무늬가 번호를 건너 이어지면 204.60–227.52 · 234.48–257.40 · 264.36–…이 되어
    /// 257.4–264.4에 틈이, 264.5–271.4에 대시가 생긴다.
    func testNoteReferenceRestartsTheLongDashPattern() async throws {
        let hancom: [ClosedRange<CGFloat>] = [
            204.60 ... 228.36, 235.32 ... 264.48, 271.44 ... 294.36,
        ]
        for hwpx in [false, true] {
            let format = hwpx ? "HWPX" : "HWP"
            let raster = try await Self.raster(Self.noteReference, hwpx: hwpx)
            let runs = Self.redRuns(raster, row: 423.96, x: 200 ... 296)
            expect(runs.count).to(equal(hancom.count), description: "\(format) 대시 수 \(runs)")
            for (run, expected) in zip(runs, hancom) {
                expect(run.lowerBound).to(
                    beCloseTo(expected.lowerBound, within: 0.3), description: "\(format) \(runs)"
                )
                expect(run.upperBound).to(
                    beCloseTo(expected.upperBound, within: 0.3), description: "\(format) \(runs)"
                )
            }
        }
    }

    /// 각주 내용 첫머리의 위 첨자 번호(구역 각주 모양이 위 첨자)에 걸린 취소선도 내용 글자의 선과 같은
    /// 행이다 — 한글 672.84 = 내용 베이스라인 678.00 위 5.16pt. 수정 전에는 번호 선이 2.66pt 높았다. 각주
    /// 영역의 쪽 좌표는 핀하지 않는다(머리말 참조) — 각주 영역 전체를 창으로 잡고 가로 구간으로 가른다.
    func testFootnoteBodyNumberStrikethroughStaysOnTheContentRow() async throws {
        for hwpx in [false, true] {
            let format = hwpx ? "HWPX" : "HWP"
            let raster = try await Self.raster(Self.noteReference, hwpx: hwpx)
            let number = try XCTUnwrap(
                Self.noteLineCenter(raster, x: 87 ... 101, near: 685, color: .red, reach: 40),
                "\(format) 각주 내용 번호 선"
            )
            let content = try XCTUnwrap(
                Self.noteLineCenter(raster, x: 106 ... 135, near: 685, color: .red, reach: 40),
                "\(format) 각주 내용 선"
            )
            expect(number).to(beCloseTo(content, within: 0.05), description: format)
        }
    }
}
