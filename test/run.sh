#!/bin/sh
# shellcheck disable=SC2034  # vars are passed by name to functions sourced from cc.sh
# shellcheck disable=SC2154  # lsep/sep are defined by the sourced cc.sh block
#
# Copyright Spack Project Developers. See COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)
#
# Exercises ../cc.sh via SPACK_TEST_COMMAND=dump-args/dump-mode/dump-env-<VAR>.
# Also unit-tests the list-manipulation primitives extracted from cc.sh.
#
# Run all tests:        sh test/run.sh
# Run a single test:    sh test/run.sh test_modes

set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPO_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
CC_SH="$REPO_DIR/cc.sh"

if [ ! -f "$CC_SH" ]; then
    echo "Cannot find cc.sh at $CC_SH" >&2
    exit 1
fi

WRAPPER_DIR=$(mktemp -d)

for name in cc c++ cpp fc ld; do
    ln -s "$CC_SH" "$WRAPPER_DIR/$name"
done

# Extract list-manipulation functions from cc.sh for unit testing.
FUNCS_SH=$(mktemp)
trap 'rm -rf "$WRAPPER_DIR" "$FUNCS_SH"' EXIT INT TERM

awk '/^# BEGIN list functions$/{flag=1; next} /^# END list functions$/{flag=0} flag' \
    "$CC_SH" > "$FUNCS_SH"

# shellcheck disable=SC1090
. "$FUNCS_SH"

REAL_CC=/bin/mycc

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

# Concatenate newline-separated lists, skipping empty arguments. Result on stdout,
# no trailing newline.
concat() {
    _first=1
    for _piece; do
        [ -z "$_piece" ] && continue
        if [ "$_first" -eq 1 ]; then
            printf '%s' "$_piece"
            _first=0
        else
            printf '\n%s' "$_piece"
        fi
    done
}

# Read newline-separated args from stdin into "$@" then run cc.sh at $1.
# Caller is expected to export SPACK_TEST_COMMAND already.
_run_wrapper_stdin() {
    _wrapper="$WRAPPER_DIR/$1"
    set --
    while IFS= read -r _ln || [ -n "$_ln" ]; do
        set -- "$@" "$_ln"
    done
    "$_wrapper" "$@"
}

# dump_args WRAPPER ARGS_STRING  -> prints wrapper's dump-args output
dump_args() {
    SPACK_TEST_COMMAND=dump-args
    export SPACK_TEST_COMMAND
    printf '%s' "$2" | _run_wrapper_stdin "$1"
}

# expect_args LABEL WRAPPER ARGS_STRING EXPECTED_STRING
expect_args() {
    _label="$1"; _wrapper="$2"; _args="$3"; _expected="$4"
    _actual=$(dump_args "$_wrapper" "$_args")
    if [ "$_actual" != "$_expected" ]; then
        _ef=$(mktemp); _af=$(mktemp)
        printf '%s\n' "$_expected" > "$_ef"
        printf '%s\n' "$_actual"   > "$_af"
        _diff=$(diff -u "$_ef" "$_af" || true)
        rm -f "$_ef" "$_af"
        fail "$_label: argv mismatch
$_diff"
    fi
}

# expect_mode LABEL WRAPPER ARGS_STRING EXPECTED_MODE
expect_mode() {
    _label="$1"; _wrapper="$2"; _args="$3"; _expected="$4"
    SPACK_TEST_COMMAND=dump-mode
    export SPACK_TEST_COMMAND
    _actual=$(printf '%s' "$_args" | _run_wrapper_stdin "$_wrapper")
    if [ "$_actual" != "$_expected" ]; then
        fail "$_label: mode mismatch (expected '$_expected', got '$_actual')"
    fi
}

# expect_contains LABEL ACTUAL NEEDLE -- line-wise membership
expect_contains() {
    _label="$1"; _actual="$2"; _needle="$3"
    if ! printf '%s\n' "$_actual" | grep -Fxq -- "$_needle"; then
        fail "$_label: expected to contain line '$_needle'"
    fi
}

