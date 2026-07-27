import Foundation

/// 문서 로드 옵션. 백그라운드 파싱의 @Sendable 클로저에 캡처되므로 명시
/// Sendable — public 비-frozen 구조체는 모듈 밖 추론이 없다 (R39 #1).
public struct HwpLoadOptions: Sendable {
    /// HWP stream을 읽을 때 허용할 최대 byte 수.
    public var readLimits: HwpReadLimits

    /// 파싱 모델의 rawPayload/rawTrailing 원본 보존 여부. 기본 true.
    /// false(뷰어)면 보존용 슬라이스를 비워 압축 해제 스트림 버퍼가
    /// 파싱 후 해제되게 한다. 파싱된 typed 필드는 양 모드 동일.
    public var preserveRawPayload: Bool

    public init(readLimits: HwpReadLimits = .default, preserveRawPayload: Bool = true) {
        self.readLimits = readLimits
        self.preserveRawPayload = preserveRawPayload
    }

    /// 기본 옵션 — 원본 payload를 전부 보존한다 (기존 동작).
    public static let `default` = HwpLoadOptions()

    /// 뷰어 옵션 — 보존용 원본 슬라이스를 비워 상주 메모리를 줄인다.
    public static let viewer = HwpLoadOptions(preserveRawPayload: false)
}

extension HwpLoadOptions {
    /// 보존 전용 슬라이스 게이트: off면 비운다.
    /// 파싱/렌더 로직이 다시 읽지 않는 순수 보존 필드에만 쓴다.
    func preservedPayload(_ data: Data) -> Data {
        preserveRawPayload ? data : Data()
    }

    /// optional 보존 슬라이스 게이트 — nil은 그대로, 값은 위 규칙으로 비운다.
    /// (equation·DOC_DATA 등 중첩 raw 필드가 viewer opt-out을 우회하지 않게, R43 #3)
    func preservedPayload(_ data: Data?) -> Data? {
        data.map(preservedPayload)
    }

    /// 파싱/렌더 로직이 다시 읽는 슬라이스 게이트: off면 분리 복사해
    /// 압축 해제 스트림 버퍼 참조만 끊는다 (byte 내용은 양 모드 동일).
    func decoupledPayload(_ data: Data) -> Data {
        preserveRawPayload ? data : Data(data)
    }
}
