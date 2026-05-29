# Design & background (for contributors)

This is **not** user documentation. The product manual lives in [`../docs/`](../docs/). This area
holds the design behind OneTest TMS and the analysis it was built from — for people extending the
platform, the MCP server, or the scripts.

## Contents

- **[`github-native/`](github-native/)** — design of the git-native platform: how OneTest maps
  onto GitHub primitives, the [architecture & delivery](github-native/07-architecture-and-delivery.md)
  model, the [`onetest-tms` spec](github-native/onetest-tms-spec.md), the
  [functions catalog](github-native/functions.md), and the
  [parity audit](github-native/parity-with-onetest.md).
- **Analysis of the original OneTest platform** (reverse-engineered — the source this re-platform
  preserves): [`overview.md`](overview.md), [`functionalities/`](functionalities/),
  [`data-model/`](data-model/).
