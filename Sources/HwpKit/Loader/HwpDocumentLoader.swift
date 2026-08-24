import CoreHwp
import Foundation
import HwpKitCore
import HwpKitNative

/// 로더가 열 수 없는 미지원 문서 종류. CoreHwp `HwpUnsupportedFeature`의
/// HwpKit 공개 대응물 — 호스트가 CoreHwp를 import하지 않고 분기한다.
public enum HwpUnsupportedDocumentKind: Sendable, Hashable {
    /// 암호로 보호된 문서 (공인 인증서 암호화 포함)
    case encryptedDocument
    /// 배포용 문서
    case deploymentDocument
    /// DRM 또는 공인 인증서 DRM이 적용된 문서
    case drmDocument

    /// CoreHwp에 미지원 종류가 늘면 여기서 컴파일 에러로 잡힌다 —
    /// default를 넣어 새 종류를 조용히 뭉개지 말 것.
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
    /// 파서가 지원하지 않는 문서 (암호·배포용·DRM). 문자열로 접지 않고
    /// 종류를 보존해 호스트가 안내·분기할 수 있게 한다 (#117).
    case unsupportedDocument(HwpUnsupportedDocumentKind)
}

extension HwpDocumentLoadError: CustomStringConvertible {
    /// 사용자에게 그대로 보여줄 수 있는 한국어 서술 (#117).
    /// `presentationBuildFailed`의 reason은 하위 계층이 넘긴 원문이라 영문일 수
    /// 있다 — `HwpError` 서술까지 한국어로 바꾸는 것은 범위 밖이다 (#117 (A)안).
    public var description: String {
        switch self {
        case .cancelled:
            "문서 로드가 취소되었습니다"
        case let .presentationBuildFailed(reason):
            "문서를 여는 데 실패했습니다: \(reason)"
        case .invalidFileWrapper:
            "파일 래퍼가 내용이 있는 일반 파일이 아닙니다"
        case let .unsupportedDocument(kind):
            switch kind {
            case .encryptedDocument:
                "암호로 보호된 문서라 열 수 없습니다"
            case .deploymentDocument:
                "배포용 문서라 열 수 없습니다"
            case .drmDocument:
                "DRM으로 보호된 문서라 열 수 없습니다"
            }
        }
    }
}

extension HwpDocumentLoadError: LocalizedError {
    public var errorDescription: String? {
        description
    }
}

public struct HwpDocumentLoader: Sendable {
    private let actor: HwpDocumentActor

    public init(fontResolver: HwpFontResolver = HwpFontResolver()) {
        actor = HwpDocumentActor(fontResolver: fontResolver)
    }

    /// 하위 계층 에러를 `HwpDocumentLoadError`로 접는 단일 관문 (#117).
    /// 미지원 문서는 `HwpError.unsupportedFeature`가 문자열로 뭉개지기 전에
    /// 가로채 종류를 보존한다. `CancellationError`는 각 호출부의 별도 catch가
    /// 먼저 처리한다. internal인 이유: passthrough 갈래가 공개 표면에서는
    /// 재현하기 어려워 세 갈래를 테스트가 직접 고정한다.
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