expect_not_contains() {
    _label="$1"; _actual="$2"; _needle="$3"
    if printf '%s\n' "$_actual" | grep -Fxq -- "$_needle"; then
        fail "$_label: expected NOT to contain line '$_needle'"
    fi
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

# -------------------
# Wrapper environment
# -------------------

# shellcheck disable=SC2089
SPACK_SYSTEM_DIRS_VALUE='"/"|"//"|"/bin"|"/bin/"|"/bin64"|"/bin64/"|"/include"|"/include/"|"/lib"|"/lib/"|"/lib64"|"/lib64/"|"/usr"|"/usr/"|"/usr/bin"|"/usr/bin/"|"/usr/bin64"|"/usr/bin64/"|"/usr/include"|"/usr/include/"|"/usr/lib"|"/usr/lib/"|"/usr/lib64"|"/usr/lib64/"|"/usr/local"|"/usr/local/"|"/usr/local/bin"|"/usr/local/bin/"|"/usr/local/bin64"|"/usr/local/bin64/"|"/usr/local/include"|"/usr/local/include/"|"/usr/local/lib"|"/usr/local/lib/"|"/usr/local/lib64"|"/usr/local/lib64/"'

# Variables we set per-test that need to be cleared between tests.
EXTRA_VARS='
SPACK_CPPFLAGS SPACK_CFLAGS SPACK_CXXFLAGS SPACK_FFLAGS SPACK_LDFLAGS SPACK_LDLIBS
SPACK_ALWAYS_CPPFLAGS SPACK_ALWAYS_CFLAGS SPACK_ALWAYS_CXXFLAGS SPACK_ALWAYS_FFLAGS
SPACK_INCLUDE_DIRS SPACK_LINK_DIRS SPACK_RPATH_DIRS
SPACK_STORE_INCLUDE_DIRS SPACK_STORE_LINK_DIRS SPACK_STORE_RPATH_DIRS
SPACK_COMPILER_EXTRA_RPATHS SPACK_COMPILER_IMPLICIT_RPATHS
SPACK_CC_HAS_FRANDOM_SEED SPACK_CXX_HAS_FRANDOM_SEED
SPACK_FC_HAS_FRANDOM_SEED SPACK_F77_HAS_FRANDOM_SEED
SPACK_CCACHE_BINARY SPACK_TEST_COMMAND SPACK_ADD_DEBUG_FLAGS SPACK_DEBUG_FLAGS
SPACK_DEBUG
'

wrapper_environment() {
    SPACK_CC=$REAL_CC
    SPACK_CXX=$REAL_CC
    SPACK_FC=$REAL_CC
    SPACK_F77=$REAL_CC
    SPACK_PREFIX=/spack-test-prefix
    # shellcheck disable=SC2209  # literal string "test", not the command
    SPACK_COMPILER_WRAPPER_PATH=test
    SPACK_DEBUG_LOG_DIR=.
    SPACK_DEBUG_LOG_ID=foo-hashabc
    SPACK_SHORT_SPEC='foo@1.2 arch=linux-rhel6-x86_64 /hashabc'
    SPACK_SYSTEM_DIRS=$SPACK_SYSTEM_DIRS_VALUE
    SPACK_MANAGED_DIRS='/path/to/spack-1/opt/spack/*|/path/to/spack-2/opt/spack/*'
    SPACK_CC_RPATH_ARG='-Wl,-rpath,'
    SPACK_CXX_RPATH_ARG='-Wl,-rpath,'
    SPACK_F77_RPATH_ARG='-Wl,-rpath,'
    SPACK_FC_RPATH_ARG='-Wl,-rpath,'
    SPACK_TARGET_ARGS_CC='-march=znver2 -mtune=znver2'
    SPACK_TARGET_ARGS_CXX='-march=znver2 -mtune=znver2'
    SPACK_TARGET_ARGS_FORTRAN='-march=znver4 -mtune=znver4'
    SPACK_CC_LINKER_ARG='-Wl,'
    SPACK_CXX_LINKER_ARG='-Wl,'
    SPACK_FC_LINKER_ARG='-Wl,'
    SPACK_F77_LINKER_ARG='-Wl,'
    SPACK_DTAGS_TO_ADD='--disable-new-dtags'
    SPACK_DTAGS_TO_STRIP='--enable-new-dtags'
    SPACK_COMPILER_FLAGS_KEEP=''
    SPACK_COMPILER_FLAGS_REPLACE='-Werror*|'

    # shellcheck disable=SC2090
    export SPACK_CC SPACK_CXX SPACK_FC SPACK_F77 SPACK_PREFIX \
        SPACK_COMPILER_WRAPPER_PATH SPACK_DEBUG_LOG_DIR SPACK_DEBUG_LOG_ID \
        SPACK_SHORT_SPEC SPACK_SYSTEM_DIRS SPACK_MANAGED_DIRS \
        SPACK_CC_RPATH_ARG SPACK_CXX_RPATH_ARG SPACK_F77_RPATH_ARG SPACK_FC_RPATH_ARG \
        SPACK_TARGET_ARGS_CC SPACK_TARGET_ARGS_CXX SPACK_TARGET_ARGS_FORTRAN \
        SPACK_CC_LINKER_ARG SPACK_CXX_LINKER_ARG SPACK_FC_LINKER_ARG SPACK_F77_LINKER_ARG \
        SPACK_DTAGS_TO_ADD SPACK_DTAGS_TO_STRIP \
        SPACK_COMPILER_FLAGS_KEEP SPACK_COMPILER_FLAGS_REPLACE

    # Empty out optional vars (so they exist but don't influence the build).
    SPACK_LINK_DIRS=''
    SPACK_INCLUDE_DIRS=''
    SPACK_RPATH_DIRS=''
    export SPACK_LINK_DIRS SPACK_INCLUDE_DIRS SPACK_RPATH_DIRS

    for _v in $EXTRA_VARS; do
        unset "$_v"
    done
}

wrapper_flags() {
    SPACK_CPPFLAGS='-g -O1 -DVAR=VALUE'
    SPACK_CFLAGS='-Wall'
    SPACK_CXXFLAGS='-Werror'
    SPACK_FFLAGS='-w'
    SPACK_LDFLAGS='-Wl,--gc-sections -L foo'
    SPACK_LDLIBS='-lfoo'
    export SPACK_CPPFLAGS SPACK_CFLAGS SPACK_CXXFLAGS SPACK_FFLAGS SPACK_LDFLAGS SPACK_LDLIBS
}

# ----------------
# Shared test data
# ----------------

# Use quoted-heredoc so nothing inside is expanded.
TEST_ARGS=$(cat <<'EOF'
-I/test/include
-L/test/lib
-L/with space/lib
-I/other/include
arg1
-Wl,--start-group
arg2
-Wl,-rpath,/first/rpath
arg3
-Wl,-rpath
-Wl,/second/rpath
-llib1
-llib2
arg4
-Wl,--end-group
-Xlinker
-rpath
-Xlinker
/third/rpath
-Xlinker
-rpath
-Xlinker
/fourth/rpath
-Wl,--rpath,/fifth/rpath
-Wl,--rpath
-Wl,/sixth/rpath
-llib3
-llib4
arg5
arg6
-DGCC_ARG_WITH_PERENS=(A B C)
"-DDOUBLE_QUOTED_ARG"
'-DSINGLE_QUOTED_ARG'
EOF
)

TEST_INCLUDE_PATHS=$(cat <<'EOF'
-I/test/include
-I/other/include
EOF
)

TEST_LIBRARY_PATHS=$(cat <<'EOF'
-L/test/lib
-L/with space/lib
EOF
)

TEST_WL_RPATHS=$(cat <<'EOF'
-Wl,-rpath,/first/rpath
-Wl,-rpath,/second/rpath
-Wl,-rpath,/third/rpath
-Wl,-rpath,/fourth/rpath
-Wl,-rpath,/fifth/rpath
-Wl,-rpath,/sixth/rpath
EOF
)

TEST_RPATHS=$(cat <<'EOF'
-rpath
/first/rpath
-rpath
/second/rpath
-rpath
/third/rpath
-rpath
/fourth/rpath
-rpath
/fifth/rpath
-rpath
/sixth/rpath
EOF
)

TEST_ARGS_NO_PATHS=$(cat <<'EOF'
arg1
-Wl,--start-group
arg2
arg3
-llib1
-llib2
arg4
-Wl,--end-group
-llib3
-llib4
arg5
arg6
-DGCC_ARG_WITH_PERENS=(A B C)
"-DDOUBLE_QUOTED_ARG"
'-DSINGLE_QUOTED_ARG'
EOF
)

TARGET_ARGS=$(cat <<'EOF'
-march=znver2
-mtune=znver2
EOF
)

TARGET_ARGS_FC=$(cat <<'EOF'
-march=znver4
-mtune=znver4
EOF
)

SPACK_CPPFLAGS_LINES=$(cat <<'EOF'
-g
-O1
-DVAR=VALUE
EOF
)

SPACK_CFLAGS_LINES='-Wall'
SPACK_FFLAGS_LINES='-w'
SPACK_LDLIBS_LINES='-lfoo'

LHEADERPAD='-Wl,-headerpad_max_install_names'
HEADERPAD='-headerpad_max_install_names'
DISABLE_NEW_DTAGS_WL='-Wl,--disable-new-dtags'
DISABLE_NEW_DTAGS='--disable-new-dtags'

COMMON_COMPILE_ARGS=$(concat \
    "$TEST_INCLUDE_PATHS" \
    "$TEST_LIBRARY_PATHS" \
    "$DISABLE_NEW_DTAGS_WL" \
    "$TEST_WL_RPATHS" \
    "$TEST_ARGS_NO_PATHS")

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

test_no_wrapper_environment() {
    # Clear every SPACK_* var, then call cc and expect an error.
    _out=$(env -i PATH="/usr/bin:/bin" "$WRAPPER_DIR/cc" 2>&1)
    _rc=$?
    if [ "$_rc" -eq 0 ]; then
        fail "cc with no env unexpectedly exited 0"
    fi
    case "$_out" in
        *"Spack compiler must be run from Spack"*) ;;
        *) fail "expected 'Spack compiler must be run from Spack' in: $_out" ;;
    esac
}

