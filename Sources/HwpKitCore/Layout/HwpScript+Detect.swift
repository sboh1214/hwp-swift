import Foundation

public extension HwpScript {
    static func detect(from scalar: Unicode.Scalar) -> HwpScript {
        switch scalar.value {
        case 0xAC00 ... 0xD7AF,
             0x1100 ... 0x11FF,
             0x3130 ... 0x318F:
            .korean
        case 0x4E00 ... 0x9FFF,
             0x3400 ... 0x4DBF:
            .chinese
        case 0x3040 ... 0x309F,
             0x30A0 ... 0x30FF:
            .japanese
        case 0x0370 ... 0x03FF,
             0x0400 ... 0x04FF:
            .etc
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
