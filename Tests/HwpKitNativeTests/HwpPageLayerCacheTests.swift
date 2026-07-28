import CoreGraphics
import CoreText
import Foundation
import HwpKitCore
@testable import HwpKitNative
import Nimble
import XCTest

private func makeBitmapContext(width: Int = 200, height: Int = 120) -> CGContext? {
    CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
}

private func imageBytes(in image: CGImage) -> [UInt8] {
    guard let data = image.dataProvider?.data,
          let bytes = CFDataGetBytePtr(data)
    else { return [] }
    return Array(UnsafeBufferPointer(start: bytes, count: CFDataGetLength(data)))
}

private func makeText(_ string: String) -> NSAttributedString {
    NSAttributedString(
        string: string,
        attributes: [
            .font: CTFontCreateWithName("Helvetica" as CFString, 14, nil),
            .foregroundColor: CGColor(gray: 0, alpha: 1),
        ]
    )
}

private func makeTextLayer(_ commands: [HwpPaintCommand]) -> HwpPageLayer {
    let layer = HwpPageLayer()
    layer.bounds = CGRect(x: 0, y: 0, width: 200, height: 120)
    layer.pageHeight = 120
    layer.paintList = HwpPaintList(commands: commands)
    return layer
}

private func drawnBytes(_ layer: HwpPageLayer) throws -> [UInt8] {
    let context = try XCTUnwrap(makeBitmapContext())
    layer.draw(in: context)
    return imageBytes(in: try XCTUnwrap(context.makeImage()))
}

/// `HwpPageLayer`의 줄 배치 캐시 (#70) — 재드로 시 재조판이 사라지는지, 그리고
/// 캐시가 렌더를 바꾸지 않는지. 기존 `HwpPageLayerTests`는 전부 draw 1회라
/// 콜드 경로만 타므로 캐시 버그를 하나도 잡지 못한다.
final class HwpPageLayerCacheTests: XCTestCase {
    /// 같은 paintList로 두 번 그리면 2회째 조판은 0회이고 픽셀은 바이트 동일하다.
    /// (핀치 줌 종료·이미지 디코딩 완료 재드로가 정확히 이 경로다.)
    func testRepeatedDrawReusesCachedLineLayout() throws {
        let layer = makeTextLayer([
            .drawText(
                attributedString: makeText("재조판 캐시 검증용 문장입니다"),
                origin: CGPoint(x: 8, y: 8),
                lineWidth: 180
            ),
        ])

        let first = try drawnBytes(layer)
        expect(layer.typesetCount) == 1
        expect(layer.cachedDrawnLineEntryCount) == 1

        let second = try drawnBytes(layer)
        expect(layer.typesetCount) == 1 // 2회째는 재조판 없음
        expect(second) == first
    }

    /// contentsScale·bounds 변경은 줄 배치의 입력이 아니므로 캐시를 무효화하지
    /// 않는다 — 줌 종료 재드로에서 재조판이 0이 되는 지점.
    func testContentsScaleChangeDoesNotInvalidateCache() throws {
        let layer = makeTextLayer([
            .drawText(
                attributedString: makeText("줌 종료 재드로"),
                origin: CGPoint(x: 8, y: 8),
                lineWidth: 180
            ),
        ])

        _ = try drawnBytes(layer)
        expect(layer.typesetCount) == 1

        layer.contentsScale = 3
        _ = try drawnBytes(layer)
        expect(layer.typesetCount) == 1
    }

    /// 플레이스홀더는 매 draw마다 새 NSAttributedString을 만든다 — 캐시에 들어가면
    /// 엔트리가 무한 증식하고, 해제된 주소가 재사용되면 오조판까지 난다.
    /// 커맨드 인덱스 키라 캐시에 닿을 통로 자체가 없어야 한다.
    func testPlaceholderDrawsBypassCache() throws {
        let layer = makeTextLayer([
            .drawImageReference(
                binItemId: 1,
                rect: CGRect(x: 0, y: 0, width: 100, height: 100)
            ),
        ])

        for _ in 0 ..< 50 {
            _ = try drawnBytes(layer)
        }

        expect(layer.cachedDrawnLineEntryCount) == 0
        expect(layer.typesetCount) == 50
    }

