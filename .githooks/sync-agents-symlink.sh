#!/usr/bin/env bash
# CLAUDE.md가 있는 디렉터리마다 AGENTS.md -> CLAUDE.md 심볼릭 링크를 유지한다. 루트·중첩 모두.
#   (인자 없음) pre-commit 모드 — 이번 커밋에 CLAUDE.md의 추가·복사·삭제·수정·이름 변경이 스테이징된 디렉터리만 처리한다.
#               CLAUDE.md 변화가 없는 커밋에서는 아무것도 하지 않는다.
#   --all       전체 모드 — 추적 중이거나 무시되지 않은 CLAUDE.md·AGENTS.md 전부를 대상으로 링크를 만들고 CLAUDE.md가 없는
#               디렉터리의 링크를 지운다(설치 시 1회). 무시된 경로와 중첩 worktree는 대상이 아니다.
# 두 모드 모두 만든 링크와 지운 링크를 스테이징한다. 출력: created|removed|kept|skipped <경로> [사유]
#
# 판정의 기준은 작업 트리가 아니라 index다 — 이 훅이 지키려는 것은 "커밋 안에서 CLAUDE.md와 AGENTS.md가 맞는가"이고,
# 그 내용을 정하는 것은 index이기 때문이다. 작업 트리를 보면 `git rm --cached CLAUDE.md`로 삭제만 스테이징하고 파일을
# 남겨 둔 경우 링크를 유지해 CLAUDE.md 없이 링크만 든 깨진 커밋을 만들고, 반대로 추가를 스테이징한 뒤 작업 트리에서
# 지우면 링크 생성을 놓친다. 링크의 실재 여부만 작업 트리에서 본다(심볼릭 링크는 파일시스템 상태여야 하므로).
#
# 경로는 어디서도 개행으로 나누지 않는다 — git은 경로에 개행을 허용하므로 줄 단위로 다루면 그런 디렉터리의
# 링크를 조용히 만들지 않거나 이름이 겹치는 엉뚱한 디렉터리를 동기화한다. 입력·중간 스트림·정렬 전부 NUL 구분이다.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

# 정방향 링크(AGENTS.md -> CLAUDE.md)를 지우고 스테이징한다.
remove_link() {
  rm -f "$1"
  git add -A -- "$1"
}

sync_dir() {
  local rel="$1" claude_idx link_idx claude_fs link_fs
  if [ "$rel" = "." ]; then
    claude_idx="CLAUDE.md"; link_idx="AGENTS.md"
  else
    claude_idx="$rel/CLAUDE.md"; link_idx="$rel/AGENTS.md"
  fi
  # 파일시스템 접근에는 `./`를 붙인다 — `-`로 시작하는 디렉터리 이름이 옵션으로 읽히지 않게 한다.
  claude_fs="./$claude_idx"; link_fs="./$link_idx"

  if git cat-file -e ":$claude_idx" 2>/dev/null; then
    # CLAUDE.md가 `@AGENTS.md` 한 줄이면 AGENTS.md가 원본(역방향 동기화)이므로 링크를 만들지 않는다 —
    # 만들면 CLAUDE.md의 import가 자기 자신을 가리키는 순환이 되고, 실제 파일 AGENTS.md를 통합 대상으로 오인하게 된다.
    if [ "$(git cat-file blob ":$claude_idx" | tr -d '[:space:]')" = "@AGENTS.md" ]; then
      # 이미 있던 정방향 링크는 지운다 — 남겨 두면 CLAUDE.md -> AGENTS.md -> CLAUDE.md 순환이 그대로 커밋된다.
      if [ -L "$link_fs" ] && [ "$(basename "$(readlink "$link_fs")")" = "CLAUDE.md" ]; then
        remove_link "$link_fs"
        echo "removed $link_fs (CLAUDE.md가 @AGENTS.md를 import — 순환이 되는 정방향 링크 제거)"
        return
      fi
      echo "skipped $link_fs (CLAUDE.md가 @AGENTS.md를 import — AGENTS.md가 원본)"
      return
    fi
    if [ -L "$link_fs" ]; then
      if [ "$(readlink "$link_fs")" = "CLAUDE.md" ]; then
        echo "kept $link_fs"
        return
      fi
      rm -f "$link_fs"
    elif [ -e "$link_fs" ]; then
      echo "skipped $link_fs (실제 파일 — /agents-md:setup-agents-md 로 CLAUDE.md에 통합한다)"
      return
    fi
    ln -s CLAUDE.md "$link_fs"
    git add -f -- "$link_fs"
    echo "created $link_fs"
  elif [ -L "$link_fs" ] && [ "$(basename "$(readlink "$link_fs")")" = "CLAUDE.md" ]; then
    remove_link "$link_fs"
    echo "removed $link_fs"
  elif [ -f "$claude_fs" ]; then
    echo "skipped $link_fs (CLAUDE.md가 index에 없다 — git add 후 다시 실행한다)"
  fi
}

# NUL 구분 경로 스트림을 NUL 구분 디렉터리 스트림으로 바꾼다. dirname 대신 parameter expansion을 쓰므로
# 개행이 든 경로가 보존되고 경로마다 프로세스를 만들지 않는다.
paths_to_dirs() {
  local path dir
  while IFS= read -r -d '' path; do
    dir="${path%/*}"
    [ "$dir" = "$path" ] && dir="."
    printf '%s\0' "$dir"
  done
}

# NUL 구분 디렉터리 스트림을 정렬·중복 제거해 처리한다. sort -z는 macOS(Apple sort 2.3)와 GNU sort 모두 지원한다.
sync_dirs() {
  local dir
  sort -zu | while IFS= read -r -d '' dir; do sync_dir "$dir"; done
}

if [ "${1:-}" = "--all" ]; then
  # find로 트리를 훑지 않는다 — .gitignore된 디렉터리 안의 중첩 worktree(.claude/worktrees/ 등)까지 내려가
  # 다른 worktree 안에 링크를 만든다. git ls-files는 무시 경로와 중첩 저장소를 밖에서 보지 않으며,
  # --cached --others --exclude-standard 로 추적 중인 파일과 아직 추적되지 않은(무시되지 않은) 파일을 함께 잡는다.
  git ls-files -z --cached --others --exclude-standard -- 'CLAUDE.md' '*/CLAUDE.md' 'AGENTS.md' '*/AGENTS.md' \
    | paths_to_dirs | sync_dirs
  exit 0
fi

# pre-commit 모드 — 이름 변경(R)·복사(C)는 옛 디렉터리의 링크 제거와 새 디렉터리의 링크 생성이 둘 다 필요해 두 경로를 모은다.
# 필터의 C는 case의 C* 분기와 짝이다 — diff.renames=copies 인 저장소에서 복사된 CLAUDE.md가 빠지지 않게 한다.
# 수정(M)도 링크 구조를 바꾼다 — 기존 CLAUDE.md를 `@AGENTS.md`로 바꾸면 역방향 전환이므로 정방향 링크를 걷어내야 한다.
# 그 외의 내용 수정에서는 이 디렉터리가 `kept` 한 줄로 끝난다.
# 경로 패턴의 *는 /도 매치하므로 중첩 디렉터리의 CLAUDE.md까지 잡힌다.
{
  while IFS= read -r -d '' status; do
    IFS= read -r -d '' path || break
    printf '%s\0' "$path"
    case "$status" in
      R*|C*) IFS= read -r -d '' path || break; printf '%s\0' "$path" ;;
    esac
  done < <(git diff --cached --name-status -z --diff-filter=ACDMR -- 'CLAUDE.md' '*/CLAUDE.md')
} | paths_to_dirs | sync_dirs
