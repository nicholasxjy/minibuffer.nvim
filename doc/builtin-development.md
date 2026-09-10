# Maintaining builtin pickers

Each picker owns its data collection, item shape, presentation defaults, and
picker-specific actions. Shared behavior lives in a few small modules:

| Module | Responsibility |
| --- | --- |
| `builtin/config.lua` | Resolve defaults, global options, and call overrides; assemble the select session. |
| `builtin/render.lua` | Apply pointer and highlight overrides to an owned copy of renderer output. |
| `builtin/actions.lua` | Bind split/vsplit after session closure, escape file commands, and populate quickfix. |
| `builtin/match.lua` | Fuzzy-match strings or records without losing item identity. |
| `builtin/*-ui.lua` | Picker-specific rows, hints, and decorations. |
| `sessions/select.lua` | Window lifecycle, navigation, selection, scrolling, and asynchronous result delivery. |

Use `config.resolve(opts, defaults)` once at the picker entry point, then pass
the resolved options and session definition to `config.select`. Shared keymaps,
prompt, layout options, and highlights are applied there. Key lists replace
inherited lists, including empty lists that disable actions. Picker-specific
options are validated by the picker; common options use `config/validate.lua`.

Render callbacks may return cached chunks. `render.configure` copies output
once before applying overrides, including nested highlight stacks and window
footer tuples. It preserves nil group headings. Do not mutate source chunks
when applying per-session settings.

Use `actions.bind_open` for split/vsplit: it captures the selected item before
closing and opens it after the original window has been restored. Pass a
complete path to `actions.open_file`. Quickfix filenames are raw data and must
not be escaped as Ex commands; pass an item-to-entry function to
`actions.quickfix`.

Use `match.fuzzy("field")` for record filtering. When multiple fields are
searchable, prepare a search field on each record. Avoid text-to-item lookup
maps: different records can have identical search text. Specialized ranking
(files, diagnostics, grep groups, and manpage prefixes) stays in its picker.

Asynchronous work belongs to a picker invocation, not a module-global variable.
Live grep owns its timer, process, and generation counter per invocation. New
queries and session closure cancel pending work; a resumed session can fetch
again. Late process callbacks check their generation before delivering results.

Run the standalone Neovim scripts for changes in this area:

```sh
for test in builtin_config builtin_actions buffers files live_grep diagnostics; do
  nvim --headless -n -u NONE -i NONE -l "scripts/test_${test}.lua" || exit 1
done
```

The scripts cover configuration precedence, cached rendering, Unicode layout,
selection/actions, duplicate records, paths containing spaces, and independent
asynchronous searches. They require `git`, `rg`, and the plugin's supported
Neovim version.
