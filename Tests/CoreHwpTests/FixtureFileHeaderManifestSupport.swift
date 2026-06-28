struct FixtureFilePropertyExpectations: Decodable {
    let rawValue: UInt32?
    let isCompressed: Bool?
    let isEncrypted: Bool?
    let isDeploymentDocument: Bool?
    let isDRMDocument: Bool?
    let doesEncryptAccreditedCertificate: Bool?
    let isAccreditedCertificateDRMDocument: Bool?
    let doesHaveDocumentHistory: Bool?
    let isCCLDocument: Bool?
    let isTracingChange: Bool?
    let isKOGLDocument: Bool?
}

struct FixtureFileLicenseExpectations: Decodable {
    let rawValue: UInt32?
    let doesHaveKoreaOpenLicense: Bool?
    let doesLimitReplication: Bool?
    let doesHavePermission: Bool?
}