test_separator_in_args() {
    wrapper_environment
    _out=$("$WRAPPER_DIR/cc" "hello$(printf '\a')world" 2>&1)
    _rc=$?
    if [ "$_rc" -eq 0 ]; then
        fail "cc with bell char in args unexpectedly exited 0"
    fi
    case "$_out" in
        *"Compiler command line contains our separator"*) ;;
        *) fail "expected 'Compiler command line contains our separator' in: $_out" ;;
    esac
}

test_modes() {
    wrapper_environment

    expect_mode vcheck1     cc  '-I/include
--version'                          vcheck
    expect_mode vcheck2     cc  '-I/include
-V'                                  vcheck
    expect_mode vcheck3     cc  '-I/include
-v'                                  vcheck
    expect_mode vcheck4     cc  '-I/include
-dumpversion'                        vcheck
    expect_mode vcheck5     cc  '-I/include
--version
-c'                                  vcheck
    expect_mode vcheck6     cc  '-I/include
-V
-o
output'                              vcheck

    expect_mode cpp_cc      cc  '-E'                                          cpp
    expect_mode cpp_cxx     c++ '-E'                                          cpp
    expect_mode cpp_cpp     cpp ''                                            cpp

    expect_mode as_cc       cc  '-S'                                          as

    expect_mode ccld_empty  cc  ''                                            ccld
    expect_mode ccld_simple cc  'foo.c
-o
foo'                                 ccld
    expect_mode ccld_rpath  cc  'foo.c
-o
foo
-Wl,-rpath,foo'                      ccld
    expect_mode ccld_objs   cc  'foo.o
bar.o
baz.o
-o
foo
-Wl,-rpath,foo'                      ccld

    expect_mode ld_empty    ld  ''                                            ld
    expect_mode ld_objs     ld  'foo.o
bar.o
baz.o
-o
foo
-Wl,-rpath,foo'                      ld
}

