@testable import CoreHwp
import Foundation

enum FixtureDerivedValues {
    static func sectionRawPayloads(from hwp: HwpFile) -> [Data] {
        hwp.sectionArray.map(\.rawPayload)
    }

    static func visibleText(from hwp: HwpFile) -> String {
        visibleText(from: allParagraphs(from: hwp))
    }

    static func visibleTextsBySection(from hwp: HwpFile) -> [String] {
        hwp.sectionArray.map { section in
            visibleText(from: allParagraphs(from: section.paragraph))
        }
    }

    private static func visibleText(from paragraphs: [HwpParagraph]) -> String {
        paragraphs
            .compactMap(\.paraText)
            .flatMap(\.charArray)
            .compactMap { char -> UnicodeScalar? in
                guard char.type == .char else {
                    return nil
                }
                return UnicodeScalar(Int(char.value))
            }
            .map(String.init)
            .joined()
    }

    static func paraTextPayloads(from hwp: HwpFile) -> [Data] {
        allParagraphs(from: hwp)
            .compactMap(\.paraText)
            .flatMap(\.charArray)
            .compactMap(\.payload)
    }

    static func paraTextInlineControls(from hwp: HwpFile) -> [HwpInlineControl] {
        allParagraphs(from: hwp)
            .compactMap(\.paraText)
            .flatMap(\.charArray)
            .compactMap(\.inlineControl)
    }

    static func paraTextRawPayloads(from hwp: HwpFile) -> [Data] {
        allParagraphs(from: hwp)
            .compactMap(\.paraText)
            .map(\.rawPayload)
    }

    static func paraHeaderPayloads(from hwp: HwpFile) -> [Data] {
        allParagraphs(from: hwp)
            .map(\.paraHeader.rawPayload)
    }

    static func paraCharShapePayloads(from hwp: HwpFile) -> [Data] {
        allParagraphs(from: hwp)
            .map(\.paraCharShape.rawPayload)
    }

    static func paraLineSegPayloads(from hwp: HwpFile) -> [Data] {
        allParagraphs(from: hwp)
            .map(\.paraLineSeg.rawPayload)
            .filter { !$0.isEmpty }
    }

    static func paraRangeTags(from hwp: HwpFile) -> [HwpParaRangeTag] {
        allParagraphs(from: hwp)
            .compactMap(\.paraRangeTagArray)
            .flatMap { $0 }
    }

    static func paraRangeTagPayloads(from hwp: HwpFile) -> [Data] {
        paraRangeTags(from: hwp).map(\.rawPayload)
    }

    static func controlCounts(from hwp: HwpFile) -> [String: Int] {
        topLevelControls(from: hwp)
            .reduce(into: [String: Int]()) { result, ctrlId in
                result[controlName(ctrlId), default: 0] += 1
            }
    }

    static func allControlCounts(from hwp: HwpFile) -> [String: Int] {
        allControls(from: hwp)
            .reduce(into: [String: Int]()) { result, ctrlId in
                result[controlName(ctrlId), default: 0] += 1
            }
    }

    static func hyperlinks(from hwp: HwpFile) -> [HwpHyperlink] {
        topLevelControls(from: hwp)
            .compactMap { ctrlId -> HwpHyperlink? in
                guard case let .hyperLink(hyperlink) = ctrlId else {
                    return nil
                }
                return hyperlink
            }
    }

    static func genShapeObjects(from hwp: HwpFile) -> [HwpGenShapeObject] {
        topLevelControls(from: hwp)
            .compactMap { ctrlId -> HwpGenShapeObject? in
                guard case let .genShapeObject(object) = ctrlId else {
                    return nil
                }
                return object
            }
    }

    static func shapeControls(from hwp: HwpFile) -> [HwpShapeControl] {
        topLevelControls(from: hwp)
            .compactMap { fixtureShapeControl(from: $0) }
    }

    static func tables(from hwp: HwpFile) -> [HwpTable] {
        topLevelControls(from: hwp)
            .compactMap { ctrlId -> HwpTable? in
                guard case let .table(table) = ctrlId else {
                    return nil
                }
                return table
            }
    }

    static func columns(from hwp: HwpFile) -> [HwpColumn] {
        topLevelControls(from: hwp)
            .compactMap { ctrlId -> HwpColumn? in
                guard case let .column(column) = ctrlId else {
                    return nil
                }
                return column
            }
    }

    static func pageNumberPositions(from hwp: HwpFile) -> [HwpPageNumberPosition] {
        topLevelControls(from: hwp)
            .compactMap { ctrlId -> HwpPageNumberPosition? in
                guard case let .pageNumberPosition(position) = ctrlId else {
                    return nil
                }
                return position
            }
    }

    static func listControls(from hwp: HwpFile) -> [(kind: String, control: HwpListControl)] {
        allControls(from: hwp)
            .compactMap { ctrlId -> (kind: String, control: HwpListControl)? in
                switch ctrlId {
                case let .header(control):
                    ("header", control)
                case let .footer(control):
                    ("footer", control)
                case let .footnote(control):
                    ("footnote", control)
                case let .endnote(control):
                    ("endnote", control)
                default:
                    nil
                }
            }
    }

    static func sectionDefinitions(from hwp: HwpFile) -> [HwpSectionDef] {
        topLevelControls(from: hwp)
            .compactMap { ctrlId -> HwpSectionDef? in
                guard case let .section(sectionDef) = ctrlId else {
                    return nil
                }
                return sectionDef
            }
    }

    static func preservedControls(from hwp: HwpFile) -> [PreservedControl] {
        preservedControls(from: hwp.sectionArray)
    }

