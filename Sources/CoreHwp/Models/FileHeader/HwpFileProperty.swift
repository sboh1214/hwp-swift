import Foundation

public struct HwpFileProperty {
    /** 원본 bit field */
    @ExcludeEquatable
    public var rawValue: UInt32
    /** 압축 여부 */
    public var isCompressed: Bool
    /** 암호 설정 여부 */
    public var isEncrypted: Bool
    /** 배포용 문서 여부 */
    public var isDeploymentDocument: Bool
    /** 스크립트 저장 여부 */
    public var doesSaveScript: Bool
    /** DRM 보안 문서 여부 */
    public var isDRMDocument: Bool
    /** XMLTemplate 스토리지 존재 여부 */
    public var doesHaveXMLTemplate: Bool
    /** 문서 이력 관리 존재 여부 */
    public var doesHaveDocumentHistory: Bool
    /** 전자 서명 정보 존재 여부 */
    public var doesHaveSignature: Bool
    /** 공인 인증서 암호화 여부 */
    public var doesEncryptAccreditedCertificate: Bool
    /** 전자 서명 예비 저장 여부 */
    public var doesSaveSpareSignature: Bool
    /** 공인 인증서 DRM 보안 문서 여부 */
    public var isAccreditedCertificateDRMDocment: Bool

    /** 공인 인증서 DRM 보안 문서 여부 */
    public var isAccreditedCertificateDRMDocument: Bool {
        get {
            isAccreditedCertificateDRMDocment
        }
        set {
            isAccreditedCertificateDRMDocment = newValue
        }
    }

    /** CCL 문서 여부 */
    public var isCCLDocument: Bool
    /** 모바일 최적화 여부 */
    public var doesOptimizeMobile: Bool
    /** 개인 정보 보안 문서 여부 */
    public var isPersonalInformationSecurityDocument: Bool
    /** 변경 추적 문서 여부 */
    public var isTracingChange: Bool
    /** 공공누리(KOGL) 저작권 문서 */
    public var isKOGLDocument: Bool
    /** 비디오 컨트롤 포함 여부 */
    public var doesHaveVideoControl: Bool
    /** 차례 필드 컨트롤 포함 여부 */
    public var doesHaveTOCFieldControl: Bool

    var unused: [Bool]
}

extension HwpFileProperty: HwpFromUInt {
    typealias UIntType = UInt32

    init(_ reader: inout BitsReader<UIntType>) throws {
        rawValue = 0
        isCompressed = try reader.readBit()
        isEncrypted = try reader.readBit()
        isDeploymentDocument = try reader.readBit()
        doesSaveScript = try reader.readBit()
        isDRMDocument = try reader.readBit()
        doesHaveXMLTemplate = try reader.readBit()
        doesHaveDocumentHistory = try reader.readBit()
        doesHaveSignature = try reader.readBit()
        doesEncryptAccreditedCertificate = try reader.readBit()
        doesSaveSpareSignature = try reader.readBit()
        isAccreditedCertificateDRMDocment = try reader.readBit()
        isCCLDocument = try reader.readBit()
        doesOptimizeMobile = try reader.readBit()
        isPersonalInformationSecurityDocument = try reader.readBit()
        isTracingChange = try reader.readBit()
        isKOGLDocument = try reader.readBit()
        doesHaveVideoControl = try reader.readBit()
        doesHaveTOCFieldControl = try reader.readBit()

        unused = try reader.readBits(14)
    }

    static func load(_ uint: UIntType) throws -> Self {
        var reader = BitsReader(from: uint)
        var fileProperty = try self.init(&reader)
        if !reader.isEOF {
            throw HwpError.bitsAreNotEOF(model: Self.self, remain: reader.remainBits)
        }
        fileProperty.rawValue = uint
        return fileProperty
    }
}

extension HwpFileProperty {
    public var unsupportedFeature: HwpUnsupportedFeature? {
        if isEncrypted || doesEncryptAccreditedCertificate {
            return .encryptedDocument
        }
        if isDeploymentDocument {
            return .deploymentDocument
        }
        if isDRMDocument || isAccreditedCertificateDRMDocument {
            return .drmDocument
        }
        return nil
    }

    init() {
        rawValue = 1
        isCompressed = true
        isEncrypted = false
        isDeploymentDocument = false
        doesSaveScript = false
        isDRMDocument = false
        doesHaveXMLTemplate = false
        doesHaveDocumentHistory = false
        doesHaveSignature = false
        doesEncryptAccreditedCertificate = false
        doesSaveSpareSignature = false
        isAccreditedCertificateDRMDocment = false
        isCCLDocument = false
        doesOptimizeMobile = false
        isPersonalInformationSecurityDocument = false
        isTracingChange = false
        isKOGLDocument = false
        doesHaveVideoControl = false
        doesHaveTOCFieldControl = false

        unused = Array(repeating: false, count: 14)
    }
}
