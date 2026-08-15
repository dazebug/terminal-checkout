# Git Hook for AGENTS symlink

이 저장소는 커밋 전에 각 폴더의 `CLAUDE.md` 유무에 따라 `AGENTS.md` 심볼릭 링크를 생성/삭제합니다.

- `CLAUDE.md`가 있는 폴더: 해당 폴더에 `AGENTS.md`를 생성(또는 유지)
- `CLAUDE.md`가 없는 폴더: 기존 `AGENTS.md`(symlink) 삭제

로컬에서 활성화하려면 다음을 실행하세요.

```bash
git config core.hooksPath .githooks
```
