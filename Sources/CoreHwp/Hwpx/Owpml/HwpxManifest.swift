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

    /// `BinData/` 아래 첨부 항목 — manifest 등재 순서 보존.
    var binDataItems: [Item] {
        items.filter { $0.href.hasPrefix("BinData/") }
    }

    static func parse(_ data: Data) throws -> HwpxManifest {
        let entry = HwpxContainer.EntryName.manifest
        let root = try HwpxXMLTreeParser.parse(data, entry: entry)
        guard root.isNamed("package") else {
            throw HwpError.invalidXML(
                entry: entry,
                reason: "unexpected root element <\(root.localName)>"
            )
        }

        var items: [Item] = []
        if let manifest = root.firstChild(named: "manifest") {
            for node in manifest.children(named: "item") {
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
        if let spine = root.firstChild(named: "spine") {
            for itemref in spine.children(named: "itemref") {
                guard let idref = itemref.attribute("idref"),
                      let href = hrefById[idref],
                      HwpxContainer.sectionIndex(of: href) != nil
                else {
                    continue
                }
                sectionHrefs.append(href)
            }
        }

        return HwpxManifest(items: items, sectionHrefs: sectionHrefs)
    }
}
