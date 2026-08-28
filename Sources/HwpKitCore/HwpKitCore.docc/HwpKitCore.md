# ``HwpKitCore``

HWP 문서의 조판·페인트를 담당하는 플랫폼 중립 렌더 코어입니다.

## Overview

HwpKitCore는 CoreHwp가 읽은 `HwpFile`을 CoreText·CoreGraphics 기반으로
조판해 페이지 단위 표현(``HwpDocument`` → ``HwpPage`` → paint list)으로
바꿉니다. AppKit·UIKit·SwiftUI를 import하지 않는 계층이므로 화면 밖
렌더링(비트맵·PDF·검색 인덱싱)에도 그대로 쓸 수 있습니다.

SwiftUI 앱이라면 보통 HwpKit의 `HwpDocumentLoader`가 이 모듈의
``HwpDocument``를 만들어 줍니다. 이 모듈을 직접 쓰는 경우는 검색 세션
(``HwpSearchController``)·선택(``HwpSelectionController``)·폰트 해석
(``HwpFontResolver``)을 제어하거나, 커스텀 렌더러를 만들 때입니다.

## Topics

### 문서 모델

- ``HwpDocument``
- ``HwpDocumentMetadata``
- ``HwpPage``
- ``HwpOutlineItem``
- ``HwpUnsupportedElement``
- ``HwpImageStore``
- ``HwpZoomFit``
- ``HwpPDFExportProgress``

### 문서 내 검색

- ``HwpSearchController``
- ``HwpSearchPhase``
- ``HwpSearchQuery``
- ``HwpSearchOptions``
- ``HwpSearchMatch``
- ``HwpSearchSnippet``
- ``HwpSearchHighlightStyle``
- ``HwpTextSearcher``

### 선택·히트 테스트

- ``HwpSelectionController``
- ``HwpGeometryChange``
- ``HwpSelectionGeometry``
- ``HwpTextSelection``
- ``HwpTextPosition``
- ``HwpHitTester``

### 폰트

- ``HwpFontResolver``
- ``HwpFontMap``
- ``HwpScript``
- ``HwpInstalledHancomFonts``

### 접근성

- ``HwpAccessibilityContent``
- ``HwpAccessibilityUnit``

### 조판·페인트 엔진 (고급)

- ``HwpPaginator``
- ``HwpIndex``
- ``HwpPaintList``
- ``HwpPaintCommand``
- ``HwpPaintListBuilder``
- ``HwpTextRunBuilder``
- ``HwpParagraphLayout``
- ``HwpTableLayout``
- ``HwpPageGeometry``
- ``HwpUnits``
- ``HwpRenderTuning``