test_expected_args() {
    wrapper_environment

    # ld_unterminated_rpath
    _args=$(cat <<'EOF'
foo.o
bar.o
baz.o
-o
foo
-rpath
EOF
)
    _exp=$(cat <<'EOF'
ld
--disable-new-dtags
foo.o
bar.o
baz.o
-o
foo
-rpath
EOF
)
    expect_args ld_unterminated_rpath ld "$_args" "$_exp"

    # xlinker_unterminated_rpath
    _args=$(cat <<'EOF'
foo.o
bar.o
baz.o
-o
foo
-Xlinker
-rpath
EOF
)
    _exp=$(concat "$REAL_CC" "$TARGET_ARGS" "$DISABLE_NEW_DTAGS_WL" "$(cat <<'EOF'
foo.o
bar.o
baz.o
-o
foo
-Xlinker
-rpath
EOF
)")
    expect_args xlinker_unterminated_rpath cc "$_args" "$_exp"

    # wl_unterminated_rpath
    _args=$(cat <<'EOF'
foo.o
bar.o
baz.o
-o
foo
-Wl,-rpath
EOF
)
    _exp=$(concat "$REAL_CC" "$TARGET_ARGS" "$DISABLE_NEW_DTAGS_WL" "$(cat <<'EOF'
foo.o
bar.o
baz.o
-o
foo
-Wl,-rpath
EOF
)")
    expect_args wl_unterminated_rpath cc "$_args" "$_exp"

    # Wl_parsing
    _args=$(cat <<'EOF'
-Wl,-rpath,/a,--enable-new-dtags,-rpath=/b,--rpath
-Wl,/c
EOF
)
    _exp=$(concat "$REAL_CC" "$TARGET_ARGS" "$DISABLE_NEW_DTAGS_WL" "$(cat <<'EOF'
-Wl,-rpath,/a
-Wl,-rpath,/b
-Wl,-rpath,/c
EOF
)")
    expect_args Wl_parsing cc "$_args" "$_exp"

    # Wl_parsing_with_missing_value
    _args=$(cat <<'EOF'
-Wl,-rpath=/a,-rpath=
-Wl,--rpath=
EOF
)
    _exp=$(concat "$REAL_CC" "$TARGET_ARGS" "$DISABLE_NEW_DTAGS_WL" "-Wl,-rpath,/a")
    expect_args Wl_parsing_missing cc "$_args" "$_exp"

    # Wl_parsing_NAG_is_ignored
    _args='-Wl,-Wl,,x,,y,,z'
    _exp=$(concat "$REAL_CC" "$TARGET_ARGS_FC" "$DISABLE_NEW_DTAGS_WL" "-Wl,-Wl,,x,,y,,z")
    expect_args Wl_parsing_NAG fc "$_args" "$_exp"

    # Xlinker_parsing
    _args=$(cat <<'EOF'
-Xlinker
-rpath
-O3
-Xlinker
/a
-Xlinker
--flag
-Xlinker
-rpath=/b
-Xlinker
EOF
)
    _exp=$(concat "$REAL_CC" "$TARGET_ARGS" "$DISABLE_NEW_DTAGS_WL" "$(cat <<'EOF'
-Wl,-rpath,/a
-Wl,-rpath,/b
-O3
-Xlinker
--flag
-Xlinker
EOF
)")
    expect_args Xlinker_parsing cc "$_args" "$_exp"

    # rpath_without_value (cc -Wl,-rpath)
    _args=$(cat <<'EOF'
-Wl,-rpath
-O3
-g
EOF
)
    _exp=$(concat "$REAL_CC" "$TARGET_ARGS" "$DISABLE_NEW_DTAGS_WL" "$(cat <<'EOF'
-O3
-g
-Wl,-rpath
EOF
)")
    expect_args rpath_without_value_wl cc "$_args" "$_exp"

    # rpath_without_value (cc -Xlinker -rpath)
    _args=$(cat <<'EOF'
-Xlinker
-rpath
-O3
-g
EOF
)
    _exp=$(concat "$REAL_CC" "$TARGET_ARGS" "$DISABLE_NEW_DTAGS_WL" "$(cat <<'EOF'
-O3
-g
-Xlinker
-rpath
EOF
)")
    expect_args rpath_without_value_xlinker cc "$_args" "$_exp"

    # dep_rpath
    _exp=$(concat "$REAL_CC" "$TARGET_ARGS" "$COMMON_COMPILE_ARGS")
    expect_args dep_rpath cc "$TEST_ARGS" "$_exp"

    # dep_include
    SPACK_INCLUDE_DIRS=x; export SPACK_INCLUDE_DIRS
    _exp=$(concat "$REAL_CC" "$TARGET_ARGS" "$TEST_INCLUDE_PATHS" "-Ix" \
        "$TEST_LIBRARY_PATHS" "$DISABLE_NEW_DTAGS_WL" "$TEST_WL_RPATHS" "$TEST_ARGS_NO_PATHS")
    expect_args dep_include cc "$TEST_ARGS" "$_exp"
    SPACK_INCLUDE_DIRS=''; export SPACK_INCLUDE_DIRS

    # dep_lib
    SPACK_LINK_DIRS=x; SPACK_RPATH_DIRS=x; export SPACK_LINK_DIRS SPACK_RPATH_DIRS
    _exp=$(concat "$REAL_CC" "$TARGET_ARGS" "$TEST_INCLUDE_PATHS" \
        "$TEST_LIBRARY_PATHS" "-Lx" "$DISABLE_NEW_DTAGS_WL" \
        "$TEST_WL_RPATHS" "-Wl,-rpath,x" "$TEST_ARGS_NO_PATHS")
    expect_args dep_lib cc "$TEST_ARGS" "$_exp"
    SPACK_LINK_DIRS=''; SPACK_RPATH_DIRS=''; export SPACK_LINK_DIRS SPACK_RPATH_DIRS

    # dep_lib_no_rpath
    SPACK_LINK_DIRS=x; export SPACK_LINK_DIRS
    _exp=$(concat "$REAL_CC" "$TARGET_ARGS" "$TEST_INCLUDE_PATHS" \
        "$TEST_LIBRARY_PATHS" "-Lx" "$DISABLE_NEW_DTAGS_WL" \
        "$TEST_WL_RPATHS" "$TEST_ARGS_NO_PATHS")
    expect_args dep_lib_no_rpath cc "$TEST_ARGS" "$_exp"
    SPACK_LINK_DIRS=''; export SPACK_LINK_DIRS

    # dep_lib_no_lib
    SPACK_RPATH_DIRS=x; export SPACK_RPATH_DIRS
    _exp=$(concat "$REAL_CC" "$TARGET_ARGS" "$TEST_INCLUDE_PATHS" \
        "$TEST_LIBRARY_PATHS" "$DISABLE_NEW_DTAGS_WL" \
        "$TEST_WL_RPATHS" "-Wl,-rpath,x" "$TEST_ARGS_NO_PATHS")
    expect_args dep_lib_no_lib cc "$TEST_ARGS" "$_exp"
    SPACK_RPATH_DIRS=''; export SPACK_RPATH_DIRS

    # ccld_deps
    SPACK_INCLUDE_DIRS=xinc:yinc:zinc
    SPACK_RPATH_DIRS=xlib:ylib:zlib
    SPACK_LINK_DIRS=xlib:ylib:zlib
    export SPACK_INCLUDE_DIRS SPACK_RPATH_DIRS SPACK_LINK_DIRS

    _exp=$(concat "$REAL_CC" "$TARGET_ARGS" "$TEST_INCLUDE_PATHS" \
        "$(printf -- '-Ixinc\n-Iyinc\n-Izinc')" \
        "$TEST_LIBRARY_PATHS" \
        "$(printf -- '-Lxlib\n-Lylib\n-Lzlib')" \
        "$DISABLE_NEW_DTAGS_WL" "$TEST_WL_RPATHS" \
        "$(printf -- '-Wl,-rpath,xlib\n-Wl,-rpath,ylib\n-Wl,-rpath,zlib')" \
        "$TEST_ARGS_NO_PATHS")
    expect_args ccld_deps cc "$TEST_ARGS" "$_exp"

    # ccld_deps_isystem
    _args="$TEST_ARGS
-isystem
fooinc"
    _exp=$(concat "$REAL_CC" "$TARGET_ARGS" "$TEST_INCLUDE_PATHS" \
        "$(printf -- '-isystem\nfooinc\n-isystem\nxinc\n-isystem\nyinc\n-isystem\nzinc')" \
        "$TEST_LIBRARY_PATHS" \
        "$(printf -- '-Lxlib\n-Lylib\n-Lzlib')" \
        "$DISABLE_NEW_DTAGS_WL" "$TEST_WL_RPATHS" \
        "$(printf -- '-Wl,-rpath,xlib\n-Wl,-rpath,ylib\n-Wl,-rpath,zlib')" \
        "$TEST_ARGS_NO_PATHS")
    expect_args ccld_deps_isystem cc "$_args" "$_exp"

    # cc_deps (-c => mode=cc, no -L/rpath from deps)
    _args="-c
$TEST_ARGS"
    _exp=$(concat "$REAL_CC" "$TARGET_ARGS" "$TEST_INCLUDE_PATHS" \
        "$(printf -- '-Ixinc\n-Iyinc\n-Izinc')" \
        "$TEST_LIBRARY_PATHS" "-c" "$TEST_ARGS_NO_PATHS")
    expect_args cc_deps cc "$_args" "$_exp"

    # ccld_with_system_dirs
    _sys=$(cat <<'EOF'
-I/usr/include
-L/usr/local/lib
-Wl,-rpath,/usr/lib64
-I/usr/local/include
-L/lib64/
EOF
)
    _args="$_sys
$TEST_ARGS"
    _exp=$(concat "$REAL_CC" "$TARGET_ARGS" "$TEST_INCLUDE_PATHS" \
        "$(printf -- '-Ixinc\n-Iyinc\n-Izinc')" \
        "$(printf -- '-I/usr/include\n-I/usr/local/include')" \
        "$TEST_LIBRARY_PATHS" \
        "$(printf -- '-Lxlib\n-Lylib\n-Lzlib')" \
        "$(printf -- '-L/usr/local/lib\n-L/lib64/')" \
        "$DISABLE_NEW_DTAGS_WL" "$TEST_WL_RPATHS" \
        "$(printf -- '-Wl,-rpath,xlib\n-Wl,-rpath,ylib\n-Wl,-rpath,zlib')" \
        "-Wl,-rpath,/usr/lib64" \
        "$TEST_ARGS_NO_PATHS")
    expect_args ccld_with_system_dirs cc "$_args" "$_exp"

    # ccld_with_system_dirs_isystem
    _sys=$(cat <<'EOF'
-isystem
/usr/include
-L/usr/local/lib
-Wl,-rpath,/usr/lib64
-isystem
/usr/local/include
-L/lib64/
EOF
)
    _args="$_sys
$TEST_ARGS"
    _exp=$(concat "$REAL_CC" "$TARGET_ARGS" "$TEST_INCLUDE_PATHS" \
        "$(printf -- '-isystem\nxinc\n-isystem\nyinc\n-isystem\nzinc')" \
        "$(printf -- '-isystem\n/usr/include\n-isystem\n/usr/local/include')" \
        "$TEST_LIBRARY_PATHS" \
        "$(printf -- '-Lxlib\n-Lylib\n-Lzlib')" \
        "$(printf -- '-L/usr/local/lib\n-L/lib64/')" \
        "$DISABLE_NEW_DTAGS_WL" "$TEST_WL_RPATHS" \
        "$(printf -- '-Wl,-rpath,xlib\n-Wl,-rpath,ylib\n-Wl,-rpath,zlib')" \
        "-Wl,-rpath,/usr/lib64" \
        "$TEST_ARGS_NO_PATHS")
    expect_args ccld_with_system_dirs_isystem cc "$_args" "$_exp"

    # ld_deps
    _exp=$(concat "ld" "$TEST_INCLUDE_PATHS" "$TEST_LIBRARY_PATHS" \
        "$(printf -- '-Lxlib\n-Lylib\n-Lzlib')" \
        "$DISABLE_NEW_DTAGS" "$TEST_RPATHS" \
        "$(printf -- '-rpath\nxlib\n-rpath\nylib\n-rpath\nzlib')" \
        "$TEST_ARGS_NO_PATHS")
    expect_args ld_deps ld "$TEST_ARGS" "$_exp"

    # ld_deps_no_rpath
    unset SPACK_RPATH_DIRS
    SPACK_RPATH_DIRS=''; export SPACK_RPATH_DIRS
    _exp=$(concat "ld" "$TEST_INCLUDE_PATHS" "$TEST_LIBRARY_PATHS" \
        "$(printf -- '-Lxlib\n-Lylib\n-Lzlib')" \
        "$DISABLE_NEW_DTAGS" "$TEST_RPATHS" \
        "$TEST_ARGS_NO_PATHS")
    expect_args ld_deps_no_rpath ld "$TEST_ARGS" "$_exp"

    # ld_deps_no_link
    SPACK_RPATH_DIRS=xlib:ylib:zlib; export SPACK_RPATH_DIRS
    SPACK_LINK_DIRS=''; export SPACK_LINK_DIRS
    _exp=$(concat "ld" "$TEST_INCLUDE_PATHS" "$TEST_LIBRARY_PATHS" \
        "$DISABLE_NEW_DTAGS" "$TEST_RPATHS" \
        "$(printf -- '-rpath\nxlib\n-rpath\nylib\n-rpath\nzlib')" \
        "$TEST_ARGS_NO_PATHS")
    expect_args ld_deps_no_link ld "$TEST_ARGS" "$_exp"
}

