public enum HwpOtherCtrlId: UInt32, HwpPrimitive, CaseIterable {
    case section = 1_936_024_420
    case column = 1_668_246_628
    case header = 1_751_474_532
    case footer = 1_718_579_060
    case footnote = 1_718_493_216
    case endnote = 1_701_716_000
    case form = 1_718_579_821
    case autoNumber = 1_635_020_399
    case newNumber = 1_853_320_815
    case pageHide = 1_885_825_124
    // 한컴 control ID `pgct`; 공개 문서의 한국어 명칭이 불명확해 원시 ID 기반 이름을 유지한다.
    case pageCT = 1_885_823_860
    case pageNumberPosition = 1_885_826_672
    case indexmark = 1_768_192_109
    case bookmark = 1_651_469_165
    case overlapping = 1_952_673_907
    case comment = 1_952_740_724
    case hiddenComment = 1_952_673_140
}
