public enum HwpCommonCtrlId: UInt32, HwpPrimitive, CaseIterable {
    /**tbl */
    case table = 1_952_607_264

    /** $lin */
    case line = 611_084_654
    /** $lec */
    case rectangle = 611_476_835
    /** $ell */
    case ellipse = 610_626_668
    /** $arc */
    case arc = 610_366_051
    /** $pol */
    case polygon = 611_348_332
    /** $cur */
    case curve = 610_497_906

    /** eqed */
    case equation = 1_701_930_340
    /** equd */
    case equationLegacy = 1_701_934_436
    /** $pic */
    case picture = 611_346_787
    /** $ole */
    case ole = 611_282_021
    /** $con */
    case container = 610_496_366
    /**
     gso
     NOTE: (@hahnlee) 공개된 문서에서 자세히 설명되어 있지는 않으나, 개채요소 설명에 따라 GenShapeObject로 추측됨
     */
    case genShapeObject = 1_735_618_336
}
