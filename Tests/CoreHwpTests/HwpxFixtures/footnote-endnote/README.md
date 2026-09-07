# footnote-endnote

HWP fixture `footnote-endnote`(`Tests/CoreHwpTests/Fixtures/footnote-endnote/document.hwp`)의
사본을 한글.app에서 열어 저장한 HWPX(OWPML) 쌍 fixture다. 각주 1개·미주 1개와
구역의 각주·미주 모양을 담아 구역 부속 컨트롤의 typed 승격(#168)을 HWP 쌍과
대조한다.

승격 전에는 `hp:footNote`·`hp:endNote`·`hp:autoNum`이 `.notImplemented`로 강등돼
**각주·미주 본문이 통째로 사라졌다** — 미지 요소 강등은 요소 이름만 payload로
담아 `hp:t` 텍스트가 모델에 남지 않는다. `document.hwpx`의 파싱 기대값은
`manifest.json`에 있다.

## 담긴 구조

```xml
<hp:footNote number="1" suffixChar="41" instId="1115242634">
  <hp:subList vertAlign="TOP" textWidth="0" textHeight="0" …>
    <hp:p …><hp:run charPrIDRef="3">
      <hp:ctrl><hp:autoNum num="1" numType="FOOTNOTE">
        <hp:autoNumFormat type="DIGIT" userChar="" prefixChar="" suffixChar=")" supscript="0"/>
      </hp:autoNum></hp:ctrl>
      <hp:t> CoreHwp footnote fixture</hp:t>
    </hp:run>…</hp:p>
  </hp:subList>
</hp:footNote>
```

`hp:endNote`는 같은 구조에 `numType="ENDNOTE"`이고 본문은 `CoreHwp endnote fixture`다.
번호 라벨이 각주 본문 문단 안의 `hp:autoNum`에서 나오므로 각주만 승격하면 번호
없는 각주가 된다.

구역 설정에는 조판 값이 따로 있다 — `hp:secPr > hp:footNotePr`·`hp:endNotePr`의
`autoNumFormat`·`noteLine`·`noteSpacing`·`numbering`·`placement`가 HWP 쌍의
FOOTNOTE_SHAPE 28바이트와 한 자리도 남기지 않고 맞는다. 미주는
`place="END_OF_DOCUMENT"`이고 `noteLine length`가 유한값(14,692,344)이다.

## 재생성

1. `/Applications/한컴오피스 한글.app`(bundle `com.hancom.office.hwp12.mac.general`,
   12.30.0 build 6446)에서 HWP 쌍(`Fixtures/footnote-endnote/document.hwp`)의 **사본**을
   연다 (열람만으로 원본이 재기록되므로 사본 필수).
2. `파일 > 다른 이름으로 저장하기...` → 파일 형식 **한글 표준 문서 (*.hwpx)** → 저장.
3. 저장본을 이 디렉터리의 `document.hwpx`로 복사하고 `git status`로 HWP 원본이
   변경되지 않았는지 확인한다.
4. `manifest.json`의 기대값을 갱신하고 `swift test --filter Hwpx`를 실행한다.
   `pageCount`는 변환본을 한글.app에서 열어 상태 표시줄의 `N/M쪽`으로 확인한다.

## 생성 확인 환경

- 앱: /Applications/한컴오피스 한글.app (com.hancom.office.hwp12.mac.general)
- 버전: 12.30.0 (build 6446)
- 일자: 2026-09-07 (Claude Computer Use GUI 자동화로 저장)
