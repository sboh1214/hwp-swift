import Foundation

/// 문서 로드 옵션. 백그라운드 파싱의 @Sendable 클로저에 캡처되므로 명시
/// Sendable — public 비-frozen 구조체는 모듈 밖 추론이 없다 (R39 #1).
public struct HwpLoadOptions: Sendable {
    /// HWP stream을 읽을 때 허용할 자원 상한 (byte 수와 레코드 트리 깊이).
    public var readLimits: HwpReadLimits

    /// 파싱 모델의 rawPayload/rawTrailing 원본 보존 여부. 기본 true.
    /// false(뷰어)면 보존용 슬라이스를 비워 압축 해제 스트림 버퍼가
    /// 파싱 후 해제되게 한다. 파싱된 typed 필드는 양 모드 동일.
    public var preserveRawPayload: Bool

    /// 손상 문단·구역을 fail-fast 대신 placeholder로 대체해 나머지 본문을
    /// 살리는 best-effort 복구 여부. 기본 false (기존 fail-fast 시맨틱).
    /// 복구는 BodyText 한정이다 — ViewText는 구역 하나라도 실패하면 전량
    /// 폐기해 BodyText로 강등하는 기존 채택 규칙을 유지한다 (#65).
    /// FileHeader `unsupportedFeature`·자원 한도 2종은 켜져 있어도 전파된다.
    public var recoverPartialContent: Bool

    public init(
        readLimits: HwpReadLimits = .default,
        preserveRawPayload: Bool = true,
        recoverPartialContent: Bool = false
    ) {
        self.readLimits = readLimits
        self.preserveRawPayload = preserveRawPayload
        self.recoverPartialContent = recoverPartialContent
    }

    /// 기본 옵션 — 원본 payload를 전부 보존한다 (기존 동작).
    public static let `default` = HwpLoadOptions()

    /// 뷰어 옵션 — 보존용 원본 슬라이스를 비워 상주 메모리를 줄이고,
    /// 손상 문단·구역은 placeholder로 복구해 나머지 본문을 그린다.
    public static let viewer = HwpLoadOptions(
        preserveRawPayload: false,
        recoverPartialContent: true
    )
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
