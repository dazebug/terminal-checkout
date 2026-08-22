# Signing and permissions

## Reinstalling silently revoked the Accessibility permission

**Type:** incident
**Status:** active
**Evidence:** confirmed
**Source:** app log, 2026-08-21 14:56 — `손쉬운 사용 권한이 없어 Warp 주입 헬퍼를 띄우지 않음`; resolved by `tccutil reset Accessibility com.dazebug.terminal-checkout` plus a re-grant, confirmed at 15:21 by a successful delivery
**Revisit when:** the app gains a stable signing identity (issue #23, #33)

The reported symptom was that Warp opened a tab and started claude but never delivered the scheduled input. The cause was not in the delivery code: the app is signed ad hoc, so its cdhash changes on every rebuild, and an ordinary `./install.sh` had invalidated the existing TCC grant. macOS then answered "not trusted" for a bundle the user could still see listed as allowed in System Settings — and toggling it there did not restore it; the stale row had to be removed with `tccutil` before a re-grant took.

**What changed because of it:** `install.sh` compares the cdhash before and after and runs `tccutil reset Accessibility` only when it actually moved, so the next grant is asked for rather than silently assumed. Separately, a request whose inputs must be typed is now refused *before* the tab is created, rather than opening a tab and reporting success while the input goes nowhere.

**Reason the refusal is up front:** the failure this incident produced was invisible — the button looked like it worked. A request that cannot deliver should fail where the user is looking, which is the button, not the app log.

**Rejected alternative — run the command anyway and skip only the input.** That is what the code did, and it is exactly what made the incident hard to see: the visible half succeeded. Refusing the whole request is louder and loses less.

**Still open:** the underlying churn. A stable local signing identity would stop the grant from dying on every install; it is tracked in issue #33 (with #23 for Hardened Runtime) rather than solved here.