test_expected_args_with_flags() {
    wrapper_environment
    wrapper_flags

    # ld_flags
    _exp=$(concat "ld" "$TEST_INCLUDE_PATHS" "$TEST_LIBRARY_PATHS" \
        "$DISABLE_NEW_DTAGS" "$TEST_RPATHS" "$TEST_ARGS_NO_PATHS" "$SPACK_LDLIBS_LINES")
    expect_args ld_flags ld "$TEST_ARGS" "$_exp"

    # cpp_flags
    _exp=$(concat "cpp" "$TEST_INCLUDE_PATHS" "$TEST_LIBRARY_PATHS" \
        "$TEST_ARGS_NO_PATHS" "$SPACK_CPPFLAGS_LINES")
    expect_args cpp_flags cpp "$TEST_ARGS" "$_exp"

    # cc_flags
    _exp=$(concat "$REAL_CC" "$TARGET_ARGS" "$TEST_INCLUDE_PATHS" "-Lfoo" \
        "$TEST_LIBRARY_PATHS" "$DISABLE_NEW_DTAGS_WL" "$TEST_WL_RPATHS" \
        "$TEST_ARGS_NO_PATHS" "$SPACK_CPPFLAGS_LINES" "$SPACK_CFLAGS_LINES" \
        "-Wl,--gc-sections" "$SPACK_LDLIBS_LINES")
    expect_args cc_flags cc "$TEST_ARGS" "$_exp"

    # cxx_flags (note: -Werror is filtered by SPACK_COMPILER_FLAGS_REPLACE)
    _exp=$(concat "$REAL_CC" "$TARGET_ARGS" "$TEST_INCLUDE_PATHS" "-Lfoo" \
        "$TEST_LIBRARY_PATHS" "$DISABLE_NEW_DTAGS_WL" "$TEST_WL_RPATHS" \
        "$TEST_ARGS_NO_PATHS" "$SPACK_CPPFLAGS_LINES" \
        "-Wl,--gc-sections" "$SPACK_LDLIBS_LINES")
    expect_args cxx_flags c++ "$TEST_ARGS" "$_exp"

    # fc_flags
    _exp=$(concat "$REAL_CC" "$TARGET_ARGS_FC" "$TEST_INCLUDE_PATHS" "-Lfoo" \
        "$TEST_LIBRARY_PATHS" "$DISABLE_NEW_DTAGS_WL" "$TEST_WL_RPATHS" \
        "$TEST_ARGS_NO_PATHS" "$SPACK_FFLAGS_LINES" "$SPACK_CPPFLAGS_LINES" \
        "-Wl,--gc-sections" "$SPACK_LDLIBS_LINES")
    expect_args fc_flags fc "$TEST_ARGS" "$_exp"

    # always_cflags
    SPACK_ALWAYS_CFLAGS='-always1 -always2'; export SPACK_ALWAYS_CFLAGS
    _args='-v
--cmd-line-v-opt'
    _exp=$(concat "$REAL_CC" "-always1" "-always2" "-v" "--cmd-line-v-opt")
    expect_args always_cflags cc "$_args" "$_exp"
    unset SPACK_ALWAYS_CFLAGS
}

