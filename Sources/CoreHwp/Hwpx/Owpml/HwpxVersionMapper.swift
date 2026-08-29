import Foundation

/// `version.xml`(`hv:HCFVersion`)을 `HwpVersion`·`HwpFileHeader`로 합성한다.
///
/// HWPX에는 바이너리 FileHeader가 없다 — 버전 4성분만 가져오고 나머지는
/// 빈 문서 기본값으로 채운다. 암호화·배포 문서는 컨테이너 게이트가 이미
/// 거부했으므로 여기 도달한 문서의 `fileProperty`는 미지원 비트가 없는
/// 상태가 맞다. `isCompressed`는 OLE stream 압축 개념이라 HWPX와 무관하다.
///
/// 엔트리 **부재**(nil)는 제3자 저장기의 생략으로 보고 기본 버전으로
/// 합성하지만, 존재하는 엔트리의 **손상**(XML 오류·엉뚱한 루트)은 기본값으로
/// 삼키지 않고 typed error로 전파한다 — 모델 안에서 오류를 잡아 기본값을
/// 돌려주지 않는 CoreHwp 규약 그대로다.
enum HwpxVersionMapper {
    /// OWPML 없는 문서·구버전 저장기를 위한 기본 버전 — 한컴 저장본 실측값.
    static let defaultVersion = HwpVersion(5, 1, 1, 0)

    static func version(fromVersionXML data: Data?) throws -> HwpVersion {
        guard let data else {
            return defaultVersion
        }
        let root = try HwpxXMLTreeParser.parse(
            data, entry: HwpxContainer.EntryName.version
        )
        guard root.isNamed("HCFVersion", in: HwpxNamespace.version) else {
            throw HwpError.invalidXML(
                entry: HwpxContainer.EntryName.version,
                reason: "unexpected root element <\(root.localName)>"
            )
        }
        // OWPML major.minor.micro.buildNumber ↔ HWP5 M.n.P.r — 한컴 저장본
        // 실측으로 micro→build, buildNumber→revision 자리에 대응한다.
        return HwpVersion(
            root.intAttribute("major", default: 5),
            root.intAttribute("minor", default: 1),
            root.intAttribute("micro", default: 1),
            root.intAttribute("buildNumber", default: 0)
        )
    }

    static func fileHeader(version: HwpVersion) -> HwpFileHeader {
        var header = HwpFileHeader()
        header.version = version
        header.encryptVersion = 0
        return header
    }
}