    static func preservedControls(from sections: [HwpSection]) -> [PreservedControl] {
        allControls(from: sections)
            .compactMap { ctrlId -> PreservedControl? in
                switch ctrlId {
                case let .notImplemented(header):
                    ("notImplemented", header)
                case let .unknown(header):
                    ("unknown", header)
                default:
                    nil
                }
            }
    }

    static func fieldControls(from hwp: HwpFile) -> [HwpFieldControl] {
        fieldControls(from: hwp.sectionArray)
    }

    static func fieldControls(from sections: [HwpSection]) -> [HwpFieldControl] {
        allControls(from: sections)
            .compactMap { ctrlId -> HwpFieldControl? in
                switch ctrlId {
                case let .memo(control),
                     let .revision(control),
                     let .field(control):
                    return control
                default:
                    return nil
                }
            }
    }

    static func otherControls(from hwp: HwpFile) -> [HwpOtherControl] {
        allControls(from: hwp)
            .compactMap { ctrlId -> HwpOtherControl? in
                switch ctrlId {
                case let .autoNumber(control),
                     let .newNumber(control),
                     let .pageHide(control),
                     let .pageCT(control),
                     let .form(control),
                     let .indexmark(control),
                     let .bookmark(control),
                     let .overlapping(control),
                     let .comment(control),
                     let .hiddenComment(control),
                     let .other(control):
                    return control
                default:
                    return nil
                }
            }
    }

    static func allGenShapeObjects(from hwp: HwpFile) -> [HwpGenShapeObject] {
        allControls(from: hwp)
            .compactMap { ctrlId -> HwpGenShapeObject? in
                guard case let .genShapeObject(object) = ctrlId else {
                    return nil
                }
                return object
            }
    }

    static func allParagraphs(from hwp: HwpFile) -> [HwpParagraph] {
        allParagraphs(from: hwp.sectionArray.flatMap(\.paragraph))
    }

    static func allControls(from hwp: HwpFile) -> [HwpCtrlId] {
        allControls(from: hwp.sectionArray)
    }

    private static func allControls(from sections: [HwpSection]) -> [HwpCtrlId] {
        allParagraphs(from: sections.flatMap(\.paragraph))
            .compactMap(\.ctrlHeaderArray)
            .flatMap { $0 }
    }

    private static func topLevelControls(from hwp: HwpFile) -> [HwpCtrlId] {
        hwp.sectionArray
            .flatMap(\.paragraph)
            .compactMap(\.ctrlHeaderArray)
            .flatMap { $0 }
    }

    private static func allParagraphs(from paragraphs: [HwpParagraph]) -> [HwpParagraph] {
        paragraphs.flatMap { paragraph in
            [paragraph] + nestedParagraphs(in: paragraph)
        }
    }

    private static func nestedParagraphs(in paragraph: HwpParagraph) -> [HwpParagraph] {
        paragraph.ctrlHeaderArray?
            .flatMap(nestedParagraphs(in:)) ?? []
    }

    private static func nestedParagraphs(in ctrlId: HwpCtrlId) -> [HwpParagraph] {
        if let control = fixtureShapeControl(from: ctrlId) {
            return nestedParagraphs(in: control.shapeComponentArray)
        }

        switch ctrlId {
        case let .table(table):
            return allParagraphs(from: table.cellArray.flatMap(\.paragraphArray))
        case let .genShapeObject(object):
            return nestedParagraphs(in: object.shapeComponentArray)
        case let .header(control),
             let .footer(control),
             let .footnote(control),
             let .endnote(control):
            return allParagraphs(from: control.listArray.flatMap(\.paragraphArray))
        default:
            return []
        }
    }

    private static func nestedParagraphs(in components: [HwpShapeComponent]) -> [HwpParagraph] {
        allParagraphs(from: components.flatMap(\.textBoxListArray).flatMap(\.paragraphArray))
    }

    // swiftlint:disable:next cyclomatic_complexity
    static func controlName(_ ctrlId: HwpCtrlId) -> String {
        switch ctrlId {
        case .table: "table"
        case .shape: "shape"
        case .line: "line"
        case .rectangle: "rectangle"
        case .ellipse: "ellipse"
        case .arc: "arc"
        case .polygon: "polygon"
        case .curve: "curve"
        case .equation: "equation"
        case .equationLegacy: "equationLegacy"
        case .picture: "picture"
        case .ole: "ole"
        case .container: "container"
        case .genShapeObject: "genShapeObject"
        case .section: "section"
        case .column: "column"
        case .pageNumberPosition: "pageNumberPosition"
        case .header: "header"
        case .footer: "footer"
        case .footnote: "footnote"
        case .endnote: "endnote"
        case .form: "form"
        case .autoNumber: "autoNumber"
        case .newNumber: "newNumber"
        case .pageHide: "pageHide"
        case .pageCT: "pageCT"
        case .indexmark: "indexmark"
        case .bookmark: "bookmark"
        case .overlapping: "overlapping"
        case .comment: "comment"
        case .hiddenComment: "hiddenComment"
        case .other: "other"
        case .hyperLink: "hyperLink"
        case .memo: "memo"
        case .revision: "revision"
        case .field: "field"
        case .notImplemented: "notImplemented"
        case .unknown: "unknown"
        }
    }
}

private func fixtureShapeControl(from ctrlId: HwpCtrlId) -> HwpShapeControl? {
    switch ctrlId {
    case let .shape(control),
         let .line(control),
         let .rectangle(control),
         let .ellipse(control),
         let .arc(control),
         let .polygon(control),
         let .curve(control),
         let .equation(control),
         let .equationLegacy(control),
         let .picture(control),
         let .ole(control),
         let .container(control):
        control
    default:
        nil
    }
}
