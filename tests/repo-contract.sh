#!/usr/bin/env bash
# stryke-mcpd-specific repo-contract gate.
#
# Pins the package layout claimed in README.md `[0x07] Layout` and
# stryke.toml. Drift (a lib file disappears, an example loses its
# shebang, a sublib forgets `package Mcpd::Foo`) breaks the contract
# and CI fails.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
ok=1

# ── lib/*.stk: every sublib non-empty ───────────────────────────────
empty=0
while IFS= read -r f; do
    [[ -s "$f" ]] || { echo "FAIL  empty: $f"; empty=$((empty+1)); ok=0; }
done < <(find lib -maxdepth 1 -name "*.stk" -type f 2>/dev/null)
lib_count=$(find lib -maxdepth 1 -name "*.stk" -type f 2>/dev/null | wc -l | tr -d ' ')
[[ $empty -eq 0 ]] && echo "PASS  every lib/*.stk non-empty ($lib_count files)"

# ── lib roster pinned at exactly 5 files (umbrella + 4 sublibs) ─────
expected_libs=(Mcpd Schema Server Tools Client)
missing_lib=""
for n in "${expected_libs[@]}"; do
    [[ -f "lib/${n}.stk" ]] || { missing_lib="$missing_lib ${n}.stk"; ok=0; }
done
if [[ -z "$missing_lib" ]]; then
    echo "PASS  lib/ contains Mcpd + 4 sublibs (Schema/Server/Tools/Client)"
else
    echo "FAIL  lib/ missing:$missing_lib"
fi
if [[ $lib_count -ne 5 ]]; then
    echo "FAIL  lib/ has $lib_count .stk files, expected exactly 5"
    ok=0
fi

# ── each sublib declares its `package Mcpd::<Name>` correctly ───────
pkg_bad=""
for n in Schema Server Tools Client; do
    f="lib/${n}.stk"
    [[ -f "$f" ]] || continue
    grep -qE "^package Mcpd::${n}\b" "$f" \
        || { pkg_bad="$pkg_bad ${n}"; ok=0; }
done
if [[ -z "$pkg_bad" ]]; then
    echo "PASS  every sublib declares 'package Mcpd::<Name>'"
else
    echo "FAIL  sublibs with missing/incorrect package line:$pkg_bad"
fi

# ── stdio discipline: lib/ never prints to stdout ───────────────────
# stdout carries the JSON-RPC stream; a stray p/print/say in lib/
# corrupts every connected client. (print $fh ... to a handle is fine.)
if grep -nE '^\s*(p |print |say )' lib/*.stk | grep -vE 'print \$fh' >/dev/null 2>&1; then
    echo "FAIL  lib/ writes to stdout — that corrupts the JSON-RPC stream:"
    grep -nE '^\s*(p |print |say )' lib/*.stk | grep -vE 'print \$fh' | head -5
    ok=0
else
    echo "PASS  lib/ never writes to stdout (JSON-RPC stream stays clean)"
fi

# ── examples have shebangs ──────────────────────────────────────────
no_shebang=0
while IFS= read -r f; do
    head -1 "$f" | grep -qE '^#!/usr/bin/env stryke' \
        || { echo "FAIL  $f: missing #!/usr/bin/env stryke"; no_shebang=$((no_shebang+1)); ok=0; }
done < <(find examples -maxdepth 1 -name "*.stk" -type f 2>/dev/null)
ex_count=$(find examples -maxdepth 1 -name "*.stk" -type f 2>/dev/null | wc -l | tr -d ' ')
if [[ $no_shebang -eq 0 ]]; then
    echo "PASS  every examples/*.stk has stryke shebang ($ex_count files)"
fi

# ── bin/mcpd.stk present + shebang ──────────────────────────────────
if [[ -f bin/mcpd.stk ]]; then
    if head -1 bin/mcpd.stk | grep -qE '^#!/usr/bin/env stryke'; then
        echo "PASS  bin/mcpd.stk present with stryke shebang"
    else
        echo "FAIL  bin/mcpd.stk missing stryke shebang"
        ok=0
    fi
else
    echo "FAIL  bin/mcpd.stk not present"
    ok=0
fi

# ── t/ contains at least one test file ──────────────────────────────
t_count=$(find t -maxdepth 1 -name "test_*.stk" -type f 2>/dev/null | wc -l | tr -d ' ')
if [[ $t_count -ge 1 ]]; then
    echo "PASS  t/ contains $t_count test_*.stk file(s)"
else
    echo "FAIL  t/ has no test_*.stk files"
    ok=0
fi

# ── stryke.toml: pure-stryke (NO [ffi] table) ───────────────────────
if [[ -f stryke.toml ]]; then
    if grep -qE '^\[ffi\]' stryke.toml; then
        echo "FAIL  stryke.toml has [ffi] — but this package claims pure-stryke"
        ok=0
    else
        echo "PASS  stryke.toml has no [ffi] (pure-stryke contract upheld)"
    fi
    # No Cargo.toml either — pure-stryke means no rust crate.
    if [[ -f Cargo.toml ]]; then
        echo "FAIL  Cargo.toml present — pure-stryke package should ship no rust crate"
        ok=0
    else
        echo "PASS  no Cargo.toml at repo root (pure-stryke contract upheld)"
    fi
else
    echo "FAIL  stryke.toml not present at repo root"
    ok=0
fi

# ── Makefile contract: must have test, install, clean targets ───────
mk_missing=""
for target in test install clean; do
    grep -qE "^${target}:" Makefile 2>/dev/null \
        || mk_missing="$mk_missing $target"
done
if [[ -z "$mk_missing" ]]; then
    echo "PASS  Makefile has test / install / clean targets"
else
    echo "FAIL  Makefile missing targets:$mk_missing"
    ok=0
fi

# ── LICENSE present ─────────────────────────────────────────────────
if [[ -f LICENSE ]]; then
    grep -qE '^MIT License' LICENSE \
        && echo "PASS  LICENSE is MIT" \
        || { echo "FAIL  LICENSE present but not MIT"; ok=0; }
else
    echo "FAIL  LICENSE not present at repo root"
    ok=0
fi

[[ $ok -eq 1 ]] && exit 0 || exit 1
