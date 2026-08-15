#!/usr/bin/env python3
"""
Terminal Checkout Native Host
Chrome 확장 프로그램에서 메시지를 받아 터미널(iTerm2/WezTerm)에서 명령 실행
"""

import json
import os
import struct
import subprocess
import sys
import re
import glob as glob_mod


def read_message():
    """Chrome에서 보낸 메시지 읽기"""
    raw_length = sys.stdin.buffer.read(4)
    if not raw_length:
        return None
    length = struct.unpack('=I', raw_length)[0]
    message = sys.stdin.buffer.read(length).decode('utf-8')
    return json.loads(message)


def send_message(message):
    """Chrome으로 응답 메시지 전송"""
    encoded = json.dumps(message).encode('utf-8')
    sys.stdout.buffer.write(struct.pack('=I', len(encoded)))
    sys.stdout.buffer.write(encoded)
    sys.stdout.buffer.flush()


def sanitize_input(text):
    """입력값에서 위험한 문자 제거 (command injection 방지)"""
    if not re.match(r'^[a-zA-Z0-9\-_./]+$', text):
        raise ValueError(f"Invalid characters in input: {text}")
    return text


ALLOWED_VARIABLES = {'repo', 'branch', 'main', 'branch_underbar'}


def render_command(template, variables):
    """command template에 변수를 치환하여 최종 명령어 생성"""
    sanitized = {}
    for key, value in variables.items():
        if key not in ALLOWED_VARIABLES:
            raise ValueError(f"Unknown variable: {{{key}}}")
        sanitized[key] = sanitize_input(value)

    # template에서 {var} 패턴 찾아서 치환
    def replacer(match):
        var_name = match.group(1)
        if var_name not in sanitized:
            raise ValueError(f"Variable {{{var_name}}} not provided")
        return sanitized[var_name]

    return re.sub(r'\{(\w+)\}', replacer, template)


def find_wezterm_cli():
    """WezTerm CLI 경로 탐색: PATH → /Applications fallback"""
    for directory in os.environ.get("PATH", "").split(os.pathsep):
        candidate = os.path.join(directory, "wezterm")
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    fallback = "/Applications/WezTerm.app/Contents/MacOS/wezterm"
    if os.path.isfile(fallback):
        return fallback
    return None


def find_wezterm_socket():
    """실행 중인 WezTerm GUI 프로세스의 소켓 찾기"""
    sock_dir = os.path.expanduser("~/.local/share/wezterm")
    if not os.path.isdir(sock_dir):
        return None

    # 실행 중인 wezterm-gui PID 수집
    try:
        result = subprocess.run(
            ["pgrep", "-x", "wezterm-gui"],
            capture_output=True, text=True, timeout=3
        )
        running_pids = set(result.stdout.strip().split()) if result.returncode == 0 else set()
    except (subprocess.TimeoutExpired, OSError):
        running_pids = set()

    # 실행 중인 PID와 매칭되는 소켓 찾기 (최신 우선)
    sockets = sorted(glob_mod.glob(os.path.join(sock_dir, "gui-sock-*")),
                     key=os.path.getmtime, reverse=True)
    for sock in sockets:
        pid = sock.rsplit("-", 1)[-1]
        if pid in running_pids:
            return sock

    # PID 매칭 실패 시 가장 최신 소켓 시도
    return sockets[0] if sockets else None


def run_in_wezterm(cmd):
    """WezTerm에서 새 탭 열고 명령 실행"""
    cli = find_wezterm_cli()
    if not cli:
        raise Exception("WezTerm not found. Install WezTerm or check your PATH.")

    # 1차: wezterm cli spawn → send-text (실행 중인 WezTerm에 새 탭)
    sock = find_wezterm_socket()
    if sock:
        try:
            env = dict(os.environ, WEZTERM_UNIX_SOCKET=sock)
            result = subprocess.run(
                [cli, "cli", "spawn"],
                capture_output=True, text=True, timeout=5, env=env
            )
            if result.returncode == 0:
                pane_id = result.stdout.strip()
                subprocess.run(
                    [cli, "cli", "send-text", "--pane-id", pane_id, "--no-paste"],
                    input=cmd + "\n",
                    capture_output=True, text=True, timeout=5, env=env
                )
                subprocess.run(["open", "-a", "WezTerm"], capture_output=True, timeout=5)
                return
        except (subprocess.TimeoutExpired, OSError):
            pass

    # 2차 fallback: wezterm start (새 프로세스로 실행, 대기하지 않음)
    subprocess.Popen(
        [cli, "start", "--", "bash", "-ic", f"{cmd}; exec bash"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        stdin=subprocess.DEVNULL,
        start_new_session=True
    )


def run_in_terminal(cmd, terminal="iterm"):
    """터미널 설정에 따라 적절한 터미널에서 명령 실행"""
    if terminal == "wezterm":
        run_in_wezterm(cmd)
    else:
        run_in_iterm(cmd)


def run_in_iterm(cmd):
    """iTerm2에서 새 탭 열고 명령 실행"""
    applescript = f'''
    tell application "iTerm2"
        tell current window
            create tab with default profile
            tell current session
                write text "{cmd}"
            end tell
        end tell
        activate
    end tell
    '''

    result = subprocess.run(
        ["osascript", "-e", applescript],
        capture_output=True,
        text=True
    )

    if result.returncode != 0:
        raise Exception(f"AppleScript error: {result.stderr}")


def open_iterm(repo, branch=None):
    """iTerm2에서 새 탭 열고 checkout 실행 (branch가 없으면 디렉토리만 이동) - 하위 호환"""
    repo = sanitize_input(repo)

    if branch:
        branch = sanitize_input(branch)
        cmd = f"z {repo} && git fetch origin && git checkout {branch}"
    else:
        cmd = f"z {repo}"

    run_in_iterm(cmd)


def main():
    try:
        message = read_message()
        if message is None:
            send_message({"success": False, "error": "No message received"})
            return

        # 신규 포맷: { command_template, variables }
        command_template = message.get("command_template")
        if command_template:
            variables = message.get("variables", {})
            terminal = message.get("terminal", "iterm")
            cmd = render_command(command_template, variables)
            run_in_terminal(cmd, terminal)
            send_message({"success": True})
            return

        # 기존 포맷: { repo, branch } (하위 호환)
        repo = message.get("repo")
        branch = message.get("branch")

        if not repo:
            send_message({"success": False, "error": "Missing repo"})
            return

        open_iterm(repo, branch)
        send_message({"success": True})

    except Exception as e:
        send_message({"success": False, "error": str(e)})


if __name__ == "__main__":
    main()
