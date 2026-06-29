import Foundation
import OLEKit

#if os(Linux)
    import Glibc
#endif

func coreHwpOLEFile(
    fromData data: Data,
    preferredFilename: String = "document.hwp"
) throws -> OLEFile {
    #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
        let fileWrapper = FileWrapper(regularFileWithContents: data)
        fileWrapper.preferredFilename = preferredFilename
        return try coreHwpOLEFile(fromWrapper: fileWrapper)
    #else
        return try coreHwpOLEFileFromTemporaryData(
            data,
            preferredFilename: preferredFilename
        )
    #endif
}

func coreHwpOLEFile(fromWrapper fileWrapper: FileWrapper) throws -> OLEFile {
    #if os(iOS) || os(watchOS) || os(tvOS) || os(macOS)
        do {
            return try OLEFile(fileWrapper)
        } catch {
            throw HwpError.invalidOLEFile(reason: String(describing: error))
        }
    #else
        guard let data = fileWrapper.regularFileContents else {
            throw HwpError.invalidOLEFile(reason: "FileWrapper does not contain regular file data")
        }
        return try coreHwpOLEFileFromTemporaryData(
            data,
            preferredFilename: fileWrapper.filename
                ?? fileWrapper.preferredFilename
                ?? "document.hwp"
        )
    #endif
}

#if os(Linux)
    var coreHwpTemporaryDirectoryOverride: URL?
    var coreHwpTemporaryFileDidCreate: ((URL) -> Void)?
    var coreHwpTemporaryFileCleanupDidFail: ((URL, Error) -> Void)?

    private func coreHwpOLEFileFromTemporaryData(
        _ data: Data,
        preferredFilename: String
    ) throws -> OLEFile {
        // OLEKit on Linux exposes only a path-based initializer for this use case, so
        // CoreHwp writes a private temporary copy and removes it immediately after load.
        let fileURL = try createTemporaryOLEFile(
            data,
            preferredFilename: preferredFilename
        )
        defer {
            removeTemporaryOLEFile(at: fileURL)
        }

        do {
            return try OLEFile(fileURL.path)
        } catch let error as HwpError {
            throw error
        } catch {
            throw HwpError.invalidOLEFile(reason: String(describing: error))
        }
    }

    private func createTemporaryOLEFile(
        _ data: Data,
        preferredFilename: String
    ) throws -> URL {
        let directory = coreHwpTemporaryDirectoryOverride
            ?? FileManager.default.temporaryDirectory
        let filename = sanitizedTemporaryOLEFilename(preferredFilename)
        let suffix = "-\(filename)"
        let templateURL = directory.appendingPathComponent(
            "CoreHwp-\(UUID().uuidString)-XXXXXX\(suffix)"
        )
        var template = Array(templateURL.path.utf8CString)
        let descriptor = mkstemps(&template, Int32(suffix.utf8.count))
        guard descriptor >= 0 else {
            throw HwpError.temporaryFileWriteFailed(reason: coreHwpErrnoDescription())
        }

        let actualPath = String(cString: template)
        let fileURL = URL(fileURLWithPath: actualPath)
        var descriptorIsClosed = false
        defer {
            if !descriptorIsClosed {
                _ = close(descriptor)
            }
        }

        do {
            try writeTemporaryOLEData(data, to: descriptor)
            descriptorIsClosed = true
            try closeTemporaryOLEFileDescriptor(descriptor)
            coreHwpTemporaryFileDidCreate?(fileURL)
            return fileURL
        } catch let error as HwpError {
            removeTemporaryOLEFile(at: fileURL)
            throw error
        }
    }

    private func sanitizedTemporaryOLEFilename(_ preferredFilename: String) -> String {
        let filename = URL(fileURLWithPath: preferredFilename).lastPathComponent
        if filename.isEmpty {
            return "document.hwp"
        }
        return filename
    }

    private func writeTemporaryOLEData(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return
            }

            var offset = 0
            var remaining = buffer.count
            while remaining > 0 {
                let written = write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    remaining
                )
                if written < 0 {
                    if errno == EINTR {
                        continue
                    }
                    throw HwpError.temporaryFileWriteFailed(
                        reason: coreHwpErrnoDescription()
                    )
                }
                if written == 0 {
                    throw HwpError.temporaryFileWriteFailed(
                        reason: "write returned 0 bytes"
                    )
                }
                offset += written
                remaining -= written
            }
        }
    }

    private func closeTemporaryOLEFileDescriptor(_ descriptor: Int32) throws {
        while close(descriptor) != 0 {
            if errno == EINTR {
                continue
            }
            throw HwpError.temporaryFileWriteFailed(
                reason: coreHwpErrnoDescription()
            )
        }
    }

    private func removeTemporaryOLEFile(at fileURL: URL) {
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            reportTemporaryOLEFileCleanupFailure(fileURL, error)
        }
    }

    private func reportTemporaryOLEFileCleanupFailure(_ fileURL: URL, _ error: Error) {
        coreHwpTemporaryFileCleanupDidFail?(fileURL, error)

        #if DEBUG
            // swiftlint:disable:next no_space_in_method_call
            assertionFailure /* debug cleanup leak */ (
                "CoreHwp temporary file cleanup failed for \(fileURL.path): \(error)",
                file: #fileID,
                line: #line
            )
        #endif
    }

    private func coreHwpErrnoDescription(_ code: Int32 = errno) -> String {
        String(cString: strerror(code))
    }
#endif
