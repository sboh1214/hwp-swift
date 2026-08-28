# ``HwpKitNative``

AppKit·UIKit 기반의 HWP 문서 렌더링 계층입니다.

## Overview

HwpKitNative는 HwpKitCore가 만든 페인트 목록을 AppKit·UIKit 화면·PDF·비트맵에
렌더링하는 계층입니다. 파싱과 조판을 비동기로 수행하는
``HwpDocumentActor``, CALayer 기반 페이지 렌더러 ``HwpPageLayer``, 화면과
같은 페인트 목록을 사용하는
``HwpPDFRenderer``·``HwpPageBitmapRenderer``·``HwpPageThumbnailRenderer``,
그리고 이미지 디코딩 캐시 ``HwpImageCache``를 제공합니다.

SwiftUI 앱은 보통 `HwpKit`을 사용합니다. 이 모듈은 SwiftUI 없이
`HwpDocumentNSView`나 `HwpDocumentUIView`를 직접 다루거나, 뷰 없이 페이지를
렌더링할 때 적합합니다.

## Topics

### 문서 로드·연결

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
