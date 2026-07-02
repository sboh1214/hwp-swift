@preconcurrency import CoreHwp
import Foundation

/// Eager O(1) lookup index over `CoreHwp.HwpFile.docInfo.idMappings`.
public struct HwpIndex: Sendable {
    public let charShapes: [UInt32: CoreHwp.HwpCharShape]
    public let paraShapes: [UInt32: CoreHwp.HwpParaShape]
    public let borderFills: [UInt32: CoreHwp.HwpBorderFill]
    public let tabDefs: [UInt32: CoreHwp.HwpTabDef]
    public let styles: [UInt32: CoreHwp.HwpStyle]
    public let bullets: [UInt32: CoreHwp.HwpBullet]
    public let numberings: [UInt32: CoreHwp.HwpNumbering]
    public let binData: [UInt32: CoreHwp.HwpBinData]

    // HWP has one face-name list per script slot (Korean/English/Chinese/Japanese/Etc/Symbol/User).
    public let faceNamesKorean: [UInt32: CoreHwp.HwpFaceName]
    public let faceNamesEnglish: [UInt32: CoreHwp.HwpFaceName]
    public let faceNamesChinese: [UInt32: CoreHwp.HwpFaceName]
    public let faceNamesJapanese: [UInt32: CoreHwp.HwpFaceName]
    public let faceNamesEtc: [UInt32: CoreHwp.HwpFaceName]
    public let faceNamesSymbol: [UInt32: CoreHwp.HwpFaceName]
    public let faceNamesUser: [UInt32: CoreHwp.HwpFaceName]

    init(
        charShapes: [UInt32: CoreHwp.HwpCharShape],
        paraShapes: [UInt32: CoreHwp.HwpParaShape],
        borderFills: [UInt32: CoreHwp.HwpBorderFill],
        tabDefs: [UInt32: CoreHwp.HwpTabDef],
        styles: [UInt32: CoreHwp.HwpStyle],
        bullets: [UInt32: CoreHwp.HwpBullet],
        numberings: [UInt32: CoreHwp.HwpNumbering],
        binData: [UInt32: CoreHwp.HwpBinData],
        faceNamesKorean: [UInt32: CoreHwp.HwpFaceName],
        faceNamesEnglish: [UInt32: CoreHwp.HwpFaceName],
        faceNamesChinese: [UInt32: CoreHwp.HwpFaceName],
        faceNamesJapanese: [UInt32: CoreHwp.HwpFaceName],
        faceNamesEtc: [UInt32: CoreHwp.HwpFaceName],
        faceNamesSymbol: [UInt32: CoreHwp.HwpFaceName],
        faceNamesUser: [UInt32: CoreHwp.HwpFaceName]
    ) {
        self.charShapes = charShapes
        self.paraShapes = paraShapes
        self.borderFills = borderFills
        self.tabDefs = tabDefs
        self.styles = styles
        self.bullets = bullets
        self.numberings = numberings
        self.binData = binData
        self.faceNamesKorean = faceNamesKorean
        self.faceNamesEnglish = faceNamesEnglish
        self.faceNamesChinese = faceNamesChinese
        self.faceNamesJapanese = faceNamesJapanese
        self.faceNamesEtc = faceNamesEtc
        self.faceNamesSymbol = faceNamesSymbol
        self.faceNamesUser = faceNamesUser
    }

    public init(from file: CoreHwp.HwpFile) {
        let idMappings = file.docInfo.idMappings
        charShapes = Self.makeIndex(idMappings.charShapeArray)
        paraShapes = Self.makeIndex(idMappings.paraShapeArray)
        borderFills = Self.makeIndex(idMappings.borderFillArray)
        tabDefs = Self.makeIndex(idMappings.tabDefArray)
        styles = Self.makeIndex(idMappings.styleArray)
        bullets = Self.makeIndex(idMappings.bulletArray)
        numberings = Self.makeIndex(idMappings.numberingArray)
        binData = Self.makeIndex(idMappings.binDataArray)
        faceNamesKorean = Self.makeIndex(idMappings.faceNameKoreanArray)
        faceNamesEnglish = Self.makeIndex(idMappings.faceNameEnglishArray)
        faceNamesChinese = Self.makeIndex(idMappings.faceNameChineseArray)
        faceNamesJapanese = Self.makeIndex(idMappings.faceNameJapaneseArray)
        faceNamesEtc = Self.makeIndex(idMappings.faceNameEtcArray)
        faceNamesSymbol = Self.makeIndex(idMappings.faceNameSymbolArray)
        faceNamesUser = Self.makeIndex(idMappings.faceNameUserArray)
    }

    public func charShape(id: UInt32) -> CoreHwp.HwpCharShape? {
        charShapes[id]
    }

    public func paraShape(id: UInt32) -> CoreHwp.HwpParaShape? {
        paraShapes[id]
    }

    public func borderFill(id: UInt32) -> CoreHwp.HwpBorderFill? {
        borderFills[id]
    }

    public func tabDef(id: UInt32) -> CoreHwp.HwpTabDef? {
        tabDefs[id]
    }

    public func style(id: UInt32) -> CoreHwp.HwpStyle? {
        styles[id]
    }

    public func bullet(id: UInt32) -> CoreHwp.HwpBullet? {
        bullets[id]
    }

    public func numbering(id: UInt32) -> CoreHwp.HwpNumbering? {
        numberings[id]
    }

    public func binDataEntry(id: UInt32) -> CoreHwp.HwpBinData? {
        binData[id]
    }

    public func faceNameKorean(id: UInt32) -> CoreHwp.HwpFaceName? {
        faceNamesKorean[id]
    }

    public func faceNameEnglish(id: UInt32) -> CoreHwp.HwpFaceName? {
        faceNamesEnglish[id]
    }

    public func faceNameChinese(id: UInt32) -> CoreHwp.HwpFaceName? {
        faceNamesChinese[id]
    }

    public func faceNameJapanese(id: UInt32) -> CoreHwp.HwpFaceName? {
        faceNamesJapanese[id]
    }

    public func faceNameEtc(id: UInt32) -> CoreHwp.HwpFaceName? {
        faceNamesEtc[id]
    }

    public func faceNameSymbol(id: UInt32) -> CoreHwp.HwpFaceName? {
        faceNamesSymbol[id]
    }

    public func faceNameUser(id: UInt32) -> CoreHwp.HwpFaceName? {
        faceNamesUser[id]
    }

    public func faceName(for faceId: UInt32, script: HwpScript) -> CoreHwp.HwpFaceName? {
        switch script {
        case .korean:
            faceNamesKorean[faceId]
        case .english:
            faceNamesEnglish[faceId]
        case .chinese:
            faceNamesChinese[faceId]
        case .japanese:
            faceNamesJapanese[faceId]
        case .etc:
            faceNamesEtc[faceId]
        case .symbol:
            faceNamesSymbol[faceId]
        case .user:
            faceNamesUser[faceId]
        }
    }
}

private extension HwpIndex {
    static func makeIndex<T>(_ array: [T]) -> [UInt32: T] {
        Dictionary(uniqueKeysWithValues: array.enumerated().map { (UInt32($0.offset), $0.element) })
    }
}
