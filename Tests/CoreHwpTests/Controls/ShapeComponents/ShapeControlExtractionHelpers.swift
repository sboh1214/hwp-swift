@testable import CoreHwp

func shapeControl(from ctrlId: HwpCtrlId?) -> HwpShapeControl? {
    switch ctrlId {
    case let .shape(control),
         let .line(control),
         let .rectangle(control),
         let .ellipse(control),
         let .arc(control),
         let .polygon(control),
         let .curve(control),
         let .equation(control),
         let .equationLegacy(control),
         let .picture(control),
         let .ole(control),
         let .container(control):
        control
    default:
        nil
    }
}
