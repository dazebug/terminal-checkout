# Contributing

Thanks for your interest in Terminal Checkout!

## Getting started

```bash
git clone https://github.com/dazebug/terminal-checkout.git
cd terminal-checkout
```

## Tests

```bash
swift test --package-path app   # Core unit tests
node --test                     # extension (JS) tests — from the repo root
app/build.sh && app/e2e.sh      # build + relay ↔ socket ↔ server round-trip (headless)
```

All of the above run in CI on every pull request.

## Before you change code

- Read [`CLAUDE.md`](CLAUDE.md) first. It is the canonical engineering-constraints document for humans and AI agents alike (`AGENTS.md` is a symlink to it): architecture constraints and empirically measured pitfalls this project depends on — in particular the TCC responsible-process split and the claude-input injection gates, which must not be weakened. If you edit `CLAUDE.md` files, enable the symlink-sync hook with `git config core.hooksPath .githooks` (optional otherwise).
- Neither the unit tests nor e2e ever opens a real terminal, so changes to terminal-control paths need hands-on verification. Adding support for a new terminal? Follow [`docs/new-terminal-checklist.md`](docs/new-terminal-checklist.md), including its hands-on checklist.
- Parts of `app/` are still commented in Korean; an English pass is planned. New code, comments, and PRs should be in English.

## Adding a language

Add its app tag to `supportedLocales` (`app/Sources/Core/Localization.swift`) and `TC_I18N_LOCALES` (`extension/i18n.js`), add `app/Sources/App/Resources/<tag>.lproj/` with `Localizable.strings` and `InfoPlist.strings`, add `extension/_locales/<chrome-code>/messages.json` with the extension's name and description, and add its `CHROME_LOCALE_DIRECTORIES` and baseline-hash entries in `tools/check-locales.js` — Chrome will not read those from anywhere else, and its directory is named in **Chrome's** locale codes rather than ours (`zh-Hans` is `zh_CN` there, `zh-Hant` is `zh_TW`). The catalogue tests, checker and bundle gate validate consistency once each declaration is present; an independent list cannot infer a tag omitted from another, so run all five gates after adding one.

`_locales` is the canonical, hand-edited translation store; `node tools/check-locales.js` checks name parity and argument bindings against `en` and never writes it. A changed `_locales` file must be reviewed as an intentional translation edit or an unintended structural change before its committed baseline pin is updated. One structural rule has no VM gate: an extension-root name may not start with `_` unless Chrome owns it (`_locales`) — Chrome refuses to load the folder otherwise, and only the real loader enforces it, so the test suite pins the rule by listing the root. Values are never translated for anything that reaches a shell — see the `ShellPayload` type and the translation notice in the README's [Language](README.md#language) section.

## README translations

`README.ko.md`, `README.zh-Hant.md` and `README.ja.md` are full translations of `README.md`. When `README.md` changes, update them in the same pull request where you can. Each translation's first line is an HTML comment naming the English commit it was last brought up to, so a translation that has fallen behind can be told from a current one. Keep each translation line-for-line with the English: the same lines, code, links and anchors. Quote on-screen labels the way that language's UI shows them (`Localizable.strings`, `_locales`, and Chrome's and macOS's own wording). Move the commit in the comment when you bring a translation up to date.

## Pull requests

Keep PRs focused, and describe what you verified — which tests you ran and which hands-on checks you performed.
