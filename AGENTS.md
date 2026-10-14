# AGENTS.md

Orientation for AI agents working on this repository.

## Project

Cordis is a dependency injection and reactive lifecycle shard for Crystal: services are provided into a `Cordis::Context`, wrapped in a `LifecycleNode` whose state follows inject-dependency resolution, and effects (side-effect blocks with teardowns) run while the node is active.

Public API surface: `Cordis::Context`, `Cordis::Service`, `Cordis::LifecycleNode`, `Cordis::ReflectService`, `Cordis::RegistryService`, `Cordis::EventsService`, `Cordis::LoggerService`, `Cordis::Injectable`, `Cordis::Any`, `Cordis::Disposable`, `Cordis::CancellationToken`, `Cordis::DisposableList`, and `Cordis::Errors::*`. Usage documentation lives in `README.md`; keep it in sync with every API change.

## Repository layout

- `src/cordis.cr` — entry point: requires all files in dependency order and defines `VERSION` from `shard.yml`.
- `src/cordis/errors.cr` — `Cordis::Errors` module; base class `Errors::Error` and all raiseable error classes.
- `src/cordis/utils.cr` — shared vocabulary: `Injectable` (macro + default), `Any`, `Disposable`, `CancellationToken`, `DisposableList`.
- `src/cordis/logger.cr` — `LoggerService` with nested `Level` enum; level resolved from `"logger"` interception.
- `src/cordis/events.cr` — `EventsService`: `on`/`once`/`emit`/`background`/`parallel`/`serial`/`bail`/`typed`, with nested `HookEntry` and `TypedEvent(T)`.
- `src/cordis/lifecycle_node.cr` — `LifecycleNode` with nested `State` enum and `Effect` class; reactive state machine driven by dependency events.
- `src/cordis/reflect.cr` — `ReflectService` with nested `Impl`; service lookup/provision (`get`, `provide`, `set`, `active?`).
- `src/cordis/registry.cr` — `RegistryService`; named plugin registry.
- `src/cordis/context.cr` — `Context`: root/child contexts, isolation and interception, service getters (incl. `method_missing`).
- `src/cordis/service.cr` — `abstract class Cordis::Service`; creates the node, provides itself, injects dependencies via `Injectable#inject`.
- `src/cordis/macros.cr` — `define_service` macro for typed accessors on `Context`.
- `spec/` — crystal spec suite, one file per source area plus `spec_helper.cr`.
- `example/` — runnable example apps (`app.cr`, `reactive_app.cr`).
- `makefile` — `make spec` (the default target) installs shards and runs the suite.

## Commands

- Install dependencies: `shards install`
- Run the spec suite: `crystal spec` (or `make spec`)
- Type-check examples without linking: `crystal build --no-codegen example/app.cr example/reactive_app.cr`
- Formatting: the repo uses column-aligned assignments (`property uid             : Int32?`), which `crystal tool format` does not preserve — do not run the formatter as a gate; match the surrounding style by hand.

## Code standards

- Compiler-friendly, performance-focused, idiomatic Crystal; data-driven design.
- No comments in code, with one exception: every source file starts with a comment containing its path (`# src/cordis/logger.cr`).
- The usage-facing API must be ergonomic.
- Never use `out` as an identifier — it is a reserved keyword.
- Never touch the `version` field in `shard.yml`; version bumps are proposed by the `dev` tool during `dev save` or done by the maintainer directly.
- Keep related types nested under their owning type (`LifecycleNode::State`, `ReflectService::Impl`, `Errors::*`, `LoggerService::Level`); avoid re-opening one type's logic across many files (no shotgun surgery).

## Git workflow

Two-branch model: `dev` is the only workplace (every commit is pushed), `main` is a release target holding one squash-merged commit per release. Branches are never deleted, never `reset --hard`, never force-pushed by hand. Use the `dev` command for everything: `dev open` (get onto `dev`), `dev save -m "..."` (commit + push, refuses on `main`), `dev undo [--hard]` / `dev undo --to REV`, `dev release` (backup, squash-merge into `main`, reconcile `dev`, tag `v<version>` from `shard.yml`), `dev release --edit-title -m "..."` (the only sanctioned history rewrite, on `main`'s tip), `dev backup` / `dev backup --restore`, `dev status`. Releases with changed content need a new `version` in `shard.yml` first; published tags are never deleted.
