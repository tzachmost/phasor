# Agent guidance

- Read `docs/architecture.md`, `docs/shell-spec.md`, and `docs/plugin-api.md` before changing core contracts or plugin loading.
- Keep shell and core independent of a particular distribution. Isolate package-manager behavior in `package/` and install helpers.
- Do not add dependencies without documenting why they are needed.
- Do not mutate unrelated user dotfiles or replace MangoWM. Manage only Phasor-owned paths.
- Do not redesign UX without an explicit product decision. Keep temporary integrations replaceable.
- Preserve versioned service and plugin APIs. Document new configuration keys in `config/schema/` and `docs/`.
- Prioritize a working, reloadable UI and fast development iteration.
- Add focused tests where practical; avoid requiring MangoWM to exercise service logic.
- Use `~/Work/phasor` as the default checkout. Keep secrets out of repository files and defaults.
- Do not broaden agent or system permissions silently.
- Never target Omarchy-specific behavior. The first real desktop validation target is a fresh CachyOS install.
