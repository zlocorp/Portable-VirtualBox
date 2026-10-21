# Contributing to the modernization

Work on `dev/modernization-2026`; keep PR #7 Draft until its acceptance criteria pass. Do not merge to historical master, publish a release or test privileged flows on a user's working machine without explicit authorization.

For each feature or external adaptation:

- Implement a real public behavior or a required runtime operation, not only an unconnected helper. Add behavioral tests, run the Python suite and relevant native/compiled Windows checks, and report skipped or unverified environments.
- Update [CHANGELOG.md](CHANGELOG.md) under **Unreleased** and [FEATURES.md](FEATURES.md). Keep public, CI-only and planned statuses distinct; update both READMEs when public behavior changes.
- Record sources and authors in [CREDITS.md](CREDITS.md) and [docs/COMMUNITY-ADOPTION.md](docs/COMMUNITY-ADOPTION.md). Direct code imports require exact source revision, preserved copyright/license notices, identified modifications and appropriate license text. Independently adapted ideas must be described as such.
- Preserve [LICENSE.md](LICENSE.md). Update [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for dependency/distribution changes. The original noncommercial/share-alike terms are not silently replaced by a different license.
- Keep attribution notices in the diagnostic archive. Do not restore old bundled compilers/tools, import unverified release binaries, force-kill processes by name, or treat environment markers as an access-control boundary.

Current build commands are in [BUILDING.md](BUILDING.md). Long execution logs belong in dated `docs/EXECUTION-*.md` reports; the README is a product overview, not an accumulating CI transcript.
