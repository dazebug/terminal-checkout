/// 지원 터미널의 단일 식별자. rawValue가 곧 `UserDefaults` 저장값이다 — `iterm`은 확장 이름과
/// 무관하게 iTerm2를 가리키는 식별자이므로 바꾸지 않는다. 케이스를 추가하면 default 없는
/// switch들이 컴파일 에러로 손댈 분기를 드러낸다 — 스위치 밖 분기(표시 조건 등)와 실측 항목은
/// docs/new-terminal-checklist.md가 정본이다.
public enum Terminal: String, CaseIterable {
    case iterm
    case wezterm
    case warp

    /// 저장값 파싱의 단일 지점. 알 수 없는 값(다른 버전이 남긴 식별자, 손으로 고친 plist)은
    /// iTerm2로 폴백한다 — 이전에는 소비 지점마다 switch default가 따로 폴백해, 실행은
    /// iTerm2로 가면서 설정 창은 iTerm2 권한 섹션을 숨기는 식으로 어긋날 수 있었다.
    public init(storedValue: String) {
        self = Terminal(rawValue: storedValue) ?? .iterm
    }
}
