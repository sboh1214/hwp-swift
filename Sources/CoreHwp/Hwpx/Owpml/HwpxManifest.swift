import Foundation

/// `Contents/content.hpf`(OPF package) 해석 — 구역 순서와 BinData 목록의 정본.
///
/// `opf:manifest/opf:item`이 컨테이너 안 파일을 id로 등재하고,
/// `opf:spine/opf:itemref`가 본문 구역의 순서를 정한다. 그림 등 첨부
/// (`BinData/*` href)는 manifest 등재 순서가 곧 HWP5식 BinItem id 공간의
/// 순서가 된다 (`HwpxBinDataMapper`).
struct HwpxManifest {
    struct Item {
        let id: String
        let href: String
        let mediaType: String
    }

    let items: [Item]
    /// spine 순서로 나열한 구역 엔트리 이름 (`Contents/section{N}.xml`만).
    let sectionHrefs: [String]
    /// 이 패키지 문서가 실제로 읽힌 엔트리 이름 — container.xml이 관례
    /// 경로가 아닌 rootfile을 지목할 수 있으므로 진단은 이것을 가리켜야 한다.
    let entry: String

    /// 헤더 파트의 **선언** 경로 — manifest가 `id="header"`로 등재한다.
    ///
    /// media-type으로는 특정할 수 없다 — 구역·설정과 같은 `application/xml`
    /// 이라(실측: 전 픽스처 31건이 같은 값) 타입 기반 식별이 불가능하다.
    /// `id="header"`는 픽스처 10종·한컴 템플릿 전수가 쓰는 관례이고, 선언이
    /// 없으면 호출자가 관례 경로로 폴백한다 (다른 id를 쓰는 생산자를
    /// 거부하지 않게).
    var headerHref: String? {
        items.first { $0.id == "header" }?.href
    }

    /// `BinData/` 아래 첨부 항목 — manifest 등재 순서 보존.
    var binDataItems: [Item] {
        items.filter { $0.href.hasPrefix("BinData/") }
    }

    static func parse(_ data: Data, entry: String) throws -> HwpxManifest {
        let root = try HwpxXMLTreeParser.parse(data, entry: entry)
        guard root.isNamed("package", in: HwpxNamespace.opf) else {
            throw HwpError.invalidXML(
                entry: entry,
                reason: "unexpected root element <\(root.localName)>"
            )
        }

        var items: [Item] = []
        if let manifest = Self.opfChild(root, "manifest") {
            for node in Self.opfChildren(manifest, "item") {
                let href = node.attribute("href") ?? ""
                guard !href.isEmpty else {
                    continue
                }
                items.append(Item(
                    id: node.attribute("id") ?? "",
                    href: href,
                    mediaType: node.attribute("media-type") ?? ""
                ))
            }
        }

        var hrefById: [String: String] = [:]
        for item in items where !item.id.isEmpty {
            if hrefById[item.id] == nil {
                hrefById[item.id] = item.href
            }
        }

        var sectionHrefs: [String] = []
        if let spine = Self.opfChild(root, "spine") {
            for itemref in Self.opfChildren(spine, "itemref") {
                guard let idref = itemref.attribute("idref"),
                      let href = hrefById[idref],
                      HwpxContainer.sectionIndex(of: href) != nil
                else {
                    continue
                }
                sectionHrefs.append(href)
            }
        }

        return HwpxManifest(items: items, sectionHrefs: sectionHrefs, entry: entry)
    }

    /// manifest/spine 자식은 정의상 OPF vocabulary다 — 전역 known 매칭은
    /// 다른 known vocabulary의 동명 요소에 가로채인다 ((namespace, local name)).
    static func opfChild(_ parent: HwpxXMLNode, _ name: String) -> HwpxXMLNode? {
        parent.childElements.first { $0.isNamed(name, in: HwpxNamespace.opf) }
    }

    static func opfChildren(_ parent: HwpxXMLNode, _ name: String) -> [HwpxXMLNode] {
        parent.childElements.filter { $0.isNamed(name, in: HwpxNamespace.opf) }
    }
}
