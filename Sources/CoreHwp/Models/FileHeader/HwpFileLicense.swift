import Foundation

public struct HwpFileLicense {
    /** 원본 bit field */
    @ExcludeEquatable
    public var rawValue: UInt32
    /** CCL, 공공누리 라이선스 정보 */
    public var doesHaveKoreaOpenLicense: Bool
    /** 복제 제한 여부 */
    public var doesLimitReplication: Bool
    /**
     동일 조건 하에 복제 허가 여부

     복제 제한인 경우 무시
     */
    public var doesHavePermission: Bool

    var unused: [Bool]
}

extension HwpFileLicense: HwpFromUInt {
    typealias UIntType = UInt32

    init(_ reader: inout BitsReader<UIntType>) throws {
        rawValue = 0
        doesHaveKoreaOpenLicense = try reader.readBit()
        doesLimitReplication = try reader.readBit()
        doesHavePermission = try reader.readBit()

        unused = try reader.readBits(29)
    }

    static func load(_ uint: UIntType) throws -> Self {
        var reader = BitsReader(from: uint)
        var fileLicense = try self.init(&reader)
        if !reader.isEOF {
            throw HwpError.bitsAreNotEOF(model: Self.self, remain: reader.remainBits)
        }
        fileLicense.rawValue = uint
        return fileLicense
    }
}

extension HwpFileLicense {
    init() {
        rawValue = 0
        doesHaveKoreaOpenLicense = false
        doesLimitReplication = false
        doesHavePermission = false

        unused = Array(repeating: false, count: 29)
    }
}
