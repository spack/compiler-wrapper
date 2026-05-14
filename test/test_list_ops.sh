#!/bin/sh
# shellcheck disable=SC2034  # vars are passed by name to functions sourced from cc.sh
# shellcheck disable=SC2154  # lsep/sep are defined by the sourced cc.sh block
#
# Copyright Spack Project Developers. See COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)
#
# Unit tests for the list-manipulation primitives in cc.sh (empty, setsep,
# append, extend, preextend). The block between '# BEGIN list functions' and
# '# END list functions' in cc.sh is extracted and sourced, so we can call
# the functions directly without running the rest of the wrapper.

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPO_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
CC_SH="$REPO_DIR/cc.sh"

if [ ! -f "$CC_SH" ]; then
    echo "Cannot find cc.sh at $CC_SH" >&2
    exit 1
fi

FUNCS_SH=$(mktemp)
trap 'rm -f "$FUNCS_SH"' EXIT INT TERM

awk '/^# BEGIN list functions$/{flag=1; next} /^# END list functions$/{flag=0} flag' \
    "$CC_SH" > "$FUNCS_SH"

# shellcheck disable=SC1090
. "$FUNCS_SH"

# ---------------------------------------------------------------------------
# Test harness
# ---------------------------------------------------------------------------

PASS_COUNT=0
FAIL_COUNT=0
CURRENT_TEST=""
CURRENT_FAILED=0

start_test() {
    CURRENT_TEST="$1"
    CURRENT_FAILED=0
}

end_test() {
    if [ "$CURRENT_FAILED" -eq 0 ]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        printf 'PASS  %s\n' "$CURRENT_TEST"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        printf 'FAIL  %s (%d sub-check(s) failed)\n' "$CURRENT_TEST" "$CURRENT_FAILED"
    fi
}

fail() {
    CURRENT_FAILED=$((CURRENT_FAILED + 1))
    printf '  [%s] %s\n' "$CURRENT_TEST" "$1" >&2
}

# expect_eq LABEL ACTUAL EXPECTED
expect_eq() {
    if [ "$2" != "$3" ]; then
        # Render the bell separator visibly in error output.
        _exp=$(printf '%s' "$3" | tr "$lsep" '|')
        _act=$(printf '%s' "$2" | tr "$lsep" '|')
        fail "$1: expected '$_exp', got '$_act'"
    fi
}

# expect_true LABEL CMD...
expect_true() {
    _label="$1"; shift
    if ! "$@"; then
        fail "$_label: expected success, got failure"
    fi
}

