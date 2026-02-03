# Roadmap

Note: This is an agent-layer memory file. It is primarily for agent use.

## Purpose
A phased plan of work that guides architecture decisions and sequencing. The roadmap is the “what next” reference; the backlog holds unscheduled items.

## Format
- The roadmap is a single list of numbered phases under `<!-- PHASES START -->`.
- Do not renumber completed phases (phases marked with ✅).
- You may renumber incomplete phases when updating the roadmap (e.g., to insert a new phase).
- Incomplete phases include **Goal**, **Tasks** (checkbox list), and **Exit criteria** sections.
- When a phase is complete:
  - update the heading to: `## Phase N ✅ — <phase name>`
  - replace the phase content with a short bullet summary of what was accomplished (no checkbox list).

### Phase templates

Completed:
```markdown
## Phase N ✅ — <phase name>
- <Accomplishment summary bullet>
- <Accomplishment summary bullet>
```

Incomplete:
```markdown
## Phase N — <phase name>

### Goal
- <What success looks like for this phase, in 1–3 bullet points.>

### Tasks
- [ ] <Concrete deliverable-oriented task>
- [ ] <Concrete deliverable-oriented task>

### Exit criteria
- <Objective condition that must be true to call the phase complete.>
- <Prefer testable statements: “X exists”, “Y passes”, “Z is documented”.>
```

## Phases

<!-- PHASES START -->

## Phase 0 ✅ — AgentPanel reset and cleanup
- Renamed the app/core targets to AgentPanel and removed the legacy CLI.
- Stripped activation/workspace management from the switcher, leaving list + selection logging.
- Updated paths, logging, and docs to the AgentPanel namespace.

## Phase 1 — Reintroduce activation (future)

### Goal
- Define and implement a new activation/workspace pipeline that can be wired to switcher selection.
- Restore user-facing project activation with reliable logging and tests.

### Tasks
- [ ] Design the activation API surface in AgentPanelCore.
- [ ] Implement activation orchestration with tests for success/failure scenarios.
- [ ] Wire switcher selection to activation and update UI messaging.

### Exit criteria
- Switcher selection activates a project in a deterministic way.
- Unit tests cover activation success/failure and basic UI wiring.

## Phase 2 — Rebuild app (nebulous)

### Goal
- Rebuild the AgentPanel app around the `AgentPanelCore` foundation while keeping the switcher + Doctor UI.
- Shrink/flatten the remaining architecture so UI is presentation-only and core logic lives in `AgentPanelCore` (or in Doctor-only code when appropriate).

### Tasks
- [ ] Define the target boundaries for `AgentPanelApp` vs `AgentPanelCore` vs `AgentPanelCLI` and delete/merge anything that doesn't fit.
- [ ] Reduce the switcher implementation to the minimal UX surface (load config, list, filter, log selection) with clean wiring and stable logs.
- [ ] Keep `ap` working end-to-end while simplifying the app (tests, build scripts, and CLI usage remain valid).

### Exit criteria
- `scripts/test.sh` passes.
- AgentPanel menu bar app still launches, switcher still shows the project list, and Doctor UI still renders.
- `ap doctor` still runs and returns a valid report.

## Phase 3 — Packaging + onboarding + documentation polish

### Goal
- Ship a signed/notarized AgentPanel with onboarding that can be followed on a fresh machine without guesswork.
- Ensure `ap doctor` (and in-app Doctor) provides complete setup validation for the supported workflow.

### Tasks
- [ ] Implement signing + notarization for `AgentPanel.app` (and decide whether `ap` is shipped alongside it or distributed separately).
- [ ] Add release scripts: `scripts/archive.sh` (xcodebuild archive/export) and `scripts/notarize.sh` (notarization + stapling) so releases do not require the Xcode GUI.
- [ ] Finalize README: install, permissions, config schema, usage (switcher + `ap`), troubleshooting.
- [ ] Ensure Doctor covers complete setup (AeroSpace app/CLI readiness + compatibility, Chrome + IDE discovery, config validity, required directories/paths).
- [ ] Implement and document distribution via both: Homebrew (recommended) and signed+notarized direct download (`.zip` or `.dmg`).

### Exit criteria
- A fresh macOS machine can be set up using README alone and `ap doctor` reports no FAIL on a correctly configured system.
- Release artifacts can be produced via scripts (no manual Xcode GUI steps required).
