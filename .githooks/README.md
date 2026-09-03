# Git Hooks

pre-commit: 이번 커밋에 CLAUDE.md가 추가·삭제·이름 변경되면 그 디렉터리의 `AGENTS.md → CLAUDE.md` 심볼릭 링크를 만들거나 지우고 함께 스테이징한다. CLAUDE.md 변화가 없는 커밋에서는 아무것도 하지 않는다. 전체 동기화는 `.githooks/sync-agents-symlink.sh --all`.

## 활성화

```
git config core.hooksPath .githooks
```
