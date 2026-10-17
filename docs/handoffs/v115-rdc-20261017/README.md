# v115 RDC handoff — unfinished production integration

Start with [HANDOFF_TO_PRO_20261017.md](HANDOFF_TO_PRO_20261017.md). World remains FAIL; no115 game APK exists. This branch preserves actual dirty-source progress, not a release.

On the same PC use existing R/E and outputs paths in that report. `REMOTE_EVIDENCE_MAP.json` pins the exact original path and SHA of each supplemental copy. `continuation_tools/` files are archival copies: their original relative directory depth and local upstream receipts matter; do not execute arbitrary relocated copies or overlay a whole tree. Reconcile exact files by recorded SHA if reconstruction is necessary.

`engine_delta/` contains the95 actual engine changed files at engine base5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88, including modules/hardcore_simulation. It is an additive source preservation set, not a separate buildable engine checkout. Existing engine and Android artifacts remain on the RDC machine. No signing keys, real-user save corpus, local engine binaries, toolchains or APKs are uploaded.

Next work: fix Source monster birth input cache using the new RED test, implement strict viewport identity handoff on actual Native map-arrival commit, pass full World and normal exit, run six180s original-save warehouse stages, then fix full-assets release binding and build compatible115.
