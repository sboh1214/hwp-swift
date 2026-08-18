import CoreGraphics
import CoreHwp
import Foundation
import HwpKitCore
import HwpKitNative
import ImageIO

/// 픽스처 문서의 1페이지를 비트맵으로 렌더하고, 문서에 내장된 한컴 렌더
/// 미리보기(PrvImage)와 그리드 잉크 밀도로 비교하는 테스트 지원 유틸.
///
/// 픽셀 동일성이 아니라 잉크 분포(레이아웃 구조·간격·배치)의 동등성을 잰다:
/// 두 이미지를 같은 크기 그레이스케일로 리샘플한 뒤 N×M 셀 그리드의 평균
/// 잉크(1 − 밝기)를 벡터로 만들어 평균 절대 오차(MAE)를 계산한다.
/// 폰트 대체로 인한 글리프 모양 차이에는 둔감하고, 문단 시작 위치·문단 간격·
/// 단 배분 차이에는 민감하다.
enum FixturePreview {
    enum RenderError: Error {
        case contextCreationFailed
        case imageCreationFailed
        case previewDecodeFailed
        case pageMissing
    }

    // MARK: - 문서 → 1페이지 렌더

    /// CoreHwp.HwpFile에서 첫 페이지만 lazy 페이지네이션한다
    /// (legacy 1,030쪽 문서도 1페이지 비용만 지불).
    static func firstPage(
        of file: CoreHwp.HwpFile,
        fontResolver: HwpFontResolver = HwpFontResolver()
    ) async throws -> (page: HwpPage, imageStore: HwpImageStore) {
        let index = HwpIndex(from: file)
        let imageStore = HwpImageStore(from: file)
        let paginator = HwpPaginator(
            sections: file.displaySectionArray,
            index: index,
            fontResolver: fontResolver,
            imageStore: imageStore
        )
        guard let page = try await paginator.page(at: 0) else {
            throw RenderError.pageMissing
        }
        return (page, imageStore)
    }

    /// HwpPage를 지정한 픽셀 크기의 CGImage로 렌더한다.
    ///
    /// **프로덕션 렌더러(`HwpPageBitmapRenderer.render`)에 그대로 위임한다** —
    /// 그래야 렌더 가드(골든·해시·fidelity)가 테스트 전용 사본이 아니라 실제로
    /// 출하되는 코드를 검사한다. 하네스에만 남는 것은 두 가지다:
    ///
    /// - `zoom`: 일부 저장본의 PrvImage가 확대·크롭 렌더라 그 대조에만 쓴다.
    ///   승격본의 `sourceRect`(캔버스를 채울 페이지 영역)로 표현된다 — zoom배
    ///   확대는 좌상단 1/zoom 영역을 채우는 것과 같다.
    /// - `.fail` 정책: 미확정 변형이 남으면 던진다. 회색 로딩 사각형이 커밋된
    ///   기준선에 **정답으로 기록되는** 것을 막아야 하는 쪽은 하네스뿐이고,
    ///   축소판은 플레이스홀더가 정답이다.
    static func renderImage(
        page: HwpPage,
        imageStore: HwpImageStore,
        pixelWidth: Int,
        pixelHeight: Int,
        zoom: CGFloat = 1
    ) async throws -> CGImage {
        try await HwpPageBitmapRenderer.render(
            page: page,
            imageStore: imageStore,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            sourceRect: zoom == 1 ? nil : CGRect(
                origin: .zero,
                size: CGSize(
                    width: page.size.width / zoom,
                    height: page.size.height / zoom
                )
            ),
            unresolvedImages: .fail
        )
    }

    // MARK: - PrvImage 디코딩

