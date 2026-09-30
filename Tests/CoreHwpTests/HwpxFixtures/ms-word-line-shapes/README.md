# ms-word-line-shapes

HWP fixture `ms-word-line-shapes`(`Tests/CoreHwpTests/Fixtures/ms-word-line-shapes/document.hwp`)와
같은 편집 세션에서 한글.app이 저장한 HWPX(OWPML) 쌍 fixture다. **MS 워드 호환 문서**
(`hh:compatibleDocument@targetProgram="MS_WORD"`, 한글 슬롯 Apple SD 산돌고딕 Neo·라틴 슬롯 Menlo)에
원형 점선·긴 점선·2중선·물결·가는+굵은 선 밑줄과 상대 크기·슬롯 상대 크기 취소선·밑줄 11문단
(꼬리표 ` #0`…` #10`)을 싣고, 두 포맷의 렌더가 그 문서의 밑줄 무늬를 한글처럼 줄 글자 상자의 높이로
재고 여러 줄 띠·물결을 단선 중심에 가운데 맞추며 취소선 무늬를 글자 모양 기본 크기로 재는지를
고정한다 (#244). `document.hwpx`의 파싱 기대값은 `manifest.json`에 있다.

## 재생성

1. `/Applications/한컴오피스 한글.app`(bundle `com.hancom.office.hwp12.mac.general`,
   12.30.0 build 6446)에서 HWP 쌍의 재생성 절차(`Fixtures/ms-word-line-shapes/README.md`)를
   따라 원본 HWPX를 연다.
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 문서 (*.hwp)** → 저장한 뒤,
   같은 세션에서 다시 `파일 > 다른 이름으로 저장하기...` → **한글 표준 문서 (*.hwpx)** → 저장.
3. 저장본을 이 디렉터리의 `document.hwpx`로 복사한다.
4. `manifest.json`의 기대값을 갱신하고 `swift test --filter Hwpx`를 실행한다.

## 생성 확인 환경

- 앱: /Applications/한컴오피스 한글.app (com.hancom.office.hwp12.mac.general)
- 버전: 12.30.0 (build 6446)
- 일자: 2026-09-30 (System Events 접근성 자동화로 저장)
