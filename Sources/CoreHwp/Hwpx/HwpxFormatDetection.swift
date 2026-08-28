import Foundation

/// 파일 선두 바이트로 HWP 계열 컨테이너 포맷을 감지한다.
///
/// `HwpFile`의 public init 3종이 이 판정으로 OLE(HWP 5.0 바이너리)와
/// ZIP(HWPX/OCF) 파이프라인을 가른다. `.unknown`은 기존 OLE 경로로 보내
/// 종전의 `invalidOLEFile` 오류 표면을 그대로 유지한다 — 감지 실패가 새
/// 오류를 만들지 않는다.
enum HwpxFormatDetection {
    enum ContainerFormat {
        /// OLE compound document (`D0 CF 11 E0 A1 B1 1A E1`) — HWP 5.0.
        case ole
        /// ZIP local file header (`PK\u{3}\u{4}`) — HWPX/OCF.
        case zip
        /// 둘 다 아님 — 기존 OLE 경로가 typed error로 거부한다.
        case unknown
    }

    private static let oleSignature = Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])
    private static let zipSignature = Data([0x50, 0x4B, 0x03, 0x04])

    /// 선두 바이트(8바이트면 충분)로 컨테이너 포맷을 판정한다.
    static func sniff(_ prefix: Data) -> ContainerFormat {
        if prefix.starts(with: oleSignature) {
            return .ole
        }
        if prefix.starts(with: zipSignature) {
            return .zip
        }
        return .unknown
    }
}