# expect_false LABEL CMD...
expect_false() {
    _label="$1"; shift
    if "$@"; then
        fail "$_label: expected failure, got success"
    fi
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

test_empty() {
    unset tvar || true
    expect_true  empty_unset empty tvar
    tvar=''
    expect_true  empty_empty empty tvar
    tvar='x'
    expect_false empty_nonempty empty tvar
    tvar=' '
    expect_false empty_space empty tvar
    unset tvar
}

test_setsep() {
    setsep foo_dirs;  expect_eq setsep_dirs   "$sep" ':'
    setsep FOO_DIRS;  expect_eq setsep_DIRS   "$sep" ':'
    setsep MYPATH;    expect_eq setsep_PATH   "$sep" ':'
    setsep MYPATHS;   expect_eq setsep_PATHS  "$sep" ':'
    setsep foo_list;  expect_eq setsep_list   "$sep" "$lsep"
    setsep whatever;  expect_eq setsep_other  "$sep" ' '
}

test_append() {
    # _list (lsep separator)
    tgt_list=''
    append tgt_list a
    expect_eq append_list_empty   "$tgt_list" "a"
    append tgt_list b
    expect_eq append_list_two     "$tgt_list" "a${lsep}b"
    append tgt_list c
    expect_eq append_list_three   "$tgt_list" "a${lsep}b${lsep}c"

    # _dirs (colon separator)
    tgt_dirs=''
    append tgt_dirs /a
    append tgt_dirs /b
    expect_eq append_dirs         "$tgt_dirs" "/a:/b"

    # default (space separator)
    tgt_other=''
    append tgt_other x
    append tgt_other y
    expect_eq append_default      "$tgt_other" "x y"
}

test_extend_empty_source() {
    src_list=''
    tgt_list='existing'
    extend tgt_list src_list
    expect_eq extend_empty_src "$tgt_list" 'existing'
}

test_extend_single_into_empty() {
    src_list='a'
    tgt_list=''
    extend tgt_list src_list
    expect_eq extend_single "$tgt_list" 'a'
}

test_extend_multi_into_empty() {
    src_list="a${lsep}b${lsep}c"
    tgt_list=''
    extend tgt_list src_list
    expect_eq extend_multi_empty "$tgt_list" "a${lsep}b${lsep}c"
}

test_extend_multi_into_nonempty() {
    src_list="b${lsep}c"
    tgt_list='a'
    extend tgt_list src_list
    expect_eq extend_multi_nonempty "$tgt_list" "a${lsep}b${lsep}c"
}

test_extend_prefix() {
    src_list="b${lsep}c"
    tgt_list='a'
    extend tgt_list src_list '-I'
    expect_eq extend_prefix "$tgt_list" "a${lsep}-Ib${lsep}-Ic"
}

test_extend_cross_separator() {
    # Source uses ':' (dirs), target uses lsep (list).
    src_dirs='a:b:c'
    tgt_list=''
    extend tgt_list src_dirs
    expect_eq extend_dirs_to_list_empty "$tgt_list" "a${lsep}b${lsep}c"

    tgt_list='x'
    extend tgt_list src_dirs '-L'
    expect_eq extend_dirs_to_list_nonempty "$tgt_list" "x${lsep}-La${lsep}-Lb${lsep}-Lc"
}

test_extend_default_separator() {
    src_other='a b c'
    tgt_other='x'
    extend tgt_other src_other
    expect_eq extend_default_sep "$tgt_other" 'x a b c'
}

test_preextend_empty_source() {
    src_list=''
    tgt_list='existing'
    preextend tgt_list src_list
    expect_eq preextend_empty_src "$tgt_list" 'existing'
}

test_preextend_single_into_empty() {
    src_list='a'
    tgt_list=''
    preextend tgt_list src_list
    expect_eq preextend_single "$tgt_list" 'a'
}

test_preextend_multi_into_empty() {
    # The original reversed-prepend logic existed to preserve source order.
    src_list="a${lsep}b${lsep}c"
    tgt_list=''
    preextend tgt_list src_list
    expect_eq preextend_multi_empty "$tgt_list" "a${lsep}b${lsep}c"
}

test_preextend_multi_into_nonempty() {
    src_list="a${lsep}b"
    tgt_list="c${lsep}d"
    preextend tgt_list src_list
    expect_eq preextend_multi_nonempty "$tgt_list" "a${lsep}b${lsep}c${lsep}d"
}

test_preextend_prefix() {
    src_list="a${lsep}b"
    tgt_list='c'
    preextend tgt_list src_list '-I'
    expect_eq preextend_prefix "$tgt_list" "-Ia${lsep}-Ib${lsep}c"
}

test_preextend_cross_separator() {
    src_dirs='a:b:c'
    tgt_list='x'
    preextend tgt_list src_dirs
    expect_eq preextend_dirs_to_list "$tgt_list" "a${lsep}b${lsep}c${lsep}x"
}

test_lsep_prepend_pattern() {
    # The inline replacement for the old prepend helper, as used at
    # 'full_command_list="${SPACK_CCACHE_BINARY}${lsep}${full_command_list}"'.
    tgt_list=''
    append tgt_list compiler
    append tgt_list -O2
    tgt_list="ccache${lsep}${tgt_list}"

    IFS="$lsep"
    # shellcheck disable=SC2086
    set -- $tgt_list
    unset IFS
    expect_eq prepend_pattern_count "$#" 3
    expect_eq prepend_pattern_first "$1" 'ccache'
    expect_eq prepend_pattern_mid   "$2" 'compiler'
    expect_eq prepend_pattern_last  "$3" '-O2'
}

# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

all_tests='
test_empty
test_setsep
test_append
test_extend_empty_source
test_extend_single_into_empty
test_extend_multi_into_empty
test_extend_multi_into_nonempty
test_extend_prefix
test_extend_cross_separator
test_extend_default_separator
test_preextend_empty_source
test_preextend_single_into_empty
test_preextend_multi_into_empty
test_preextend_multi_into_nonempty
test_preextend_prefix
test_preextend_cross_separator
test_lsep_prepend_pattern
'

if [ $# -gt 0 ]; then
    tests_to_run="$*"
else
    tests_to_run="$all_tests"
fi

for t in $tests_to_run; do
    start_test "$t"
    "$t"
    end_test
done

printf '\n%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
