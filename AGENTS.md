# Repository Guidelines

Consolepilot is a macOS (Apple Silicon, macOS 14+) tool for cross-app background Actions plus AI chat/CLI/HTTP over one engine. **Read [Docs/PLAN.md](Docs/PLAN.md) (current execution plan, D1–D8) and [Docs/GATE0-CONFIRMATION.md](Docs/GATE0-CONFIRMATION.md) (Gate 0 evidence) before production changes.** P0 (SwiftPM → Xcode migration) has not started; the repo is still SwiftPM.

## Project Structure & Module Organization

- `Package.swift` (Swift tools 6.0): targets `ConsolepilotCore` (`Sources/` minus App/CLI), `Consolepilot` (App), `ConsolepilotCLI`, `ConsolepilotTests`.
- `Sources/` — `Domain`, `Infrastructure`, `Transport`, `Rendering`, `App`, `CLI` (one Core target today; Xcode split planned).
- `Tests/` — XCTest suites (`TransportTests`, `ServerTests`, `DatabaseTests`, …). `Spikes/` — throwaway, not shipped.
- `Docs/` — plan, reports, guides. `.idea/` and `*.iml` are gitignored; never commit IDE files.

## Build, Test, and Development Commands

- `./Scripts/bootstrap.sh` — verify Xcode, Swift 6+, and required tools.
- `./Scripts/build-local.sh` — build the local app binary.
- `./Scripts/test.sh` — clean + run all tests (`swift test -j 1`).
- `swift test --disable-sandbox` — required in the restricted Codex shell; 3 clipboard/Keychain tests fail only there.
- `./Scripts/lint.sh` — swift-format `--strict` + SwiftLint `--strict` (+ Periphery if installed).
- `./Scripts/sign.sh` / `install-cli.sh` — ad-hoc signing / CLI install. Planned (PLAN §4 P0): root `Makefile` becomes the only command entry.

## Coding Style & Naming Conventions

- Swift 6 strict concurrency; MVVM + use cases; views never touch DB/Provider/Keychain/Server directly.
- `.swift-format`: 4-space indent, 120-char lines. Run `swift-format format --in-place --recursive Sources Tests`.
- SwiftLint is `strict` (incl. `force_unwrapping`, `fatal_error_message`); production code bans force unwraps, `fatalError`, silent `try?`, and `[String: Any]` DTOs.
- lowerCamelCase; stable `accessibilityIdentifier`s on interactive controls.

## Testing Guidelines

- Framework: XCTest. Files `<Area>Tests.swift`; methods prefixed `test`.
- Run `./Scripts/test.sh` (or `swift test --disable-sandbox` in sandboxed shells). Baseline: 77 tests.
- PLAN §5 gates: tests must not depend on real network, Keychain entries, user clipboard, or existing databases; regression cases run ≥20×.

## Commit & Pull Request Guidelines

- History uses Conventional Commits prefixes (`chore:`, `docs:`, …); short imperative subjects; one logical change per commit (docs separate from tooling changes).
- Branch prefix: `codex/`. PRs: link the issue, state what/why, include test/lint output and UI screenshots; never attach keys or captured content.

## Security & Configuration Tips

- `config.toml`, `*.secret.toml`, `.env` are gitignored; API keys only via Keychain/env-var references.
- Logs, tests, and diagnostics must never contain Authorization headers, keys, or captured text.
- No app-internal data-clear page (D8); mvp SQLite cleanup is a manual one-time step.

## Agent-Specific Instructions

- Read PLAN §0 before writing production code; do not start P0 until its step-1 checklist is confirmed.
- Field dispositions: delete `launchAtLogin`/`toggleHotkey`; `attachTo` → `sessionMode` (migration error); `tails` out of scope this round; `theme`/fonts/`opacity`/`alwaysOnTop` land in P2.
- Update `Docs/PLAN.md` / `Docs/PROGRESS.md` when phase status changes.
