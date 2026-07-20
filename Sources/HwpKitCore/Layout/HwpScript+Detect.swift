import Foundation

public extension HwpScript {
    static func detect(from scalar: Unicode.Scalar) -> HwpScript {
        switch scalar.value {
        case 0xAC00 ... 0xD7AF,
             0x1100 ... 0x11FF,
             0x3130 ... 0x318F,
             // 한글 자모 확장 A/B·반각 자모도 한글 슬롯이다 (R33 #2)
             0xA960 ... 0xA97F,
             0xD7B0 ... 0xD7FF,
             0xFFA0 ... 0xFFDC:
            .korean
        case 0x4E00 ... 0x9FFF,
             0x3400 ... 0x4DBF,
             // CJK 호환 한자·비-BMP 확장 (R33 #2)
             0xF900 ... 0xFAFF,
             0x20000 ... 0x2FA1F:
            .chinese
        case 0x3040 ... 0x309F,
             0x30A0 ... 0x30FF:
            .japanese
        case 0x0370 ... 0x03FF,
             0x0400 ... 0x04FF,
             // RTL·복합 문자계 (히브리/아랍+보충·표현형/타이/데바나가리)는
             // 영문이 아니라 '기타 언어' 슬롯이다 (R33 #2)
             0x0590 ... 0x05FF,
             0x0600 ... 0x077F,
             0x08A0 ... 0x08FF,
             0x0900 ... 0x097F,
             0x0E00 ... 0x0E7F,
             0xFB50 ... 0xFDFF,
             0xFE70 ... 0xFEFF:
            .etc
        // 인용부호는 한글도 라틴 폭으로 조판한다 (noori 실물: '…부호'+')' 밀착)
        case 0x2018 ... 0x201F:
            .english
        case 0x2000 ... 0x206F,
             0x2070 ... 0x209F,
             0x2100 ... 0x214F,
             0x2190 ... 0x21FF,
             0x2200 ... 0x22FF,
             0x2500 ... 0x257F,
             0xE000 ... 0xF8FF:
            .symbol
        default:
            .english
        }
    }
}
