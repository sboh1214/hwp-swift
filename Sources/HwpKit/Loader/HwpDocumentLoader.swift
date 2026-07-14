import Foundation
import HwpKitCore
import HwpKitNative

public enum HwpDocumentLoadError: Error, Sendable {
    case cancelled
    case presentationBuildFailed(String)
    case invalidFileWrapper
}

public struct HwpDocumentLoader: Sendable {
    private let actor: HwpDocumentActor

    public init(fontResolver: HwpFontResolver = HwpFontResolver()) {
        actor = HwpDocumentActor(fontResolver: fontResolver)
    }

    public func load(from url: URL) async throws -> HwpDocument {
        do {
            return try await actor.loadDocument(from: url)
        } catch is CancellationError {
            throw HwpDocumentLoadError.cancelled
        } catch {
            throw HwpDocumentLoadError.presentationBuildFailed(error.localizedDescription)
        }
    }

    public func load(from data: Data) async throws -> HwpDocument {
        do {
            return try await actor.loadDocument(from: data)
        } catch is CancellationError {
            throw HwpDocumentLoadError.cancelled
        } catch {
            throw HwpDocumentLoadError.presentationBuildFailed(error.localizedDescription)
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
            } catch let error as HwpDocumentLoadError {
                continuation.finish(throwing: error)
            } catch {
                continuation.finish(throwing: HwpDocumentLoadError.presentationBuildFailed(
                    error.localizedDescription
                ))
            }
        }
        continuation.onTermination = { @Sendable _ in task.cancel() }
        return stream
    }
}
