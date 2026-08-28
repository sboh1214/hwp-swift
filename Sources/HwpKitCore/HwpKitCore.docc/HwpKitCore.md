# ``HwpKitCore``

HWP 문서를 조판해 페인트 목록을 만들며, UI 프레임워크에 의존하지 않는
렌더 코어입니다.

## Overview

HwpKitCore는 CoreHwp가 파싱한 `HwpFile`을 CoreText·CoreGraphics 기반으로
조판하는 모델과 엔진을 제공합니다. ``HwpPaginator``가 ``HwpPage``와
``HwpPaintList``를 만들고, ``HwpDocument``가 페이지 결과를 묶습니다.
AppKit·UIKit·SwiftUI에 의존하지 않아 화면·PDF·비트맵 렌더러가 같은
조판 결과를 공유하며, 검색·선택도 같은 페이지 모델을 사용합니다.

SwiftUI 앱에서는 보통 HwpKit의 `HwpDocumentLoader`가 이 모듈의
``HwpDocument``를 생성합니다. 검색 세션(``HwpSearchController``)·선택
(``HwpSelectionController``)·폰트 해석(``HwpFontResolver``)을 직접
제어하거나 커스텀 렌더러를 만들 때는 이 모듈을 직접 사용합니다.

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