    /// PrvImage 스트림(BMP/GIF/PNG/JPEG)을 CGImage로 디코딩한다.
    static func decodePreview(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw RenderError.previewDecodeFailed
        }
        return image
    }

    // MARK: - 잉크 밀도 그리드 비교

    /// 이미지를 width×height 그레이스케일로 리샘플한 뒤 columns×rows 셀별
    /// 평균 잉크(0 = 백지, 1 = 전부 검정)를 계산한다.
    static func inkGrid(
        of image: CGImage,
        width: Int,
        height: Int,
        columns: Int,
        rows: Int
    ) throws -> [Double] {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw RenderError.contextCreationFailed
        }
        // GIF 팔레트/알파를 흰 바탕으로 합성한다
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        guard let raw = context.data else {
            throw RenderError.imageCreationFailed
        }
        let pixels = raw.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * height)
        var sums = [Double](repeating: 0, count: columns * rows)
        var counts = [Int](repeating: 0, count: columns * rows)
        for y in 0 ..< height {
            let cellRow = min(rows - 1, y * rows / height)
            for x in 0 ..< width {
                let cellColumn = min(columns - 1, x * columns / width)
                let luma = pixels[y * context.bytesPerRow + x]
                let cell = cellRow * columns + cellColumn
                sums[cell] += 1.0 - Double(luma) / 255.0
                counts[cell] += 1
            }
        }
        return zip(sums, counts).map { sum, count in count > 0 ? sum / Double(count) : 0 }
    }

    /// 두 잉크 그리드의 평균 절대 오차.
    static func meanAbsoluteError(_ lhs: [Double], _ rhs: [Double]) -> Double {
        precondition(lhs.count == rhs.count, "grid size mismatch")
        guard !lhs.isEmpty else { return 0 }
        let total = zip(lhs, rhs).reduce(0.0) { $0 + abs($1.0 - $1.1) }
        return total / Double(lhs.count)
    }

    /// 강도 정합 MAE: reference ≈ s × rendered가 되는 최소제곱 스칼라 s를 찾아
    /// 전역 잉크 강도 차 (폰트 대체/안티앨리어싱 두께 — noori 실측 최대 2.1배)를
    /// 제거한 뒤 MAE를 계산한다. s는 [1/3, 3]으로 클램프해 콘텐츠 누락을
    /// 강도 보상으로 가리지 못하게 한다.
    static func scaleMatchedError(
        reference: [Double],
        rendered: [Double]
    ) -> (mae: Double, scale: Double) {
        precondition(reference.count == rendered.count, "grid size mismatch")
        let denominator = rendered.reduce(0.0) { $0 + $1 * $1 }
        var scale = 1.0
        if denominator > 1e-9 {
            let numerator = zip(reference, rendered).reduce(0.0) { $0 + $1.0 * $1.1 }
            scale = min(3.0, max(1.0 / 3.0, numerator / denominator))
        }
        let mae = meanAbsoluteError(reference, rendered.map { $0 * scale })
        return (mae, scale)
    }

    /// 렌더와 PrvImage를 같은 그리드로 비교한 결과.
    struct Measurement {
        let previewWidth: Int
        let previewHeight: Int
        let columns: Int
        let rows: Int
        /// 강도 정합 MAE (테스트 임계 대상)
        let mae: Double
        /// 정합 전 절대 MAE (진단용)
        let rawMae: Double
        /// 적용된 강도 스칼라 (진단용)
        let inkScale: Double
    }

    /// 픽스처 파일의 1페이지 렌더 vs PrvImage 잉크 밀도 MAE를 계산한다.
    /// 저해상(폭 400px 미만) 미리보기는 셀이 최소 30px을 갖도록 그리드를
    /// 거칠게 잡는다 (6×8) — 고해상은 12×16.
    ///
    /// 저해상 미리보기는 한컴이 큰 렌더를 축소한 것이라 안티앨리어싱 잉크가
    /// 두껍다 — 같은 조건이 되도록 우리도 724px급으로 렌더한 뒤 미리보기
    /// 크기로 축소해 비교한다 (inkGrid의 리샘플 경로).
    static func measure(
        file: CoreHwp.HwpFile,
        fontResolver: HwpFontResolver = HwpFontResolver(),
        previewZoom: CGFloat = 1
    ) async throws -> Measurement {
        let preview = try decodePreview(file.previewImage.image)
        let (page, imageStore) = try await firstPage(of: file, fontResolver: fontResolver)
        let renderScale = max(1, 724 / preview.width)
        let rendered = try await renderImage(
            page: page,
            imageStore: imageStore,
            pixelWidth: preview.width * renderScale,
            pixelHeight: preview.height * renderScale,
            zoom: previewZoom
        )
        let highResolution = preview.width >= 400
        let columns = highResolution ? 12 : 6
        let rows = highResolution ? 16 : 8
        let renderedGrid = try inkGrid(
            of: rendered,
            width: preview.width,
            height: preview.height,
            columns: columns,
            rows: rows
        )
        let previewGrid = try inkGrid(
            of: preview,
            width: preview.width,
            height: preview.height,
            columns: columns,
            rows: rows
        )
        let matched = scaleMatchedError(reference: previewGrid, rendered: renderedGrid)
        return Measurement(
            previewWidth: preview.width,
            previewHeight: preview.height,
            columns: columns,
            rows: rows,
            mae: matched.mae,
            rawMae: meanAbsoluteError(previewGrid, renderedGrid),
            inkScale: matched.scale
        )
    }
}
