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