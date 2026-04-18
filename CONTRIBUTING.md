# Contributing to ve-kit

Thanks for the interest. ve-kit is a small, opinionated pattern library — not a framework with a contributor governance model. Here's how to help.

## If you want to report a bug or rough edge

Open an [issue](https://github.com/HuntsDesk/ve-kit/issues) with:
- Which path you used to install (curl-bash / paste-a-prompt / /bootstrap)
- Which Claude Code version + OS
- What you expected vs what happened
- The section of `01-BOOTSTRAP.md` you were following (if applicable)

## If you want to propose a change

Pull requests are welcome for:
- **Documentation fixes** — typos, broken links, unclear steps in any of the top-level `.md` files
- **Sanitizer additions** — if you spot something in the distribution that looks project-specific and should be generic (see [README.md](./README.md) for the sanitization approach)
- **Portability fixes** — if `init.sh` or the skills assume macOS-specific tooling that should be cross-platform
- **New skills** — for the `skills/` directory, following the existing format (see [`skills/plan/SKILL.md`](./skills/plan/SKILL.md) as a reference)

For **larger changes** — new layers, new architectural concepts, renaming — open an issue first to talk through the design before writing code. Pattern libraries are hard to keep coherent if everyone adds their own ideas without coordination.

## If you want to fork

Fork freely. ve-kit is MIT-licensed. If your fork evolves into something meaningfully different, great — cite ve-kit as an inspiration in your README and go your own way.

## Development

ve-kit is distributed from [HuntsDesk/Ask-JDS](https://github.com/HuntsDesk/Ask-JDS) via `git subtree`. The canonical source is `docs/ve-kit/` in that repo; `HuntsDesk/ve-kit` is a force-pushed squashed mirror. This means:

- PRs against `HuntsDesk/ve-kit` can't be merged directly (force-push clobbers them). Instead, the maintainer pulls the changes into Ask-JDS and republishes.
- This is fine for small PRs — the maintainer cherry-picks manually. For larger changes, open an issue first so the maintainer can apply your work in-tree.

If this workflow becomes a friction point for contributors, that's a signal to restructure the distribution — open an issue and say so.

## Code of conduct

Be kind. Assume good faith. Disagree about ideas, not people.

## What's NOT in scope

- Feature requests tied to specific commercial SaaS integrations (ve-kit is Claude-Code-centric by design)
- Anything that'd break the existing three-layer architecture (BOOTSTRAP → Vibe Board → VE Worker) without a compelling case
- Bikeshedding on naming (the `ve-*` prefix is sticky; changes here require a strong argument)

## Companion repo

The Google Workspace MCP piece of the `ve-*` family lives at [HuntsDesk/ve-gws](https://github.com/HuntsDesk/ve-gws) with its own CONTRIBUTING.md.
