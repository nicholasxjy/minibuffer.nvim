# Files matcher and performance

The builtin files picker uses `minibuffer.fuzzy.new_snacks`. Its forward scan,
gap/consecutive scoring, query modifiers, and default score/text-length/index
ordering are checked against Snacks at commit
[`882c996cf28183f4d63640de0b4c02ec886d01f2`](https://github.com/folke/snacks.nvim/tree/882c996cf28183f4d63640de0b4c02ec886d01f2/lua/snacks/picker).
The relevant upstream definitions are
[`smart`](https://github.com/folke/snacks.nvim/blob/882c996cf28183f4d63640de0b4c02ec886d01f2/lua/snacks/picker/config/sources.lua),
[`matcher`](https://github.com/folke/snacks.nvim/blob/882c996cf28183f4d63640de0b4c02ec886d01f2/lua/snacks/picker/core/matcher.lua),
and [`score`](https://github.com/folke/snacks.nvim/blob/882c996cf28183f4d63640de0b4c02ec886d01f2/lua/snacks/picker/core/score.lua).
Snacks is not a runtime dependency. The existing `minibuffer.fuzzy.new` matcher
continues to serve the fzf integration without changing its scoring behavior.

The picker retains its sources, cwd filtering, frecency store, keymaps, prompt,
pointer, highlighting options, and Git decorations. `git_changed_first` remains
a stable partition after fuzzy ranking. Ignored files are not promoted. The
existing directory-boundary check for cwd bonuses is retained.

## Work avoided

- Resolve optional icon providers once per invocation, including absent providers.
- Reuse Git status for parent directories and avoid repeated relative-path work.
- Normalize unusual scan paths; use already-canonical rg paths directly.
- Reuse normalized absolute paths when looking up frecency.
- Cache lowercase fields and text-length/source-index ordering per candidate set.
- Rank by score buckets, preserving the cached tie order inside each bucket.
- For plain query extensions, match only previous matches. Backspacing and query
  modifiers fall back to the full candidate set.
- Compute fuzzy highlight positions only for visible rows, using the same matcher
  as ranking, and reuse them when selection changes without changing the query.

Candidate records are immutable within a files invocation. A new candidate array
or changed count rebuilds ordering caches. Callers of `new_snacks` that change
record text, paths, or source indices must create a new ranker. Every files
invocation still rescans files and Git status; no stale cross-invocation scan
cache is introduced.

## Validation

`scripts/test_snacks_matcher.lua` compares scores, result order, and highlight
positions against the upstream matcher. It includes deterministic randomized
paths, Unicode, long inputs, smartcase, exact/word queries, anchors, AND/OR,
inverse terms, field queries, and multiple matcher option combinations. Separate
comparisons exercise cwd/frecency bonuses with a fixed store.

```sh
SNACKS_REFERENCE=/path/to/snacks.nvim nvim --headless -n -u NONE -i NONE \
  -l scripts/test_snacks_matcher.lua
nvim --headless -n -u tests/minimal_init.lua -i NONE -l tests/run.lua
nvim --headless -n -u NONE -i NONE -l scripts/test_files.lua
```

Validation for this change: 178,080 candidate/query comparisons, 38 general
tests, and the six builtin regression scripts. Neovim 0.11.3 was used for
standalone render scripts with the existing command-window test stubs; the
general suite passed on `v0.13.0-dev-1583+gd039f19af5`. That nightly exits with a
`grid_line_flush` assertion after the live-grep assertions pass; the same exit
failure reproduces at the unchanged baseline. The live-grep script exits
successfully on 0.11.3.

## Reproducible CPU benchmark

`scripts/bench_files.lua` generates 20,000 deterministic paths and substitutes
fixed asynchronous rg/Git output. It measures candidate preparation plus empty
ranking, eight queries, and a fuzzy-highlight query plus formatting 15 rows.
Frecency is disabled to avoid dependence on a user's history. The icon provider
is a deterministic stub when `MINIBUFFER_BENCH_ICONS=1`.

Measurements below are medians of three runs on the same environment using
Neovim 0.11.3, with the icon provider enabled. The baseline is `6b033ab`.

| CPU workload | Baseline | Updated |
| --- | ---: | ---: |
| Candidate preparation + empty ranking | 2711 ms | 405 ms |
| Eight queries | 2294 ms | 208 ms |
| Highlight query + 15 formatted rows | 454 ms | 73 ms |

These numbers exclude real filesystem scans, Git subprocess time, and terminal
painting. They measure picker CPU work, not end-to-end opening latency.

```sh
MINIBUFFER_BENCH_ICONS=1 MINIBUFFER_BENCH_RTP=/path/to/baseline \
  nvim --headless -n -u NONE -i NONE -l scripts/bench_files.lua
MINIBUFFER_BENCH_ICONS=1 \
  nvim --headless -n -u NONE -i NONE -l scripts/bench_files.lua
```

Set `MINIBUFFER_BENCH_COUNT` to change dataset size. Omit
`MINIBUFFER_BENCH_ICONS` to measure the no-provider case.
