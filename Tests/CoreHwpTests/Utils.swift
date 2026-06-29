import CoreHwp
import Foundation

func openHwp(_ location: String, _ name: String) throws -> HwpFile {
    try HwpFile(fromPath: hwpURL(location, name).path)
}

func createHwp(_ location: String, _ name: String) throws -> (HwpFile, HwpFile) {
    let this = HwpFile()
    let official = try HwpFile(fromPath: hwpURL(location, name).path)
    return (this, official)
}

func hwpURL(_ location: String, _ name: String) -> URL {
    let colocated = URL(fileURLWithPath: location)
        .deletingLastPathComponent()
        .appendingPathComponent(name + ".hwp")
    if FileManager.default.fileExists(atPath: colocated.path) {
        return colocated
    }

    return testsRoot(from: location)
        .appendingPathComponent("Fixtures")
        .appendingPathComponent(name)
        .appendingPathComponent("document.hwp")
}

func testsRoot(from location: String) -> URL {
    var url = URL(fileURLWithPath: location).deletingLastPathComponent()
    while url.lastPathComponent != "CoreHwpTests", url.path != "/" {
        url.deleteLastPathComponent()
    }
    return url
}

func concatenatedData(_ chunks: Data...) -> Data {
    chunks.reduce(into: Data()) { data, chunk in
        data.append(chunk)
    }
}
