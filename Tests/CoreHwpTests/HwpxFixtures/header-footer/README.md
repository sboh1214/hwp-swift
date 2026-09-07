# header-footer

HWP fixture `header-footer`(`Tests/CoreHwpTests/Fixtures/header-footer/document.hwp`)의
사본을 한글.app에서 열어 저장한 HWPX(OWPML) 쌍 fixture다. 양쪽 머리말·꼬리말
(`hp:header`·`hp:footer`, 각각 `applyPageType="BOTH"`)을 담아 구역 부속 컨트롤의
typed 승격(#167)을 HWP 쌍과 대조한다.

승격 전에는 두 요소가 `.notImplemented`로 강등돼 머리말·꼬리말이 매 쪽에서
통째로 빠졌다. `document.hwpx`의 파싱 기대값은 `manifest.json`에 있다.

## 담긴 구조

```xml
<hp:header id="1" applyPageType="BOTH">
  <hp:subList vertAlign="TOP" textWidth="42520" textHeight="4252" …>
    <hp:p …><hp:run charPrIDRef="2"><hp:t>CoreHwp header fixture</hp:t></hp:run>…</hp:p>
  </hp:subList>
</hp:header>
```

`hp:footer`는 같은 구조에 `vertAlign="BOTTOM"`이고 본문은 `CoreHwp footer fixture`다.

## 재생성

1. `/Applications/한컴오피스 한글.app`(bundle `com.hancom.office.hwp12.mac.general`,
   12.30.0 build 6446)에서 HWP 쌍(`Fixtures/header-footer/document.hwp`)의 **사본**을
   연다 (열람만으로 원본이 재기록되므로 사본 필수).
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 표준 문서 (*.hwpx)** → 저장.
3. 저장본을 이 디렉터리의 `document.hwpx`로 복사하고 `git status`로 HWP 원본이
   변경되지 않았는지 확인한다.
4. `manifest.json`의 기대값을 갱신하고 `swift test --filter Hwpx`를 실행한다.

## 생성 확인 환경

- 앱: /Applications/한컴오피스 한글.app (com.hancom.office.hwp12.mac.general)
- 버전: 12.30.0 (build 6446)
- 일자: 2026-09-07 (Claude Computer Use GUI 자동화로 저장)
