import Foundation

#if os(Linux)

    // MARK: - Linux Foundation FileWrapper compatibility

    /// Linux Foundation에 없는 `FileWrapper`를 보완하는 최소 호환 타입입니다.
    ///
    /// `HwpFile.init(fromWrapper:)` public 진입점을 Linux에서도 유지하기 위한 플랫폼
    /// 어댑터이며, HWP 문서 모델 표면이 아닙니다.
    public struct FileWrapper {
        /// 파일 읽기 옵션입니다.
        public struct ReadingOptions: OptionSet, Sendable {
            public let rawValue: UInt

            public init(rawValue: UInt) {
                self.rawValue = rawValue
            }

            public static let immediate = ReadingOptions(rawValue: 1 << 0)
        }

        /// regular file payload입니다.
        public var regularFileContents: Data?

        /// 선호 파일명입니다.
        public var preferredFilename: String?

        /// 파일명입니다.
        public var filename: String?

        /// regular file payload로 wrapper를 생성합니다.
        public init(regularFileWithContents contents: Data) {
            regularFileContents = contents
        }

        /// URL의 regular file payload로 wrapper를 생성합니다.
        public init(url: URL, options _: ReadingOptions = []) throws {
            regularFileContents = try Data(contentsOf: url)
            filename = url.lastPathComponent
            preferredFilename = url.lastPathComponent
        }
    }
#endif