test_system_path_cleanup() {
    wrapper_environment
    SPACK_COMPILER_WRAPPER_PATH="$WRAPPER_DIR"
    SPACK_CC=true
    export SPACK_COMPILER_WRAPPER_PATH SPACK_CC

    _sys='/bin:/usr/bin:/usr/local/bin'

    # Without trailing slash
    SPACK_TEST_COMMAND=dump-env-PATH
    export SPACK_TEST_COMMAND
    PATH="$WRAPPER_DIR:$_sys" _out=$(printf '%s' "$TEST_ARGS" | _run_wrapper_stdin cc)
    _expected="$WRAPPER_DIR/cc: PATH: $_sys"
    if [ "$_out" != "$_expected" ]; then
        fail "system_path_cleanup (no trailing /): got '$_out' expected '$_expected'"
    fi

    # With trailing slash
    PATH="$WRAPPER_DIR/:$_sys" _out=$(printf '%s' "$TEST_ARGS" | _run_wrapper_stdin cc)
    if [ "$_out" != "$_expected" ]; then
        fail "system_path_cleanup (trailing /): got '$_out' expected '$_expected'"
    fi
    unset SPACK_TEST_COMMAND
}

test_ld_deps_partial() {
    wrapper_environment
    SPACK_INCLUDE_DIRS=xinc
    SPACK_RPATH_DIRS=xlib
    SPACK_LINK_DIRS=xlib
    export SPACK_INCLUDE_DIRS SPACK_RPATH_DIRS SPACK_LINK_DIRS

    SPACK_SHORT_SPEC='foo@1.2=linux-x86_64'; export SPACK_SHORT_SPEC
    _args="-r
$TEST_ARGS"
    _exp=$(concat "ld" "$TEST_INCLUDE_PATHS" "$TEST_LIBRARY_PATHS" "-Lxlib" \
        "$DISABLE_NEW_DTAGS" "$TEST_RPATHS" "-rpath" "xlib" "-r" "$TEST_ARGS_NO_PATHS")
    expect_args ld_deps_partial_linux ld "$_args" "$_exp"

    SPACK_SHORT_SPEC='foo@1.2=darwin-x86_64'; export SPACK_SHORT_SPEC
    _exp=$(concat "ld" "$HEADERPAD" "$TEST_INCLUDE_PATHS" "$TEST_LIBRARY_PATHS" "-Lxlib" \
        "$DISABLE_NEW_DTAGS" "$TEST_RPATHS" "-r" "$TEST_ARGS_NO_PATHS")
    expect_args ld_deps_partial_darwin ld "$_args" "$_exp"
}

test_ccache_prepend_for_cc() {
    wrapper_environment
    SPACK_CCACHE_BINARY=ccache; export SPACK_CCACHE_BINARY

    SPACK_SHORT_SPEC='foo@1.2=linux-x86_64'; export SPACK_SHORT_SPEC
    _exp=$(concat "ccache" "$REAL_CC" "$TARGET_ARGS" "$COMMON_COMPILE_ARGS")
    expect_args ccache_prepend_linux cc "$TEST_ARGS" "$_exp"

    SPACK_SHORT_SPEC='foo@1.2=darwin-x86_64'; export SPACK_SHORT_SPEC
    _exp=$(concat "ccache" "$REAL_CC" "$TARGET_ARGS" "$LHEADERPAD" "$COMMON_COMPILE_ARGS")
    expect_args ccache_prepend_darwin cc "$TEST_ARGS" "$_exp"
}

