/** 테두리선 종류 */
public enum HwpBorderType: Int, HwpPrimitive {
    /** 선 없음 */
    case none = 0
    /** 실선 */
    case line = 1
    /** 긴 점선 */
    case longDotLine = 2
    /** 점선 */
    case dotLine = 3
    /** -.-.-.-. */
    case dashDot = 4
    /** -..-..-.. */
    case dashDotDot = 5
    /** Dash보다 긴 선분의 반복 */
    case longDash = 6
    /** Dot보다 큰 동그라미의 반복 */
    case circle = 7
    /** 2중선 */
    case doubleLine = 8
    /** 가는선 + 굵은선 2중선 */
    case thinThickDoubleLine = 9
    /** 굵은선 + 가는선 2중선 */
    case thickThinDoubleLine = 10
    /** 가는선 + 굵은선 + 가는선 3중선 */
    case thinThickThinTripleLine = 11
    /** 물결 */
    case wave = 12
    /** 물결 2중선 */
    case doubleWave = 13
    /** 두꺼운 3D */
    case thick3D = 14
    /** 두꺼운 3D(광원 반대) */
    case thick3DReverse = 15
    /** 3D 단선 */
    case single3D = 16
    /** 3D 단선(광원 반대) */
    case single3DReverse = 17
}
