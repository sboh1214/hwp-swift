import Foundation

/**
 파일 버전. 0xMMnnPPrr의 형태(예 5.0.3.0)
 - MM: 문서 형식의 구조가 완전히 바뀌는 것을 나타냄. 숫
 자가 다르면 구 버전과 호환 불가능.
 - nn: 큰 구조는 동일하나, 큰 변화가 있는 것을 나타냄. 숫
 자가 다르면 구 버전과 호환 불가능.
 - PP: 구조는 동일, Record가 추가되었거나, 하위 버전에서
 호환되지 않는 정보가 추가된 것을 나타냄. 숫자가 달라도
 구 버전과 호환 가능.
 - rr: Record에 정보들이 추가된 것을 나타냄. 숫자가 달라
 도 구 버전과 호환 가능.
 */
public struct HwpVersion: HwpFromData {
    /** 원본 payload */
    public let rawPayload: Data
    public let major: UInt8
    public let minor: UInt8
    public let build: UInt8
    public let revision: UInt8

    /** 0xMMnnPPrr 형태의 원본 version 값 */
    public var rawValue: UInt32 {
        UInt32(revision)
            | UInt32(build) << 8
            | UInt32(minor) << 16
            | UInt32(major) << 24
    }

    init() {
        major = 5
        minor = 1
        build = 0
        revision = 1
        rawPayload = Self.rawPayload(major: major, minor: minor, build: build, revision: revision)
    }

    init(_ reader: inout DataReader) throws {
        let startOffset = reader.byteOffset
        revision = try reader.read(UInt8.self)
        build = try reader.read(UInt8.self)
        minor = try reader.read(UInt8.self)
        major = try reader.read(UInt8.self)
        rawPayload = try reader.consumedData(from: startOffset)
    }

    public init(_ major: Int, _ minor: Int, _ build: Int, _ revision: Int) {
        self.major = UInt8(clamping: major)
        self.minor = UInt8(clamping: minor)
        self.build = UInt8(clamping: build)
        self.revision = UInt8(clamping: revision)
        rawPayload = Self.rawPayload(
            major: self.major,
            minor: self.minor,
            build: self.build,
            revision: self.revision
        )
    }

    private static func rawPayload(
        major: UInt8,
        minor: UInt8,
        build: UInt8,
        revision: UInt8
    ) -> Data {
        Data([revision, build, minor, major])
    }
}

extension HwpVersion: Comparable {
    public static func < (lhs: HwpVersion, rhs: HwpVersion) -> Bool {
        if lhs.major < rhs.major {
            return true
        }
        if lhs.major > rhs.major {
            return false
        }
        if lhs.minor < rhs.minor {
            return true
        }
        if lhs.minor > rhs.minor {
            return false
        }
        if lhs.build < rhs.build {
            return true
        }
        if lhs.build > rhs.build {
            return false
        }
        if lhs.revision < rhs.revision {
            return true
        }
        return false
    }
}
