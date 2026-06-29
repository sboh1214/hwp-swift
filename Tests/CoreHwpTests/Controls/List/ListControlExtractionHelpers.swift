@testable import CoreHwp

func listControlFromHeader(_ ctrlId: HwpCtrlId) -> HwpListControl? {
    guard case let .header(control) = ctrlId else { return nil }
    return control
}

func listControlFromFooter(_ ctrlId: HwpCtrlId) -> HwpListControl? {
    guard case let .footer(control) = ctrlId else { return nil }
    return control
}

func listControlFromFootnote(_ ctrlId: HwpCtrlId) -> HwpListControl? {
    guard case let .footnote(control) = ctrlId else { return nil }
    return control
}

func listControlFromEndnote(_ ctrlId: HwpCtrlId) -> HwpListControl? {
    guard case let .endnote(control) = ctrlId else { return nil }
    return control
}