test_no_ccache_prepend_for_fc() {
    wrapper_environment

    SPACK_SHORT_SPEC='foo@1.2=linux-x86_64'; export SPACK_SHORT_SPEC
    _exp=$(concat "$REAL_CC" "$TARGET_ARGS_FC" "$COMMON_COMPILE_ARGS")
    expect_args no_ccache_fc_linux fc "$TEST_ARGS" "$_exp"

    SPACK_SHORT_SPEC='foo@1.2=darwin-x86_64'; export SPACK_SHORT_SPEC
    _exp=$(concat "$REAL_CC" "$TARGET_ARGS_FC" "$LHEADERPAD" "$COMMON_COMPILE_ARGS")
    expect_args no_ccache_fc_darwin fc "$TEST_ARGS" "$_exp"
}

test_keep_and_replace() {
    wrapper_environment
    _werror_specific='-Werror=meh'
    _werror='-Werror'
    _input="$TEST_ARGS
$_werror_specific
$_werror"

    # 1) KEEP="", REPLACE="-Werror*|" => both werror flags removed; -Wl,--end-group survives
    SPACK_COMPILER_FLAGS_KEEP=''
    SPACK_COMPILER_FLAGS_REPLACE='-Werror*|'
    export SPACK_COMPILER_FLAGS_KEEP SPACK_COMPILER_FLAGS_REPLACE
    _out=$(dump_args cc "$_input")
    expect_contains keep_replace_1_keepend "$_out" '-Wl,--end-group'
    expect_not_contains keep_replace_1_strip_specific "$_out" "$_werror_specific"
    expect_not_contains keep_replace_1_strip_werror   "$_out" "$_werror"

    # 2) KEEP="-Werror=*", REPLACE="-Werror*|" => keep -Werror=meh, strip -Werror
    SPACK_COMPILER_FLAGS_KEEP='-Werror=*'
    SPACK_COMPILER_FLAGS_REPLACE='-Werror*|'
    export SPACK_COMPILER_FLAGS_KEEP SPACK_COMPILER_FLAGS_REPLACE
    _out=$(dump_args cc "$_input")
    expect_contains     keep_replace_2_keep   "$_out" "$_werror_specific"
    expect_not_contains keep_replace_2_strip  "$_out" "$_werror"

    # 3) Additional patterns
    SPACK_COMPILER_FLAGS_KEEP='-Werror=*'
    SPACK_COMPILER_FLAGS_REPLACE='-Werror*| -llib1| -Wl*|'
    export SPACK_COMPILER_FLAGS_KEEP SPACK_COMPILER_FLAGS_REPLACE
    _out=$(dump_args cc "$_input")
    expect_contains     keep_replace_3_keep         "$_out" "$_werror_specific"
    expect_not_contains keep_replace_3_strip_werror "$_out" "$_werror"
    expect_not_contains keep_replace_3_strip_lib1   "$_out" '-llib1'
    expect_not_contains keep_replace_3_strip_rpath  "$_out" '-Wl,--rpath'
}

test_disable_new_dtags() {
    wrapper_environment
    wrapper_flags

    _out=$(dump_args ld "$TEST_ARGS")
    expect_contains disable_new_dtags_ld "$_out" '--disable-new-dtags'

    _out=$(dump_args cc "$TEST_ARGS")
    expect_contains disable_new_dtags_cc "$_out" '-Wl,--disable-new-dtags'
}

test_filter_enable_new_dtags() {
    wrapper_environment
    wrapper_flags

    _args="$TEST_ARGS
--enable-new-dtags"
    _out=$(dump_args ld "$_args")
    expect_not_contains filter_enable_dtags_ld "$_out" '--enable-new-dtags'

    _args="$TEST_ARGS
-Wl,--enable-new-dtags"
    _out=$(dump_args cc "$_args")
    expect_not_contains filter_enable_dtags_cc "$_out" '-Wl,--enable-new-dtags'
}

test_linker_strips_loopopt() {
    wrapper_environment
    wrapper_flags

    _args="$TEST_ARGS
-loopopt=0"
    _out=$(dump_args ld "$_args")
    expect_not_contains loopopt_ld "$_out" '-loopopt=0'

    _out=$(dump_args cc "$_args")
    expect_not_contains loopopt_ccld "$_out" '-loopopt=0'

    # In cc mode (-c forces it), -loopopt=0 *is* kept
    _args="$TEST_ARGS
-loopopt=0
-c
x.c"
    _out=$(dump_args cc "$_args")
    expect_contains loopopt_cc_kept "$_out" '-loopopt=0'
}

