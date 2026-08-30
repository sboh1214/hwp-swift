import Foundation

/// `Preview/PrvText.txt`·`Preview/PrvImage.png`를 HWP5 미리보기 모델로 옮긴다.
///
/// HWP5의 `PrvText`는 UTF-16LE stream이지만 HWPX의 `PrvText.txt`는 **UTF-8**
/// 텍스트다 (번들 템플릿 실측 — `Normal.hwtx`는 ASCII CRLF, `05_Report.hwtx`는
/// UTF-8 한글). `HwpPreviewText`가 UTF-16LE payload를 계약으로 삼으므로
/// 디코드 후 재인코딩해 넣는다. BOM 분기는 내장 차트 XML과 같은 규칙을
/// 재사용한다 (`HwpEmbeddedChart.decodeXMLString`).
enum HwpxPreviewMapper {
    /// 미리보기는 optional stream이다 — 부재·비텍스트 payload는 HWP5의
    /// 부재 기본값과 같은 `HwpPreviewText()`로 접는다 (본문 파싱과 무관한
    /// 참고 표면이라 문서 전체를 실패시키지 않는다).
    static func previewText(
        from data: Data?, options: HwpLoadOptions = .default
    ) -> HwpPreviewText {
        guard let data, !data.isEmpty,
              let text = HwpEmbeddedChart.decodeXMLString(data)
        else {
            return HwpPreviewText()
        }
        var payload = Data(capacity: text.utf16.count * 2)
        for unit in text.utf16 {
            payload.append(UInt8(unit & 0xFF))
            payload.append(UInt8(unit >> 8))
        }
        do {
            // 합성 payload도 바이너리 경로와 같은 `preservedPayload` 게이트를
            // 지나야 `.viewer`의 상주 메모리 절감이 유지된다 — reader init에
            // 위임해 게이트가 두 포맷에서 같은 지점(모델)에 남는다. text는
            // 바이너리 경로처럼 게이트와 무관하게 보존된다.
            var reader = DataReader(payload, options: options)
            return try HwpPreviewText(&reader)
        } catch {
            // 도달 불능에 가깝다 — payload는 유효한 String의 UTF-16 재인코딩
            // 이라 짝수 길이·유효 스칼라가 보장된다. 방어적으로 부재 기본값과
            // 같게 접는다 (optional stream이라 문서 실패 사유가 아니다).
            return HwpPreviewText()
        }
    }

    static func previewImage(
        from data: Data?, options: HwpLoadOptions = .default
    ) -> HwpPreviewImage {
        guard let data, !data.isEmpty else {
            return HwpPreviewImage()
        }
        do {
            // previewText와 같은 게이트 위임 — 바이너리 경로처럼 format은
            // 전체 payload에서 판정하고 image/rawPayload만 비운다.
            var reader = DataReader(data, options: options)
            return try HwpPreviewImage(&reader)
        } catch {
            // 도달 불능에 가깝다 — readToEnd는 새 reader에서 실패하지 않는다.
            // 방어적으로 부재 기본값과 같게 접는다 (optional stream).
            return HwpPreviewImage()
        }
    }
}
