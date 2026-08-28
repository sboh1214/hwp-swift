import CoreHwp
import Foundation
import HwpKitCore
import HwpKitNative

/// 로더가 지원하지 않는 문서의 종류. CoreHwp의 `HwpUnsupportedFeature`에
/// 대응하는 HwpKit 공개 타입으로, 호스트는 CoreHwp를 import하지 않고도 문서
/// 종류에 따라 분기할 수 있다.
public enum HwpUnsupportedDocumentKind: Sendable, Hashable {
    /// 암호로 보호된 문서(공인 인증서 암호화 포함)
    case encryptedDocument
    /// 배포용 문서
    case deploymentDocument
    /// 일반 DRM이나 공인 인증서 DRM이 적용된 문서
    case drmDocument

    /// CoreHwp에서 지원하지 않는 문서 종류가 추가되면 이 `switch` 문에서
    /// 컴파일 오류가 발생한다. 새 종류가 누락되지 않도록 `default`는 추가하지
    /// 않는다.
    init(_ feature: HwpUnsupportedFeature) {
        switch feature {
        case .encryptedDocument:
            self = .encryptedDocument
        case .deploymentDocument:
            self = .deploymentDocument
        case .drmDocument:
            self = .drmDocument
        }
    }
}

public enum HwpDocumentLoadError: Error, Sendable {
    case cancelled
    case presentationBuildFailed(String)
    case invalidFileWrapper
    /// 파서가 지원하지 않는 암호로 보호된 문서·배포용 문서·DRM 문서. 일반
    /// 오류 문자열로 변환하지 않고 문서 종류를 보존하므로 호스트가 알맞은 안내를
    /// 표시하거나 종류별로 분기할 수 있다 (#117).
    case unsupportedDocument(HwpUnsupportedDocumentKind)
}

extension HwpDocumentLoadError: CustomStringConvertible {
    /// 사용자에게 그대로 표시할 수 있는 한국어 오류 설명 (#117).
    /// `presentationBuildFailed`는 하위 계층의 오류 설명을 원문 그대로 덧붙이므로
    /// 영어가 포함될 수 있다. `HwpError`의 설명을 한국어로 바꾸는 작업은 이 변경의
    /// 범위에 포함하지 않는다 (#117의 A안).
    public var description: String {
        switch self {
        case .cancelled:
            "문서 불러오기가 취소되었습니다"
        case let .presentationBuildFailed(reason):
            "문서를 여는 데 실패했습니다: \(reason)"
        case .invalidFileWrapper:
            "파일 래퍼가 내용을 포함한 일반 파일을 나타내지 않습니다"
        case let .unsupportedDocument(kind):
            switch kind {
            case .encryptedDocument:
                "암호로 보호된 문서는 열 수 없습니다"
            case .deploymentDocument:
                "배포용 문서는 열 수 없습니다"
            case .drmDocument:
                "DRM으로 보호된 문서는 열 수 없습니다"
            }
        }
    }
}

extension HwpDocumentLoadError: LocalizedError {
    public var errorDescription: String? {
        description
    }
}

/// .hwp 파일을 읽어 화면에 그릴 수 있는 `HwpDocument`로 만드는 로더 —
/// HwpKit 사용의 시작점이다. URL·Data·FileWrapper를 받아 파싱과 조판을
/// 백그라운드(`HwpDocumentActor`)에서 수행하고, 실패는
/// `HwpDocumentLoadError`로 던진다. 큰 문서는 `loadUpdates(from:)`로
/// 첫 페이지가 확정되는 즉시 중간 스냅샷을 받을 수 있다.
public struct HwpDocumentLoader: Sendable {
    private let actor: HwpDocumentActor

    public init(fontResolver: HwpFontResolver = HwpFontResolver()) {
        actor = HwpDocumentActor(fontResolver: fontResolver)
    }

    /// 하위 계층의 오류를 `HwpDocumentLoadError`로 변환하는 단일 지점 (#117).
    /// `HwpError.unsupportedFeature`는 일반 오류 문자열로 바꾸기 전에 따로
    /// 처리하여 문서 종류를 보존한다. `CancellationError`는 각 호출부에서 별도의
    /// `catch` 절로 먼저 처리한다. `HwpDocumentLoadError`를 그대로 반환하는
    /// 분기는 공개 API만으로 재현하기 어려우므로 이 메서드는 `internal`로 두고
    /// 테스트에서 세 분기를 직접 검증한다.
    static func mapLoadFailure(_ error: Error) -> HwpDocumentLoadError {
        if let error = error as? HwpDocumentLoadError {
            return error
        }
        if case let HwpError.unsupportedFeature(feature) = error {
            return .unsupportedDocument(HwpUnsupportedDocumentKind(feature))
        }
        return .presentationBuildFailed(error.localizedDescription)
    }

    public func load(from url: URL) async throws -> HwpDocument {
        do {
            return try await actor.loadDocument(from: url)
        } catch is CancellationError {
            throw HwpDocumentLoadError.cancelled
        } catch {
            throw Self.mapLoadFailure(error)
        }
    }

    public func load(from data: Data) async throws -> HwpDocument {
        do {
            return try await actor.loadDocument(from: data)
        } catch is CancellationError {
            throw HwpDocumentLoadError.cancelled
        } catch {
            throw Self.mapLoadFailure(error)
        }
    }

    public func load(from fileWrapper: FileWrapper) async throws -> HwpDocument {
        guard fileWrapper.isRegularFile, let data = fileWrapper.regularFileContents else {
            throw HwpDocumentLoadError.invalidFileWrapper
        }
        return try await load(from: data)
    }

    /// 프로그레시브 로딩 — 첫 페이지 확정 즉시 스냅샷이 나오고, 이후
    /// 배치 단위 중간 스냅샷 → 최종 스냅샷 (isComplete)으로 끝난다.
    /// 최종 문서는 `load(from:)` 결과와 동일하다. 에러는
    /// `HwpDocumentLoadError`로 매핑된다.
    public func loadUpdates(
        from url: URL
    ) async -> AsyncThrowingStream<HwpDocumentSnapshot, Error> {
        let inner = await actor.loadDocumentUpdates(from: url)
        // 누적 스냅샷은 최신이 이전 것을 포함하므로 최신 소수만 버퍼링한다 —
        // 느린 소비자에서 스냅샷이 무제한 쌓여 페이지 수 대비 ~제곱으로 메모리가
        // 늘어나는 것을 막는다 (#10). 따라가는 소비자는 전량을 그대로 본다.
        let (stream, continuation) = AsyncThrowingStream<HwpDocumentSnapshot, Error>
            .makeStream(bufferingPolicy: .bufferingNewest(8))
        let task = Task {
            do {
                for try await snapshot in inner {
                    continuation.yield(snapshot)
                }
                continuation.finish()
            } catch is CancellationError {
                continuation.finish(throwing: HwpDocumentLoadError.cancelled)
            } catch {
                continuation.finish(throwing: Self.mapLoadFailure(error))
            }
        }
        continuation.onTermination = { @Sendable _ in task.cancel() }
        return stream
    }
}
