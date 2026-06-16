```
 ███╗   ███╗ ██████╗██████╗ ██████╗
 ████╗ ████║██╔════╝██╔══██╗██╔══██╗
 ██╔████╔██║██║     ██████╔╝██║  ██║
 ██║╚██╔╝██║██║     ██╔═══╝ ██║  ██║
 ██║ ╚═╝ ██║╚██████╗██║     ██████╔╝
 ╚═╝     ╚═╝ ╚═════╝╚═╝     ╚═════╝
    [ m c p   s e r v e r s,   n a t i v e ]
```

[![CI](https://github.com/MenkeTechnologies/stryke-mcpd/actions/workflows/ci.yml/badge.svg)](https://github.com/MenkeTechnologies/stryke-mcpd/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![stryke](https://img.shields.io/badge/stryke-package-cyan.svg)](https://github.com/MenkeTechnologies/strykelang)

### `[MCP SERVERS WITHOUT A RUNTIME]`

> *"Every MCP server today drags a Node runtime or a Python venv to the target machine. This one is a single static native binary."*

`stryke-mcpd` is the policy layer for writing MCP (Model Context Protocol) servers in stryke: validated tool specs (`Mcpd::Schema`), crash-isolated serving with file-only logging (`Mcpd::Server`), a root-jailed stock tool pack (`Mcpd::Tools`), and result-envelope helpers for round trips (`Mcpd::Client`). The protocol plumbing — `mcp_server_start`, `mcp_connect`, `mcp_call`, the `tool fn` / `mcp_server` desugar — is strykelang core. Write the server in a few lines, `s build --release` it, ship one binary. No `[ffi]` table, no cdylib, no helper binary — just `.stk` modules loaded on `use Mcpd`. Created by MenkeTechnologies.

### [`strykelang`](https://github.com/MenkeTechnologies/strykelang) &middot; [`MenkeTechnologiesMeta`](https://github.com/MenkeTechnologies/MenkeTechnologiesMeta) · [`stryke-utils`](https://github.com/MenkeTechnologies/stryke-utils) · [`stryke-fleet`](https://github.com/MenkeTechnologies/stryke-fleet)

---

## Table of Contents

- [\[0x00\] Why a Package, Not Core](#0x00-why-a-package-not-core)
- [\[0x01\] Install](#0x01-install)
- [\[0x02\] Quick Start](#0x02-quick-start)
- [\[0x03\] Sublibraries](#0x03-sublibraries)
- [\[0x04\] What's NOT in Here](#0x04-whats-not-in-here)
- [\[0x05\] CLI](#0x05-cli)
- [\[0x06\] Tests](#0x06-tests)
- [\[0x07\] Layout](#0x07-layout)
- [\[0xFF\] License](#0xff-license)

---

## [0x00] Why a Package, Not Core

The protocol is already core: `mcp_server_start` serves stdio JSON-RPC, `mcp_connect`/`mcp_tools`/`mcp_call`/`mcp_close` are the client side, and the `tool fn` / `mcp_server "name" { ... }` desugar exists at the source level. What core does NOT impose is discipline, and MCP servers need exactly two pieces of it:

1. **stdout belongs to the protocol.** One stray `print` corrupts the JSON-RPC stream for every connected client. `Mcpd::Server::log_to` routes diagnostics to a file; `tests/repo-contract.sh` greps `lib/` and fails CI if anything in this package ever writes to stdout.
2. **A dying tool must not kill the server.** Every `run` coderef is wrapped: a `die` comes back to the client as an `ERROR: ...` text result, the failure is logged, and the server keeps serving. The round-trip test pins this — call a tool that dies, then call another tool on the same connection.

Plus the parts everyone rewrites per server: construction-time spec validation with named diagnostics (`Schema`), arg checking against declared types (`check_args`), a root-jailed filesystem/shell tool pack (`Tools`), and result-envelope extraction (`Client`).

## [0x01] Install

```sh
# From a release:
s pkg install -g github.com/MenkeTechnologies/stryke-mcpd

# From a local checkout:
git clone https://github.com/MenkeTechnologies/stryke-mcpd
cd stryke-mcpd
s pkg install -g .              # installs into ~/.stryke/store/stryke-mcpd@<version>/

# Or via Makefile:
make install
```

No cargo step. No cdylib. The installed store directory contains only `stryke.toml` + `lib/*.stk` — no compiled artifacts, fully portable across platforms.

## [0x02] Quick Start

```perl
use Mcpd

# A server is one call: validated specs in, stdio JSON-RPC out.
Mcpd::Server::log_to("$ENV{HOME}/.cache/calc.log")   # stdout stays clean
Mcpd::Server::serve("calc", [
    Mcpd::Schema::tool("add", "Add two numbers",
        +{ a => "number", b => "number" },
        sub { val $args = shift; $args->{a} + $args->{b} }),

    @{ Mcpd::Tools::all(+{ root => getcwd() }) },     # stock pack, jailed
])
```

```perl
# Client side — round trip any server over stdio:
val $h = mcp_connect("stdio:stryke calc_server.stk")
p join(", ", @{ Mcpd::Client::tool_names($h) })
p Mcpd::Client::call_text($h, "add", +{ a => 2, b => 40 })   # 42
p Mcpd::Client::is_error(mcp_call($h, "always_fails", +{}))  # 1 — server still alive
mcp_close($h)
```

```sh
# Ship it: AOT-compile the server to a single static native binary.
s build --release          # target/release/<name> — no interpreter on the target
```

## [0x03] Sublibraries

| # | Module | File | Fns | Highlights |
|---|--------|------|----:|------------|
| 1 | `Mcpd::Schema` | `lib/Schema.stk` | 13 | `tool` (validated spec) · `check_args` (type-checked args) · `validate_all` (unique names, full specs) · `types` · `param_names` · `to_json_schema` (MCP inputSchema) · `from_json_schema` (inputSchema → params, inverse) · `to_tool_list` (MCP tools/list payload) · `from_tool_list` (tools/list → descriptors, inverse) · `tool_map` (name → spec dispatch index) · `tool_summary` · `describe` (catalog) · `rename` |
| 2 | `Mcpd::Server` | `lib/Server.stk` | 7 | `serve` (validate + wrap + `mcp_server_start`) · `wrap` (die → `ERROR:` envelope) · `wrap_all` · `audit` (log successes) · `log_to`/`log`/`log_path` (file-only diagnostics) |
| 3 | `Mcpd::Tools` | `lib/Tools.stk` | 19 | `fs_read` · `fs_list` · `fs_grep` · `fs_find` (recursive, capped) · `fs_stat` · `fs_head` (first N lines) · `fs_tail` (last N lines) · `fs_exists` · `fs_lines` (wc) · `fs_write` · `fs_append` · `fs_mkdir` · `sh_exec` (allowlist) · `env_get` · `time_now` · `sys_info` · `all` (`readonly` mode) · `jail` (root confinement) · `names` |
| 4 | `Mcpd::Client` | `lib/Client.stk` | 10 | `text` (envelope → string) · `texts` (unjoined blocks) · `content_types` · `content_of_type` (full blocks of a type) · `call_text` (call + extract) · `is_error` · `error_message` (strip prefix) · `tool_names` · `has_tool` · `tool_schema` (a tool's advertised inputSchema) |

## [0x04] What's NOT in Here

By design — these are stryke builtins, so we don't re-wrap them:

| Category | Builtins (call directly) |
|----------|--------------------------|
| Server plumbing | `mcp_server_start` · `mcp_serve_registered_tools` · `ai_register_tool` and the `tool fn` / `mcp_server "name" { ... }` source-level desugar |
| Client plumbing | `mcp_connect` · `mcp_tools` · `mcp_resources` · `mcp_prompts` · `mcp_call` · `mcp_resource` · `mcp_prompt` · `mcp_close` |
| AI attachment | `mcp_attach_to_ai` · `mcp_detach_from_ai` · `mcp_attached` |
| File / process | `slurp` · `spurt` · `getcwd` · `qx(...)` · `opendir`/`readdir` |

If a function in this library can be replaced with one builtin call, it's a bug.

## [0x05] CLI

```sh
s bin/mcpd.stk new myserver            # write ./myserver.stk skeleton (validated, logged, ready)
s bin/mcpd.stk serve-stock /srv/data   # stock pack jailed to /srv/data, served on stdio
s bin/mcpd.stk tools                   # list the stock tool pack
s bin/mcpd.stk version
s bin/mcpd.stk help
```

Wire a server into any MCP client config as `{ "command": "stryke", "args": ["server.stk"] }` — or build it and point at the binary with no args at all.

## [0x06] Tests

```sh
s test t/                       # assertions across every public function
```

`t/test_mcpd.stk` asserts Schema/Tools/Client as pure functions (spec validation, arg checking, jail escapes, envelope parsing), then runs a live round trip: it generates a server script, serves it over stdio via `mcp_connect`, lists tools, calls one, kills one, and proves the server survived. Headless-CI safe — everything happens on the local machine.

## [0x07] Layout

```
stryke-mcpd/
├── stryke.toml                # pure-stryke package manifest (no [ffi])
├── Makefile                   # test / install / clean
├── LICENSE                    # MIT
├── lib/
│   ├── Mcpd.stk               # `use Mcpd` — pulls all four sublibs
│   ├── Schema.stk             # `use Mcpd::Schema` — validated tool specs
│   ├── Server.stk             # `use Mcpd::Server` — crash-isolated serving
│   ├── Tools.stk              # `use Mcpd::Tools`  — root-jailed stock pack
│   └── Client.stk             # `use Mcpd::Client` — result-envelope helpers
├── bin/
│   └── mcpd.stk               # CLI front-end (new / serve-stock / tools)
├── t/
│   └── test_mcpd.stk          # pure asserts + live stdio round trip
├── examples/
│   ├── calc_server.stk        # minimal server (the round-trip target shape)
│   ├── round_trip.stk         # client: list, call, error envelope, survival
│   ├── stock_server.stk       # stock pack jailed to cwd
│   └── jailed_fs.stk          # live write/read + a blocked jail escape over stdio
├── tests/                     # shell gate scripts (CI lints)
└── docs/                      # GitHub Pages site
```

## [0xFF] License

MIT — see [LICENSE](LICENSE).
