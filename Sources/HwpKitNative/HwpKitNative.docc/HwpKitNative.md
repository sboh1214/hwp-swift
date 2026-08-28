# ``HwpKitNative``

AppKit·UIKit 위에서 HWP 문서를 그리는 플랫폼 브릿지입니다.

## Overview

HwpKitNative는 HwpKitCore의 paint list를 실제 화면·PDF·비트맵으로 옮기는
계층입니다. 파싱과 조판을 백그라운드로 보내는 ``HwpDocumentActor``,
CALayer 기반 페이지 렌더러 ``HwpPageLayer``, 화면과 같은 조판을 쓰는
``HwpPDFRenderer``·``HwpPageBitmapRenderer``·``HwpPageThumbnailRenderer``,
그리고 이미지 디코드 캐시 ``HwpImageCache``를 제공합니다.

대부분의 앱은 이 모듈을 직접 쓰지 않고 SwiftUI 파사드인 `HwpKit`을
사용합니다. 이 모듈을 직접 쓰는 경우는 SwiftUI 없이 자체 뷰 계층을
만들거나(macOS의 `HwpDocumentNSView`, iOS의 `HwpDocumentUIView`), 뷰 없이
페이지를 오프스크린으로 렌더링할 때입니다.

## Topics

### 문서 로드·브릿지

- ``HwpDocumentActor``
- ``HwpDocumentSnapshot``

### 렌더링

- ``HwpPageLayer``
- ``HwpPDFRenderer``
- ``HwpPDFRenderError``
- ``HwpPageBitmapRenderer``
- ``HwpPageBitmapRenderError``
- ``HwpPageThumbnailRenderer``

### 이미지 파이프라인

- ``HwpPageImageProvider``
- ``HwpImageCache``
- ``HwpCachedImage``
- ``HwpUnresolvedImagePolicy``
