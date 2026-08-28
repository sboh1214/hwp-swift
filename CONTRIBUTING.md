# 기여

## 빌드 요구 사항

Apple 플랫폼은 Xcode(Swift 5.9+)만 있으면 됩니다. Linux에서 작업한다면 압축
해제가 시스템 zlib에 링크하므로 개발 헤더가 필요합니다 — 공식 Swift 도커
이미지에는 이미 들어 있고, 그 외 환경에서는 `zlib1g-dev`(rpm 계열은
`zlib-devel`)를 설치하십시오. 바인딩은 `Sources/CHwpZlib`의 module map으로만
들어오므로, 링크 대상을 바꿀 일이 생기면 그 디렉터리와 `Package.swift`를
함께 고칩니다.

## 코딩 스타일

이 프로젝트는 코드 포맷과 스타일을 강제하기 위해 [SwiftLint](https://github.com/realm/SwiftLint),
[SwiftFormat](https://github.com/nicklockwood/SwiftFormat),
[pre-commit](https://pre-commit.com/)을 사용합니다.

```
brew install swiftlint swiftformat pre-commit
pre-commit install
```

SwiftFormat과 SwiftLint는 모든 PR에서 CI(`ci.yml`의 `lint` 잡)으로 확인됩니다.

## 명명법

파일 및 폴더명은 파스칼표기법을 따릅니다.
스위프트 코드는 일반적인 명명법을 따릅니다.

## 코드 퀄리티

커버리지는 [Codecov](https://codecov.io/gh/sboh1214/hwp-swift)에서 추적합니다.

## Pull Request 라벨

라벨은 release-drafter(`.github/release-drafter.yml`)가 릴리스 노트 분류와
버전 산정에 사용하므로, PR 성격대로 답니다.

- 기능 PR → `enhancement` (릴리스 노트의 🚀 Features로 분류됩니다)
- 성능 개선 PR → `performance` (⚡️ Performance로 분류됩니다)
- 버그 수정 PR → `bug` (🐛 Bug Fixes로 분류됩니다). 성능 회귀 수정도
  `performance`가 아니라 `bug`를 답니다. 버그 수정에는 `enhancement`를
  달지 않습니다.
- 문서 PR → `documentation` (📚 Documentation으로 분류됩니다)
- CI·테스트·리팩터링 PR → `maintenance` (🧰 Maintenance로 분류됩니다)
- 공개 API의 소스 브레이킹 또는 동작 변경이 있으면 `api-breaking`을 추가로
  답니다. 이 라벨이 하나라도 든 구간은 다음 릴리스 버전이 minor로 올라갑니다
  — 1.0 전까지 파괴 변경은 minor 버전에 싣습니다.

분류 라벨(`enhancement`·`performance`·`bug`·`documentation`·`maintenance`)은 PR당 하나만
답니다 — release-drafter는 여러 카테고리에 걸치는 PR을 카테고리마다 중복
기재합니다. `api-breaking`은 분류 라벨이 아니므로 함께 달아도 됩니다.

라벨이 없는 PR은 릴리스 노트에서 카테고리 밖으로 떨어지므로, 머지 전에
반드시 분류 라벨 하나를 답니다.

## 문서

문서는 [Swift-DocC](https://www.swift.org/documentation/docc/)로 빌드되며,
`main` 브랜치에 푸시될 때 [https://hwp-swift.sboh.dev/](https://hwp-swift.sboh.dev/)에
배포됩니다. 사이트는 4개 라이브러리 타깃(CoreHwp·HwpKitCore·HwpKitNative·
HwpKit)의 combined DocC 아카이브 하나로 구성됩니다. 빌드 명령의 단일
출처는 `.github/actions/build-docs-site/action.yml`이고, 배포는 `cd.yml`의
`docs` 잡, PR 검증은 `docs-check.yml`입니다. combined 문서 생성에는
Swift 6.0+(Xcode 16+) 툴체인의 docc가 필요합니다.

각 타깃의 모듈 랜딩과 심볼 큐레이션은 `Sources/<타깃>/<타깃>.docc/` 안의
루트 문서가 정의합니다 — 새 public 진입점을 추가했으면 해당 루트 문서의
`## Topics`에도 올려 주세요 (큐레이션되지 않은 심볼은 종류별 자동 그룹으로
목록 맨 아래에 표시됩니다).

### 로컬에서 미리보기

DocC 미리보기 서버를 실행하면 변경 사항이 브라우저에 즉시 반영됩니다.
미리보기는 combined 모드를 지원하지 않으므로 한 번에 한 타깃만 띄웁니다.

```sh
swift package --disable-sandbox preview-documentation --target CoreHwp
```

명령을 실행하면 `http://localhost:8080/documentation/corehwp` 같은 URL이
콘솔에 표시되며, 그 주소를 브라우저에서 열면 됩니다. HwpKitCore·
HwpKitNative·HwpKit도 같은 방식입니다.

### 배포본과 동일한 정적 사이트 생성

GitHub Pages에 배포되는 결과물 그대로 확인하고 싶다면 정적 사이트를 직접
생성한 뒤 로컬 HTTP 서버로 띄웁니다. 출력 위치(`./docs`)와 인자는
`.github/actions/build-docs-site/action.yml`과 동일하며, 마지막의 랜딩
페이지 overlay까지 같은 순서로 재현합니다. `--hosting-base-path`는 쓰지
않습니다 — 커스텀 도메인이 루트에서 서빙합니다. `./docs`는 `.gitignore`에
포함되어 있어 작업 후 별도로 정리하지 않아도 됩니다.

```sh
rm -rf ./docs
swift package --allow-writing-to-directory ./docs \
  generate-documentation \
  --target CoreHwp \
  --target HwpKitCore \
  --target HwpKitNative \
  --target HwpKit \
  --enable-experimental-combined-documentation \
  --disable-indexing \
  --transform-for-static-hosting \
  --output-path ./docs
cp .github/pages/index.html ./docs/index.html

python3 -m http.server 8000 --directory ./docs
```

이후 `http://localhost:8000/`에서 랜딩 페이지를,
`http://localhost:8000/documentation/corehwp/` 등에서 모듈 문서를,
`http://localhost:8000/documentation/`에서 합성 패키지 색인을
확인할 수 있습니다.

## 배포

### 릴리스

`main`에 푸시될 때마다 release-drafter(`cd.yml`의 `release-drafter` 잡)가 드래프트
릴리스를 갱신합니다. 다음 버전 번호는 그 구간에 머지된 PR의 라벨에서 산정되므로
(위 "Pull Request 라벨"), 라벨이 맞아야 번호가 맞습니다.

릴리스할 때 아래를 함께 갱신합니다.

- `CHANGELOG.md` — `## Unreleased` 아래 내용을 `## X.Y.Z (YYYY-MM-DD)`로 확정하고,
  비어 있는 `## Unreleased`를 맨 위에 남깁니다.
- `README.md`와 `.github/pages/index.html` — 설치 스니펫의 고정 버전. **두 곳은
  같은 안내의 사본**이고 후자는 `docs` 잡이 DocC 산출물 위에 덮어 사이트로
  배포하므로, 하나만 고치면 hwp-swift.sboh.dev가 낡은 안내를 계속 내보냅니다.

드래프트 릴리스를 게시하면 그 시점의 `main`에 태그가 생성됩니다.

### Swift 버전이 새로 출시된 경우

아래 파일의 Swift matrix를 업데이트합니다.

- `.github/workflows/ci.yml` (`test-macos`, `test-linux`의 `matrix.swift`)

### Minimum Swift 버전이 변경된 경우

아래 파일을 모두 업데이트합니다.

- `.github/workflows/ci.yml` (matrix 최소 버전)
- `.swift-version`
- `.swiftformat` (`--swiftversion`)
- `Package.swift` (`// swift-tools-version:` 및 `platforms`)
