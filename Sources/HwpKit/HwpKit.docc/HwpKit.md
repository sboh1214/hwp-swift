# ``HwpKit``

HWP 문서를 표시하는 SwiftUI 뷰어 컴포넌트 모음입니다.

## Overview

HwpKit은 CoreHwp 파서 위에 조판·렌더 계층(HwpKitCore·HwpKitNative)을
얹은 SwiftUI 파사드입니다. 문서 뷰·툴바·검색 바처럼 호스트가 놓은 자리만
차지하는 컴포넌트를 제공하고, 저장 패널·인쇄·전역 단축키 같은 호스트
chrome과 정책은 앱 몫으로 남깁니다.

문서 모델(`HwpDocument`)과 검색 세션(`HwpSearchController`) 등은
HwpKitCore의 타입이므로 `HwpKit`과 `HwpKitCore`를 함께 import합니다.

```swift
import HwpKit
import HwpKitCore
import SwiftUI

struct ViewerView: View {
    let url: URL
    @State private var document: HwpDocument?

    var body: some View {
        Group {
            if let document {
                HwpDocumentView(document: document)
            } else {
                ProgressView()
            }
        }
        .task {
            document = try? await HwpDocumentLoader().load(from: url)
        }
    }
}
```

큰 문서는 ``HwpDocumentLoader/loadUpdates(from:)``로 첫 페이지가 확정되는
즉시 그리기 시작할 수 있습니다. 모든 컴포넌트의 실제 배선 예시는 저장소의
`Sample/HwpSwiftSample`을 참고하십시오.

## Topics

### 시작하기

- ``HwpDocumentLoader``
- ``HwpDocumentView``
- ``HwpDocumentLoadError``
- ``HwpUnsupportedDocumentKind``

### 툴바·탐색 컴포넌트

- ``HwpDocumentToolbar``
- ``HwpPageNavigator``
- ``HwpZoomControls``

### 문서 내 검색

- ``HwpSearchBar``
- ``HwpSearchNavigator``

### 내보내기·축소판

- ``HwpPDFExporter``
- ``HwpPDFExportError``
- ``HwpPageThumbnails``
- ``HwpThumbnailError``
