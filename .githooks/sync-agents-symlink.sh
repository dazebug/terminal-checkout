#!/usr/bin/env bash
# CLAUDE.md가 있는 디렉터리마다 AGENTS.md -> CLAUDE.md 심볼릭 링크를 유지한다. 루트·중첩 모두.
#   (인자 없음) pre-commit 모드 — 이번 커밋에 CLAUDE.md의 추가·삭제·이름 변경이 스테이징된 디렉터리만 처리한다.
#               CLAUDE.md 변화가 없는 커밋에서는 아무것도 하지 않는다.
#   --all       전체 모드 — 트리 전체를 훑어 링크를 만들고 CLAUDE.md가 없는 디렉터리의 링크를 지운다(설치 시 1회).
# 두 모드 모두 만든 링크와 지운 링크를 스테이징한다. 출력: created|removed|kept|skipped <경로> [사유]
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

sync_dir() {
  local dir="$1" claude="$1/CLAUDE.md" link="$1/AGENTS.md"
  if [ -f "$claude" ]; then
    # CLAUDE.md가 `@AGENTS.md` 한 줄이면 AGENTS.md가 원본(역방향 동기화)이므로 링크를 만들지 않는다 —
    # 만들면 CLAUDE.md의 import가 자기 자신을 가리키는 순환이 되고, 실제 파일 AGENTS.md를 통합 대상으로 오인하게 된다.
    if [ "$(tr -d '[:space:]' < "$claude")" = "@AGENTS.md" ]; then
      echo "skipped $link (CLAUDE.md가 @AGENTS.md를 import — AGENTS.md가 원본)"
      return
    fi
    if [ -L "$link" ]; then
      if [ "$(readlink "$link")" = "CLAUDE.md" ]; then
        echo "kept $link"
        return
      fi
      rm -f "$link"
    elif [ -e "$link" ]; then
      echo "skipped $link (실제 파일 — /agents-md:setup-agents-md 로 CLAUDE.md에 통합한다)"
      return
    fi
    (cd "$dir" && ln -s CLAUDE.md AGENTS.md)
    git add -f -- "$link"
    echo "created $link"
  elif [ -L "$link" ] && [ "$(basename "$(readlink "$link")")" = "CLAUDE.md" ]; then
    rm -f "$link"
    git add -A -- "$link"
    echo "removed $link"
  fi
}

if [ "${1:-}" = "--all" ]; then
  { find . -path ./.git -prune -o -type l -name AGENTS.md -print0
    find . -path ./.git -prune -o -type f -name CLAUDE.md -print0; } \
    | xargs -0 -r -n1 dirname | sort -u | while IFS= read -r dir; do sync_dir "$dir"; done  # -r: GNU xargs는 입력이 없어도 dirname을 실행해 pipefail로 죽는다(BSD는 실행하지 않음)
  exit 0
fi

# pre-commit 모드 — 이름 변경(R)은 옛 디렉터리의 링크 제거와 새 디렉터리의 링크 생성이 둘 다 필요해 두 경로를 모은다.
# 경로 패턴의 *는 /도 매치하므로 중첩 디렉터리의 CLAUDE.md까지 잡힌다.
dirs=""
while IFS= read -r -d '' status; do
  IFS= read -r -d '' path || break
  dirs="$dirs$(dirname "$path")"$'\n'
  case "$status" in
    R*|C*) IFS= read -r -d '' path || break; dirs="$dirs$(dirname "$path")"$'\n' ;;
  esac
done < <(git diff --cached --name-status -z --diff-filter=ADR -- 'CLAUDE.md' '*/CLAUDE.md')
[ -n "$dirs" ] || exit 0
printf '%s' "$dirs" | sort -u | while IFS= read -r dir; do
  if [ "$dir" = "." ]; then
    sync_dir "."
  else
    sync_dir "./$dir"
  fi
done
