#!/usr/bin/env bash
#
# oss.sh - Tool for managing multiple OSS projects.
#
# Copyright (C) 2026 Предраг Јовановић
# SPDX-FileCopyrightText: 2026 Предраг Јовановић
# SPDX-License-Identifier: GPL-3.0-or-later

set -uo pipefail

# ----------------------------------------------------------------------------
# Globals & config
# ----------------------------------------------------------------------------

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

OSS_WORKSPACE_OPT=""      # set via -w/--workspace
COLOR_MODE="auto"         # auto | always | never
VERBOSE=0

WRAP_PROVIDE_OPT=""       # set via -p/--provide (wrap gen)

# ----------------------------------------------------------------------------
# Logging / color module
# ----------------------------------------------------------------------------

_color_enabled() {
    case "$COLOR_MODE" in
        always) return 0 ;;
        never)  return 1 ;;
        auto)
            [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]
            return $?
            ;;
    esac
}

_setup_colors() {
    if _color_enabled; then
        C_RESET=$'\033[0m'
        C_RED=$'\033[31m'
        C_GREEN=$'\033[32m'
        C_YELLOW=$'\033[33m'
        C_BLUE=$'\033[34m'
        C_MAGENTA=$'\033[35m'
        C_CYAN=$'\033[36m'
        C_BOLD=$'\033[1m'
        C_DIM=$'\033[2m'
    else
        C_RESET="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_MAGENTA="" C_CYAN="" C_BOLD="" C_DIM=""
    fi
}

log_info()    { printf '%s[info]%s  %s\n'  "$C_BLUE"    "$C_RESET" "$*" >&2; }
log_success() { printf '%s[ ok ]%s  %s\n'  "$C_GREEN"   "$C_RESET" "$*" >&2; }
log_warn()    { printf '%s[warn]%s  %s\n'  "$C_YELLOW"  "$C_RESET" "$*" >&2; }
log_error()   { printf '%s[fail]%s  %s\n'  "$C_RED"     "$C_RESET" "$*" >&2; }
log_debug()   { [[ "$VERBOSE" -eq 1 ]] && printf '%s[dbg ]%s  %s\n' "$C_DIM" "$C_RESET" "$*" >&2; return 0; }

heading() { printf '%s%s%s\n' "$C_BOLD$C_CYAN" "$*" "$C_RESET"; }
project_label() { printf '%s%s%s' "$C_MAGENTA$C_BOLD" "$*" "$C_RESET"; }

die() {
    log_error "$*"
    exit 1
}

# ----------------------------------------------------------------------------
# Generic utilities
# ----------------------------------------------------------------------------

require_cmds() {
    local missing=()
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || missing+=("$c")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        die "missing required command(s): ${missing[*]}"
    fi
}

trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# ----------------------------------------------------------------------------
# Workspace helpers
# ----------------------------------------------------------------------------


# NOTE: used as `ws="$(resolve_workspace)" || exit 1` at call sites.
# It must NOT call die() itself: die() calls exit, and exit inside a
# command-substitution subshell only terminates the subshell, not the
# calling script -- execution would continue with an empty workspace.
# So errors are printed here and a non-zero status is returned instead,
# and every caller checks that status explicitly.
resolve_workspace() {
    local ws="${OSS_WORKSPACE_OPT:-${OSS_WORKSPACE:-}}"
    if [[ -z "$ws" ]]; then
        log_error "workspace not set. Use -w/--workspace <dir> or export OSS_WORKSPACE."
        return 1
    fi
    if [[ ! -d "$ws" ]]; then
        log_error "workspace directory does not exist: $ws"
        return 1
    fi
    (cd "$ws" && pwd)
}

wraps_dir() {
    local ws="$1"
    printf '%s/.wraps' "$ws"
}

# Is the given directory (default: cwd) the workspace root?
in_workspace_root() {
    local ws="$1"
    local cwd
    cwd="$(pwd)"
    [[ "$cwd" == "$ws" ]]
}

# List project directories directly under the workspace (git repos, .wraps excluded)
list_projects() {
    local ws="$1"
    local d name
    for d in "$ws"/*/; do
        [[ -d "$d" ]] || continue
        name="$(basename "$d")"
        [[ "$name" == ".wraps" ]] && continue
        [[ -d "$d/.git" ]] || continue
        printf '%s\n' "${d%/}"
    done
}

# ----------------------------------------------------------------------------
# Git helpers (all operate on an explicit repo path so callers can loop)
# ----------------------------------------------------------------------------

git_root_from_cwd() {
    git rev-parse --show-toplevel 2>/dev/null
}

git_current_branch() {
    local repo="$1"
    git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null
}

# Number of commits on HEAD not yet on its upstream ("commits since last push")
git_commits_ahead() {
    local repo="$1"
    local upstream
    upstream="$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" || {
        printf 'no-upstream'
        return
    }
    git -C "$repo" rev-list --count '@{u}..HEAD' 2>/dev/null
}

git_latest_tag() {
    local repo="$1"
    git -C "$repo" describe --tags --abbrev=0 2>/dev/null
}

git_commits_since_tag() {
    local repo="$1" tag="$2"
    git -C "$repo" rev-list --count "${tag}..HEAD" 2>/dev/null
}

git_tag_age() {
    local repo="$1" tag="$2"
    git -C "$repo" log -1 --format=%ar "$tag" -- 2>/dev/null
}

# ----------------------------------------------------------------------------
# Version / semver helpers ('v1', 'v1.0', 'v1.0.0')
# ----------------------------------------------------------------------------

is_semver() {
    [[ "$1" =~ ^v[0-9]+(\.[0-9]+){0,2}$ ]]
}

strip_v_prefix() {
    local v="$1"
    printf '%s' "${v#v}"
}