test_spack_managed_dirs_are_prioritized() {
    wrapper_environment

    _pkg1='/path/to/spack-1/opt/spack/linux-ubuntu22.04-zen2/gcc-13.2.0/pkg-1.0-abcdef'
    _pkg2='/path/to/spack-1/opt/spack/linux-ubuntu22.04-zen2/gcc-13.2.0/pkg-2.0-abcdef'
    _pkg3='/path/to/spack-2/opt/spack/linux-ubuntu22.04-zen2/gcc-13.2.0/pkg-3.0-abcdef'
    _pkg4='/path/to/spack-2/opt/spack/linux-ubuntu22.04-zen2/gcc-13.2.0/pkg-4.0-abcdef'
    _pkg5='/path/to/spack-2/opt/spack/linux-ubuntu22.04-zen2/gcc-13.2.0/pkg-5.0-abcdef'

    SPACK_CPPFLAGS="-I/usr/local/include -I/external-1/include -I${_pkg1}/include"
    SPACK_LDFLAGS="-L/usr/local/lib -L/external-1/lib -L${_pkg1}/lib -Wl,-rpath,/usr/local/lib -Wl,-rpath,/external-1/lib -Wl,-rpath,${_pkg1}/lib"
    SPACK_STORE_LINK_DIRS="${_pkg4}/lib:${_pkg5}/lib"
    SPACK_STORE_RPATH_DIRS="${_pkg4}/lib:${_pkg5}/lib"
    SPACK_STORE_INCLUDE_DIRS="${_pkg4}/include:${_pkg5}/include"
    SPACK_LINK_DIRS='/external-3/lib:/external-4/lib'
    SPACK_RPATH_DIRS='/external-3/lib:/external-4/lib'
    SPACK_INCLUDE_DIRS='/external-3/include:/external-4/include'
    export SPACK_CPPFLAGS SPACK_LDFLAGS SPACK_STORE_LINK_DIRS SPACK_STORE_RPATH_DIRS \
        SPACK_STORE_INCLUDE_DIRS SPACK_LINK_DIRS SPACK_RPATH_DIRS SPACK_INCLUDE_DIRS

    _args=$(cat <<EOF
-I/usr/include
-L/usr/lib
-Wl,-rpath,/usr/lib
-I/external-2/include
-L/external-2/lib
-Wl,-rpath,/external-2/lib
-I..
-L..
-Wl,-rpath,..
-I${_pkg2}/include
-I${_pkg3}/include
-L${_pkg2}/lib
-L${_pkg3}/lib
-Wl,-rpath,${_pkg2}/lib
-Wl,-rpath,${_pkg3}/lib
hello.c
-o
hello
EOF
)

    _out=$(dump_args cc "$_args")

    _dash_I=$(printf '%s\n' "$_out" | sed -n 's/^-I//p')
    _dash_L=$(printf '%s\n' "$_out" | sed -n 's/^-L//p')
    _dash_rp=$(printf '%s\n' "$_out" | sed -n 's/^-Wl,-rpath,//p')

    _expected_I=$(cat <<EOF
${_pkg1}/include
..
${_pkg2}/include
${_pkg3}/include
${_pkg4}/include
${_pkg5}/include
/external-1/include
/external-2/include
/external-3/include
/external-4/include
/usr/local/include
/usr/include
EOF
)

    _expected_LR=$(cat <<EOF
${_pkg1}/lib
..
${_pkg2}/lib
${_pkg3}/lib
${_pkg4}/lib
${_pkg5}/lib
/external-1/lib
/external-2/lib
/external-3/lib
/external-4/lib
/usr/local/lib
/usr/lib
EOF
)

    if [ "$_dash_I" != "$_expected_I" ]; then
        _ef=$(mktemp); _af=$(mktemp)
        printf '%s\n' "$_expected_I" > "$_ef"
        printf '%s\n' "$_dash_I"     > "$_af"
        _diff=$(diff -u "$_ef" "$_af" || true)
        rm -f "$_ef" "$_af"
        fail "managed_dirs -I order mismatch
$_diff"
    fi
    if [ "$_dash_L" != "$_expected_LR" ]; then
        fail "managed_dirs -L order mismatch
got: $_dash_L
expected: $_expected_LR"
    fi
    if [ "$_dash_rp" != "$_expected_LR" ]; then
        fail "managed_dirs -Wl,-rpath order mismatch
got: $_dash_rp
expected: $_expected_LR"
    fi
}

# ---------------------------------------------------------------------------
# -frandom-seed
# ---------------------------------------------------------------------------

test_frandom_seed_not_added_without_env() {
    wrapper_environment
    _out=$(dump_args cc '-c
hello.c
-O2')
    if printf '%s\n' "$_out" | grep -F -- '-frandom-seed=' >/dev/null; then
        fail "frandom_seed_absent: -frandom-seed should not appear without SPACK_CC_HAS_FRANDOM_SEED"
    fi
}

test_frandom_seed_filters_args() {
    wrapper_environment
    SPACK_CC_HAS_FRANDOM_SEED=1; export SPACK_CC_HAS_FRANDOM_SEED

    # cc mode: -frandom-seed should contain only source files, concatenated.
    # Includes space-separated path flags to verify their values do not leak.
    _out=$(dump_args cc '-c
-O2
-I/some/include
-isystem
/some/sys
-L
/some/lib
hello.c
world.c
foo.o
bar.a
baz.so
quux.dylib')
    expect_contains frandom_seed_value "$_out" '-frandom-seed=hello.cworld.c'

    # User-supplied -frandom-seed suppresses auto-generated one
    _out=$(dump_args cc '-c
-frandom-seed=custom
hello.c')
    if printf '%s\n' "$_out" | grep -cF -- '-frandom-seed=' | grep -qv '^1$'; then
        fail "frandom_seed_user_override: expected exactly one -frandom-seed"
    fi
    expect_contains frandom_seed_user_passthrough "$_out" '-frandom-seed=custom'
}

# ---------------------------------------------------------------------------
# List-ops unit tests (set +u: the sourced list functions use optional $3)
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

# List-ops tests need set +u because the sourced functions use optional $3.
list_ops_tests='
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

is_list_ops_test() {
    case "$list_ops_tests" in
        *"$1"*) return 0 ;;
        *) return 1 ;;
    esac
}

wrapper_tests='
test_no_wrapper_environment
test_separator_in_args
test_modes
test_expected_args
test_expected_args_with_flags
test_system_path_cleanup
test_ld_deps_partial
test_ccache_prepend_for_cc
test_no_ccache_prepend_for_fc
test_keep_and_replace
test_disable_new_dtags
test_filter_enable_new_dtags
test_linker_strips_loopopt
test_spack_managed_dirs_are_prioritized
test_frandom_seed_not_added_without_env
test_frandom_seed_filters_args
'

all_tests="$wrapper_tests $list_ops_tests"

if [ $# -gt 0 ]; then
    tests_to_run="$*"
else
    tests_to_run="$all_tests"
fi

for t in $tests_to_run; do
    start_test "$t"
    if is_list_ops_test "$t"; then
        set +u; "$t"; set -u
    else
        "$t"
    fi
    end_test
done

printf '\n%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
