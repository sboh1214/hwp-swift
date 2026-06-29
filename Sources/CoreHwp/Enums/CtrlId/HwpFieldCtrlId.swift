public enum HwpFieldCtrlId: UInt32, HwpPrimitive, CaseIterable {
    case unknown = 628_452_971
    case date = 610_563_173
    case docDate = 627_336_308
    case path = 628_121_972
    case bookmark = 627_207_531
    case mailMerge = 627_928_423
    case crossRef = 628_650_598
    case formula = 627_469_685
    case clickHere = 627_272_811
    case summary = 628_321_650
    case userInfo = 628_454_258
    case hyperLink = 627_600_491
    case revisionSign = 628_320_615
    case revisionDelete = 623_192_676
    case revisionAttach = 623_192_673
    case revisionClipping = 623_192_643
    case revisionSawtooth = 623_192_659
    case revisionThinking = 623_192_660
    case revisionPraise = 623_192_656
    case revisionLine = 623_192_652
    case revisionSimpleChange = 623_192_675
    case revisionHyperLink = 623_192_680
    case revisionLineAttach = 623_192_641
    case revisionLineLink = 623_192_681
    case revisionLineRansfer = 623_192_692
    case revisionRightMove = 623_192_690
    case revisionLeftMove = 623_191_660
    case revisionTransfer = 623_192_686
    case revisionSimpleInsert = 623_192_677
    case revisionSplit = 628_322_412
    case revisionChange = 623_209_842
    case memo = 623_209_829
    case privateInfoSecurity = 627_273_842
    case tableOfContents = 628_387_683
}

public extension HwpFieldCtrlId {
    var isRevision: Bool {
        switch self {
        case .revisionSign,
             .revisionDelete,
             .revisionAttach,
             .revisionClipping,
             .revisionSawtooth,
             .revisionThinking,
             .revisionPraise,
             .revisionLine,
             .revisionSimpleChange,
             .revisionHyperLink,
             .revisionLineAttach,
             .revisionLineLink,
             .revisionLineRansfer,
             .revisionRightMove,
             .revisionLeftMove,
             .revisionTransfer,
             .revisionSimpleInsert,
             .revisionSplit,
             .revisionChange:
            true
        default:
            false
        }
    }
}
