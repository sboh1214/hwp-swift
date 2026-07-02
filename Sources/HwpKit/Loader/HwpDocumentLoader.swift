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
}
