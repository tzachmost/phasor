# Development Handoff

Use this page to resume Phasor work in a new coding session. The public repository is [github.com/tzachmost/phasor](https://github.com/tzachmost/phasor), on the `main` branch. Read this page together with [the roadmap](roadmap.md) and [the architecture](architecture.md).

## Current state

The v0.1 foundation is implemented and pushed. It includes the MangoWM session supervisor, Quickshell plugin host and Launcher, Python core services over local IPC, Mango windows and Spaces integration, app discovery and launch, Home file search and basic file actions, system status/control adapters, diagnostics, install scripts, and an Arch package recipe. The one-command CachyOS/Arch setup is in the README.

The latest published implementation checkpoint is commit `dbfd629` (`chore(install): add one-command CachyOS setup`). Check `git status` and `git log` before continuing, since this handoff can outlive that checkpoint.

## Validation status

- The 23 Python unit tests passed at the last implementation check.
- Python compilation, shell syntax, JSON parsing, and `git diff --check` passed.
- A mocked session supervisor completed startup and shutdown.
- A headless Quickshell probe loaded the configuration, but the current environment has no Mango/Wayland compositor, so a live session was not verified.
- The installer has not been run on a fresh CachyOS machine. Fresh CachyOS validation is still required before calling the desktop session validated.

## Suggested next steps

1. Validate on a fresh CachyOS/Arch desktop: follow the one-line setup in the README, select the Phasor login session, and record/fix any installation or startup failures. Do not treat the headless probe as a substitute for this.
2. Add an in-shell Space indicator and switcher. The core Space API and Mango keyboard shortcuts already exist; see [the shell spec](shell-spec.md) and [shortcuts](shortcuts.md).
3. Connect theme and reduced-motion settings to the existing QML theme tokens.
4. Complete the file action menu with rename, delete, share, and copy-file actions. Update the docs and focused coverage as each action lands.
5. Keep [the roadmap](roadmap.md) current as items are completed or reprioritized.

## Useful commands

From an existing development checkout:

```bash
git status --short
git pull
./scripts/doctor
```

For a fresh CachyOS/Arch install, use the single command in the README rather than this development-checkout sequence.
