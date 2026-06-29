/**
 ‘본문’의 데이터 레코드
 */
enum HwpSectionTag: UInt32, HwpPrimitive, CaseIterable {
    case paraHeader = 66
    case paraText = 67
    case paraCharShape = 68
    case paraLineSeg = 69
    case paraRangeTag = 70
    case ctrlHeader = 71
    case listHeader = 72
    case pageDef = 73
    case footnoteShape = 74
    case pageBorderFill = 75
    case shapeComponent = 76
    case table = 77
    case shapeComponentLine = 78
    case shapeComponentRectangle = 79
    case shapeComponentEllipse = 80
    case shapeComponentArc = 81
    case shapeComponentPolygon = 82
    case shapeComponentCurve = 83
    case shapeComponentOle = 84
    case shapeComponentPicture = 85
    case shapeComponentContainer = 86
    case ctrlData = 87
    case eqEdit = 88
    case reserved = 89
    case shapeComponentTextart = 90
    case formObject = 91
    case memoShape = 92
    case memoList = 93
    case chartData = 95
    case videoData = 98
    case shapeComponentUnknown = 115
}
