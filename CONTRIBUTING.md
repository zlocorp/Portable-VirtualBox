# Contributing

Work in `dev/modernization-2026`; keep PR #7 Draft. Do not merge to historical master, publish releases or test privileged code on a user's working PC without authorization.

Deliver functioning changes with appropriate behavioral tests. Update CHANGELOG for user-visible changes and FEATURES when a capability's status changes; keep public features, CI experiments and future work distinct. The README is a product overview, not a transcript of every test run.

Reuse suitable fork/PR code directly and adapt its interfaces to this project. Preserve useful implementation rather than rewriting it merely for uniform style. Replace incompatible or unsafe operations specifically, and test the resulting public flow. A note in a plan does not count as adoption.

Preserve LICENSE.md and original source headers. Record actual external code/assets and significant adaptations in CREDITS.md with source revision and license where applicable. Keep detailed research links in the repository, not in the GUI. Do not add credits for merely reading a page, and do not duplicate the same contributor list across screens/documents. The ZIP copies the existing LICENSE and consolidated CREDITS files.

Do not restore obsolete bundled tools, import unverified binaries or kill unrelated processes by name. Current build instructions are in BUILDING.md.
