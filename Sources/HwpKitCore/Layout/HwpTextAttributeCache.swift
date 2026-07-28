import CoreHwp
import CoreText
import Foundation

/// 글자 모양 (charShape) 별 텍스트 속성 사전 캐시 — 같은 글자 모양을 쓰는 텍스트
/// 조각마다 속성 사전과 파생 CTFont를 처음부터 다시 만드는 중복을 없앤다.
///
/// `HwpTextRunBuilder.attributes(for:script:)`는 `index`·`fontResolver`가 고정일 때
/// `(shapeId, script)`의 순수 함수다. 장평·이탤릭 근사 매트릭스·라틴 세리프 폴백·
/// 장식 (밑줄/취소선/음영/그림자/외곽선/양각/강조점/첨자)이 전부 글자 모양에서만
/// 나오고, 문단마다 달라지는 값 (변경추적 표시·메모 앵커·controlIndex·run
/// delegate·첨자 치환)은 전부 **반환된 뒤** 사전 사본에 붙기 때문이다. 문서 하나가
/// 쓰는 글자 모양은 보통 수십 개뿐이라 이 계산의 대부분이 중복이다.
///
/// **계약 — 돌려받은 사전을 제자리에서 변형하지 말 것.** 캐시가 같은 사전 (그리고
/// 그 안의 CTFont/CGColor/NSNumber 인스턴스)을 여러 호출부에 공유하므로, 값을
/// 제자리에서 바꾸면 다른 호출부까지 오염된다. 호출부는 `var` 사본에 키를 추가·
/// 치환만 한다 — Swift Dictionary는 값 타입이라 사본 수정이 캐시에 닿지 않고,
/// CTFont·CGColor는 불변이라 교체만 안전하다. (`HwpFontResolver`가 같은 CTFont
/// 인스턴스를 이미 여러 run에 나눠 주고 있어 공유 자체는 새 계약이 아니다.)
///
/// **소유는 문서 (파이프라인) 단위** — `HwpPaginator.init`이 하나 만들어 하위
/// 레이아웃에 주입한다. 전역 캐시나 `HwpFontResolver` 소유는 안 된다:
/// - `shapeId`의 의미가 문서 (`HwpIndex`) 마다 다르다 — 문서를 넘어 공유하면 다른
///   문서의 글자 모양이 섞인다 (`.testDeterministic` 처럼 여러 문서가 공유하는
///   resolver가 실재한다).
/// - `usesInstalledHancomFonts`가 resolver별 값이라 한 프로세스에 opt-in on/off
///   resolver가 공존할 수 있다 — 전역 캐시는 두 모드의 폰트를 섞는다.
///
/// 이 문서 단위 소유 규약을 타입으로 강제할 수단이 없으므로 (키에 `HwpIndex`
/// 신원이 없다) **internal로 둔다** — 캐시를 받는 init도 전부 internal이라 모듈
/// 밖에서 다른 문서의 캐시를 넘길 길 자체가 없다. public API는 캐시 없는
/// 기존 init 그대로다.
final class HwpTextAttributeCache: @unchecked Sendable {
    private struct AttributeKey: Hashable {
        /// `nil` = `index`에 없는 글자 모양 id. `HwpTextRunBuilder.resolvedShape`의
        /// 폴백이 문단과 무관한 상수 (`HwpCharShape()`)라 미해결 id는 결과 사전이
        /// 전부 같으므로 **한 키로 접는다**. 접지 않으면 조작 문서가 문자마다 다른
        /// id를 흘려 내용이 같은 항목을 문서 수명 내내 쌓게 된다.
        let shapeId: UInt32?
        let script: HwpScript
    }

    /// 저장소별 항목 수 상한 — 넘으면 **축출이 아니라 삽입 중단**이다. 조판은 문서를
    /// 순서대로 훑으므로 FIFO 축출은 워킹셋이 상한보다 클 때 히트율 0% + 매번 전량
    /// 재삽입이 된다 (`HwpPageLayer` 줄 배치 캐시에서 겪은 함정). 미스가 `create`
    /// 폴백이라 삽입을 멈춰도 결과는 같다 — 느려질 뿐이다.
    ///
    /// 정상 문서는 닿지 않는다: 미해결 id가 위에서 한 키로 접히므로 항목 수는
    /// (문서가 실제 가진 charShape 수) × (스크립트 7) 이하이고, 상한에 닿으려면
    /// 9,000개 넘는 글자 모양을 실제로 쓰는 문서여야 한다. 항목당 수백 바이트라
    /// 상한 자체도 수십 MB 수준 — `HwpPaginator.maximumDocumentPages`와 같은 결의 절단.
    static let maximumStoredEntries = 65536
    /// 인스턴스 상한 (기본 = 전역) — 테스트가 상한 경로를 작은 입력으로 재현한다
    /// (`HwpPageLayer.cachedLineBudget`와 같은 패턴).
    var maximumEntries = HwpTextAttributeCache.maximumStoredEntries

    /// 사전과 그 값 (CTFont/CGColor/NSNumber)은 모두 불변으로 다룬다 (위 계약) —
    /// 저장소 접근만 lock으로 감싼다. `HwpFontResolver.FontCache`와 같은 패턴.
    private var attributeStorage: [AttributeKey: [NSAttributedString.Key: Any]] = [:]
    private var tabStorage: [UInt32: [CTTextTab]] = [:]
    private let lock = NSLock()

    /// 테스트 전용 관측 지점 (`HwpFontResolver.matchCounter`와 같은 역할) — 캐시가
    /// 실제로 재계산을 없애는지 유닛 테스트가 확인한다. 속성 사전만 센다.
    private var hits = 0
    private var misses = 0

    init() {}

    var hitCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return hits
    }

    var missCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return misses
    }

    var entryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return attributeStorage.count
    }

    /// `(shapeId, script)`의 텍스트 속성 사전. 없으면 `create`로 만들어 채운다.
    ///
    /// `create`는 lock 밖에서 부른다 — CoreText 폰트 생성이 무거워 lock을 쥔 채
    /// 부르면 병렬 조판이 직렬화된다. 경합하면 같은 키를 두 번 만들 수 있지만 순수
    /// 함수라 결과가 같다 (`FontCache`와 같은 절충).
    func attributes(
        shapeId: UInt32?,
        script: HwpScript,
        create: () -> [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any] {
        let key = AttributeKey(shapeId: shapeId, script: script)
        lock.lock()
        if let cached = attributeStorage[key] {
            hits += 1
            lock.unlock()
            return cached
        }
        misses += 1
        lock.unlock()
        let attributes = create()
        lock.lock()
        if attributeStorage.count < maximumEntries {
            attributeStorage[key] = attributes
        }
        lock.unlock()
        return attributes
    }

    /// 탭 정의 (표 36) 별 CT 탭 스톱. `HwpIndex.textTabs(for:)`는 호출마다
    /// `CTTextTab`을 새로 만드는데 문단마다 (측정 + 렌더 재조판) 불린다. 결과는
    /// `tabDefId`만의 함수이고 `CTTextTab`은 불변이라 문서 안에서 공유해도 된다.
    func textTabs(for paraShape: CoreHwp.HwpParaShape, index: HwpIndex) -> [CTTextTab] {
        let key = UInt32(paraShape.tabDefId)
        lock.lock()
        if let cached = tabStorage[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let tabs = index.textTabs(for: paraShape)
        lock.lock()
        if tabStorage.count < maximumEntries {
            tabStorage[key] = tabs
        }
        lock.unlock()
        return tabs
    }
}
