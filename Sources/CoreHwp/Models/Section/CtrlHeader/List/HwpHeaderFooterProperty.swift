import Foundation

/**
 머리말/꼬리말이 적용될 범위 (표 141 bit 0-1)
 */
public enum HwpHeaderFooterApplyScope: Int, HwpPrimitive {
    /** 양 쪽 */
    case bothPages = 0
    /** 짝수 쪽만 */
    case evenPagesOnly = 1
    /** 홀수 쪽만 */
    case oddPagesOnly = 2
}

public extension HwpListControl {
    /**
     머리말/꼬리말 속성 (표 140)

     머리말/꼬리말 컨트롤 헤더 payload는 ctrl id(4 byte) 뒤에 속성 UINT32가 온다.
     표 140의 나머지 필드(텍스트 영역 폭/높이, 레벨 참조)는 실제 파일에서
     리스트 헤더 쪽에 기록된다 (header-footer 픽스처 바이트 검증). payload가
     짧으면 nil.
     */
    var headerFooterPropertyRawValue: UInt32? {
        try? header.rawPayload.readLittleEndianUInt32(at: 4)
    }

    /** 머리말/꼬리말 적용 범위 (표 141 bit 0-1). 해석할 수 없으면 양쪽. */
    var headerFooterApplyScope: HwpHeaderFooterApplyScope {
        guard let rawValue = headerFooterPropertyRawValue else { return .bothPages }
        return HwpHeaderFooterApplyScope(rawValue: Int(rawValue & 0b11)) ?? .bothPages
    }
}