    /// 같은 rect·다른 텍스트의 플레이스홀더가 서로 오염되지 않는다.
    /// (NSAttributedString 신원을 키로 썼다면 주소 재사용으로 깨질 수 있던 지점.)
    func testDistinctPlaceholderTextsInSameRectRenderDistinctly() throws {
        let rect = CGRect(x: 0, y: 0, width: 120, height: 40)
        func bytes(_ texts: [String]) throws -> [UInt8] {
            try drawnBytes(makeTextLayer(
                texts.map { .drawPlaceholder(rect: rect, text: $0) }
            ))
        }

        // 뒤 명령이 같은 rect를 덮으므로 결과는 마지막 텍스트만 그린 것과 같다.
        expect(try bytes(["AAAA", "MMMM"])) == (try bytes(["MMMM"]))
        // 두 텍스트가 실제로 다르게 그려지는지 (위 단언이 공허하지 않은지) 확인
        expect(try bytes(["MMMM"])).toNot(equal(try bytes(["AAAA"])))
    }

    /// paintList 재대입은 didSet에서 캐시를 전량 비운다.
    func testPaintListReassignmentInvalidatesCache() throws {
        let layer = makeTextLayer([
            .drawText(
                attributedString: makeText("이전 문단"),
                origin: CGPoint(x: 8, y: 8),
                lineWidth: 180
            ),
        ])
        _ = try drawnBytes(layer)
        expect(layer.cachedDrawnLineEntryCount) == 1

        layer.paintList = HwpPaintList(commands: [
            .drawText(
                attributedString: makeText("교체된 문단"),
                origin: CGPoint(x: 8, y: 8),
                lineWidth: 180
            ),
        ])
        expect(layer.cachedDrawnLineEntryCount) == 0

        // 새 레이어로 교체본만 그린 결과와 픽셀 동일 — 스테일 배치가 남지 않는다
        let fresh = makeTextLayer([
            .drawText(
                attributedString: makeText("교체된 문단"),
                origin: CGPoint(x: 8, y: 8),
                lineWidth: 180
            ),
        ])
        expect(try drawnBytes(layer)) == (try drawnBytes(fresh))
    }

    /// CA 사본 (`init(layer:)`)은 캐시를 물려받지 않는다. 그 대입은 super.init
    /// 이전이라 didSet이 발화하지 않으므로, 캐시를 복사하면 무효화 계약이 깨진다.
    func testLayerCopyStartsWithEmptyCache() throws {
        let layer = makeTextLayer([
            .drawText(
                attributedString: makeText("사본 검증"),
                origin: CGPoint(x: 8, y: 8),
                lineWidth: 180
            ),
        ])
        let original = try drawnBytes(layer)
        expect(layer.cachedDrawnLineEntryCount) == 1

        let copy = HwpPageLayer(layer: layer)
        copy.bounds = layer.bounds
        expect(copy.cachedDrawnLineEntryCount) == 0
        expect(copy.typesetCount) == 0
        expect(try drawnBytes(copy)) == original
    }

    /// 줄 예산을 넘기면 축출이 아니라 **삽입 중단**이다 — draw가 커맨드를 항상
    /// 같은 순서로 훑으므로 FIFO 축출은 히트율 0%가 된다. 예산 밖 명령은 현행대로
    /// 매번 재조판하되 렌더는 동일해야 한다.
    func testCachedLineBudgetStopsInsertingWithoutEvicting() throws {
        func makeCommands() -> [HwpPaintCommand] {
            (0 ..< 3).map { index in
                .drawText(
                    attributedString: makeText("예산 \(index)"),
                    origin: CGPoint(x: 8, y: 8 + CGFloat(index) * 24),
                    lineWidth: 180
                )
            }
        }

        let limited = HwpPageLayer()
        limited.bounds = CGRect(x: 0, y: 0, width: 200, height: 120)
        limited.pageHeight = 120
        limited.cachedLineBudget = 1 // 명령당 1줄이라 첫 명령만 들어간다
        limited.paintList = HwpPaintList(commands: makeCommands())

        let first = try drawnBytes(limited)
        expect(limited.typesetCount) == 3
        expect(limited.cachedDrawnLineEntryCount) == 1

        let second = try drawnBytes(limited)
        expect(limited.typesetCount) == 5 // 첫 명령만 히트, 나머지 2개는 재조판
        expect(limited.cachedDrawnLineEntryCount) == 1 // 축출 없음
        expect(second) == first

        // 예산이 넉넉한 레이어와 렌더가 동일하다
        expect(second) == (try drawnBytes(makeTextLayer(makeCommands())))
    }
}
