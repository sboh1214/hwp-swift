import HwpKit
import HwpKitCore
import SwiftUI

/// PDF 내보내기·인쇄 상태 기계 (#74·#126) — 진행률·취소·목적지 인계·임시 파일
/// 수명이 전부 여기 모여 있다. 바닥 조각(저장 패널용 `FileDocument`, 플랫폼
/// 인쇄, iPad 앵커)은 `PDFExportSupport.swift`에 있고, 이 파일은 그것들을
/// **언제** 부르는지를 정한다.
///
/// 관측 가능한 모델 타입으로 뽑지 않고 `ContentView`의 extension으로 나눈
/// 이유 (#140): 이 흐름의 규약이 전부 SwiftUI **갱신 주기**에 걸려 있다 —
/// "두 모달을 같은 주기에 겹치면 두 번째 표시가 유실된다"와, 시트가 뜬 적이
/// 없을 때 `Task { @MainActor in ... }`로 한 주기를 건너뛰는 보정이 그것이다.
/// 상태를 `@Observable` 클래스로 옮기면 쓰기가 즉시 관측자를 깨워 그 "주기"의
/// 경계가 달라지고, `onDismiss`·`onAppear` 경로에서만 읽히는 값들(
/// `exportSheetDidPresent`·`pendingDestination`·`pendingError`)은 body에서
/// 읽히지 않아 추적 대상에서도 빠진다. extension은 `@State` 소유권과 갱신
/// 주기를 하나도 바꾸지 않는다.
///
/// 모달 3종(진행 시트·저장 패널·오류 알림)이 걸리는 자리는 그대로
/// `ContentView`의 **루트 body**다 — 문서가 바뀌어도 살아남아야 하기 때문이다
/// (`ContentView.swift`의 그 주석).
extension ContentView {
    var exportProgressSheet: some View {
        VStack(spacing: 16) {
            ProgressView(value: exportProgress ?? 0) {
                Text("PDF 만드는 중…")
            }
            .frame(width: 220)
            Button("취소") { exportTask?.cancel() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .onAppear { exportSheetDidPresent = true }
    }

    /// 진행 표시를 끝낸다. 시트가 떠 있었으면 `onDismiss`가 뒤를 잇고, 뜬 적이
    /// **없으면** 그 콜백이 영영 오지 않으므로 직접 이어 간다. 다음 주기로
    /// 넘기는 것은 "모달을 같은 갱신 주기에 겹치지 않는다"는 이 파일의 규약을
    /// 시트가 없었을 때도 지키기 위해서다.
    private func finishExportProgress() {
        let wasPresented = exportSheetDidPresent
        exportSheetDidPresent = false
        exportProgress = nil
        guard !wasPresented else { return }
        Task { @MainActor in presentPendingDestination() }
    }

    /// 임시 PDF를 지우고 참조를 놓는다. 이 앱은 내보낼 때마다 새 UUID 파일을
    /// 만들므로, 지우지 않으면 1,030쪽짜리가 세션 내내 쌓인다.
    func discardExportedPDF() {
        if let exportedPDF {
            try? FileManager.default.removeItem(at: exportedPDF)
        }
        exportedPDF = nil
        exportedPDFIsHandedOff = false
    }

    /// 이전 실행이 남긴 임시 PDF를 거둔다. 목적지 UI에 넘긴 파일은 그 완료
    /// 콜백이 지우지만 scene이 파괴되면 그 콜백이 오지 않으므로, 그 잔해까지
    /// 거둬야 "넘긴 파일은 지우지 않는다"가 누수로 퇴화하지 않는다.
    ///
    /// **이번 실행에서 만든 것은 건드리지 않는다**: `WindowGroup`은 창마다 이
    /// 뷰를 만들어서, 전부 지우면 나중에 연 창이 먼저 창의 내보내기를 깬다.
    static func removeStaleExports() {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(
            at: manager.temporaryDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        for entry in entries
            where entry.lastPathComponent.hasPrefix(Self.exportFilePrefix)
        {
            let modified = try? entry.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            guard let modified, modified < Self.processStart else { continue }
            try? manager.removeItem(at: entry)
        }
    }

    func exportPDF(document: HwpDocument, then destination: PDFDestination) {
        exportTask?.cancel()
        discardExportedPDF()
        exportError = nil
        exportProgress = 0
        exportedName = Self.exportFileName(for: document)
        // 파일명은 UUID로 짓는다. 제목에서 뽑으면 `WindowGroup`의 두 창이 같은
        // 경로를 써, 한쪽 저장 패널이 열려 있는 사이 다른 쪽 내보내기가 그 파일을
        // 갈아 치운다 (다른 문서가 저장된다). 긴 제목의 파일명 한도(255바이트)
        // 문제도 함께 사라진다.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Self.exportFilePrefix)\(UUID().uuidString).pdf")
        exportTask = Task {
            do {
                try await HwpPDFExporter().export(document: document, to: url) { progress in
                    Task { @MainActor in
                        // 진행 중일 때만 갱신 — 취소 후 늦게 도착한 보고가 시트를
                        // 되살리지 않게 한다.
                        if exportProgress != nil {
                            exportProgress = progress.fractionCompleted
                        }
                    }
                }
                // 취소된 뒤에 끝난 결과는 주인이 없다 — 뷰가 사라졌으면 저장·인쇄
                // 콜백도, 다음 내보내기도 이 파일을 지워 주지 않는다. 렌더러의
                // 마지막 취소 확인은 파일을 옮기기 **전**이라 이 창이 남는다.
                guard !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                await MainActor.run {
                    exportedPDF = url
                    // 시트를 닫고, 저장 패널·인쇄는 그 뒤가 이어받는다 (시트가
                    // 떴으면 onDismiss가, 뜬 적이 없으면 finishExportProgress가).
                    pendingDestination = destination
                    finishExportProgress()
                }
            } catch HwpPDFExportError.cancelled {
                await MainActor.run { finishExportProgress() }
            } catch {
                await MainActor.run {
                    // 시트를 닫는 것과 알림을 띄우는 것을 같은 갱신 주기에 겹치면
                    // 두 번째가 유실된다 — 저장·인쇄와 같이 onDismiss로 미룬다.
                    pendingError = error.localizedDescription
                    finishExportProgress()
                }
            }
        }
    }

    /// 진행 시트가 완전히 닫힌 뒤 저장 패널·인쇄를 띄운다. 취소로 닫힌
    /// 경우에는 `pendingDestination`이 비어 있어 아무 일도 하지 않는다.
    func presentPendingDestination() {
        if let failure = pendingError {
            pendingError = nil
            exportError = failure
            return
        }
        guard let destination = pendingDestination, let url = exportedPDF else { return }
        pendingDestination = nil
        // 이 시점부터 파일 소유권은 목적지 UI에 있다 — 창이 닫혀도 그쪽이 다
        // 쓸 때까지 남긴다. 표시가 곧바로 실패하면 아래에서 되돌린다.
        exportedPDFIsHandedOff = true
        switch destination {
        case .save:
            showSavePanel = true
        case .print:
            let cleanup: @Sendable (String?) -> Void = { reason in
                Task { @MainActor in
                    discardExportedPDF()
                    // 인쇄 UI가 닫힌 뒤라 진행 시트와 겹치지 않는다 (모달을 같은
                    // 갱신 주기에 겹치면 알림이 유실된다는 이 파일의 규약).
                    if let reason {
                        exportError = reason
                    }
                }
            }
            #if os(macOS)
                let failure = HwpSamplePrinter.print(
                    pdfAt: url, jobName: exportedName, onFinish: cleanup
                )
            #else
                let failure = HwpSamplePrinter.print(
                    pdfAt: url, jobName: exportedName, anchor: printAnchor.view, onFinish: cleanup
                )
            #endif
            if let failure {
                exportError = failure
                discardExportedPDF()
            }
        }
    }

    /// 문서 제목을 파일 이름으로 쓰되 경로 구분자는 지운다.
    private static func exportFileName(for document: HwpDocument) -> String {
        let title = document.metadata.title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-") ?? ""
        let clipped = Self.clippedToFilenameLimit(title)
        return clipped.isEmpty ? "document" : clipped
    }

    /// 파일명 성분 한도(255바이트)에서 확장자 몫을 빼고 **UTF-8 바이트로** 자른다.
    /// 문자 수로 자르면 한도를 못 지킨다 — 결합 이모지 하나가 25바이트라 80자가
    /// 2,000바이트다. 자르는 단위는 Character라 자소가 쪼개지지 않는다.
    private static func clippedToFilenameLimit(_ title: String) -> String {
        let limit = 255 - ".pdf".utf8.count
        var clipped = ""
        var bytes = 0
        for character in title {
            let size = String(character).utf8.count
            guard bytes + size <= limit else { break }
            clipped.append(character)
            bytes += size
        }
        return clipped
    }
}
