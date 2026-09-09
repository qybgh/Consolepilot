# Repository Guidelines

Consolepilot is a macOS (Apple Silicon, macOS 14+) tool for cross-app background Actions plus AI chat/CLI/HTTP over one engine. **Read [Docs/PLAN.md](Docs/PLAN.md) (current P0/P1 execution plan, decisions D1–D8) and [Docs/GATE0-CONFIRMATION.md](Docs/GATE0-CONFIRMATION.md) before production changes.** P0 (XcodeGen migration + clean skeleton) is complete; P1 (8-target split + Provider/Action reliability) is in progress. Writing rules: [Docs/CODING-STYLE.md](Docs/CODING-STYLE.md).

## Project Structure & Module Organization

- `project.yml` is the only editing source for the Xcode project; run `make xcodegen` after changing it (drift is checked by `make lint`). Generated `Consolepilot.xcodeproj` is committed.
- `Sources/Domain/` — models/stores today, plus new contract shells: `Repositories/` (Session/Usage/CaptureAudit/Configuration repository protocols) and `UseCases/` (`ConversationUseCase`, `ActionExecutionUseCase` protocols + value types).
- `Sources/Application/` — use-case placeholder implementations (`…UseCasePlaceholder`, throw `AppError.notImplemented`); P1 wires them.
- `Sources/Infrastructure/` `Rendering/` `Transport/` — one Core framework target today; P1-A splits into Domain/Application/Infrastructure/SystemIntegration.
- `Sources/App/` — SwiftUI `@main` app + AppKit bridges (legacy UI slated for P2 removal). `Sources/CLI/` — CLI. `Tests/` — XCTest. `Docs/` — plan, progress, guides.

## Build, Test, and Development Commands

- `make bootstrap` — verify Xcode/toolchain/architecture (one-time).
- `make test` — full XCTest via `xcodebuild test` (GUI session must be all green; 3 clipboard/Keychain tests fail only in restricted shells).
- `make lint` — swift-format strict + SwiftLint strict + `xcodebuild analyze` + secret scan + periphery + xcodeproj drift check.
- `make build` / `make release VERSION=x.y.z` / `make clean` — Debug build; signed ZIP + SHA-256 manifest into `dist/`; cleanup.

## Coding Style & Naming Conventions

- Swift 6 strict concurrency; value types (`Sendable struct` + `Equatable`) first; shared mutable state in actors; UI/coordinators `@MainActor final class`; every started `Task` has an owner, cancellation path, terminal state, and test.
- Protocols carry no `Protocol` suffix (`SessionRepository`, `ConversationUseCase`); one main type per file; UI copy in Chinese with stable `accessibilityIdentifier`.
- New errors follow the layered `AppError` style with stable `code`, `userMessage`, `recoverySuggestion`, and sanitized `diagnostic`. Banned in production: force unwraps, `fatalError`, `try!`, silent `try?`, `[String: Any]` DTOs, unowned `Task`s, plaintext secrets.
- Format: 4-space indent, 120 columns (`.swift-format`); SwiftLint strict. Run `swift-format format --in-place --recursive Sources Tests` before committing.

## Testing Guidelines

- Framework: XCTest; files `<Area>Tests.swift`, methods prefixed `test`, Arrange/Act/Assert sections.
- Baseline: 83 tests (`make test`). Use fakes/in-memory doubles; never real network, Keychain entries, user clipboard, or existing databases.
- Contract shells are pinned by tests so the dead-code gate (periphery, P1-F) doesn't report them as unused.

## Commit & Pull Request Guidelines

- Conventional Commits prefixes (`feat:`, `refactor:`, `style:`, `test:`, `chore:`, `docs:`); one logical change per commit; docs changes are separate commits.
- Branch prefix `codex/`. PRs link the issue, state what/why, include `make test` + `make lint` output and UI screenshots; never attach keys or captured content.

## Security & Configuration Tips

- `config.toml`, `*.secret.toml`, `.env` are gitignored; API keys only via Keychain/env-var references. Logs, tests, and diagnostics never contain Authorization headers, keys, or captured text.
- Capture audit logs metadata only (source app, character count, strategy, duration) — never content.

## Agent-Specific Instructions

- P1-A–F scope is fixed: 8-target split, repository/use-case wiring, Provider contract + fixtures, Action lifecycle (`sessionMode`/`timeoutSec`), config field disposals (`launchAtLogin`/`toggleHotkey` delete, `attachTo` migration error, `tails` out of scope, 6 UI fields to P2).
- Delete any deprecated field/module/page only after a full-repo reference search (sources, tests, docs, config, scripts).
- Update `Docs/PLAN.md` / `Docs/PROGRESS.md` when phase status changes.
