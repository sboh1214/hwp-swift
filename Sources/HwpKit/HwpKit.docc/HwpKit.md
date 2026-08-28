# ``HwpKit``

HWP 문서를 표시하는 SwiftUI 뷰어 컴포넌트 모음입니다.

## Overview

HwpKit은 CoreHwp 파서와 조판·렌더링 계층인 HwpKitCore·HwpKitNative를
SwiftUI에서 사용할 수 있도록 묶은 공개 API 계층입니다. 문서 뷰·툴바·검색
바 등 호스트 앱의 레이아웃에 넣는 컴포넌트를 제공하며, 저장 패널·인쇄·전역
단축키 같은 앱 전역 UI와 정책은 호스트 앱이 맡습니다.

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

큰 문서는 ``HwpDocumentLoader/loadUpdates(from:)``에서 중간 스냅샷을 받아
첫 페이지부터 표시할 수 있습니다. 각 컴포넌트의 사용 예는 저장소의
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
