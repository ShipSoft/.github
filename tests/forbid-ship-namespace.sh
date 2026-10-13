#!/usr/bin/env bash
# SPDX-FileCopyrightText: CERN for the benefit of the SHiP Collaboration
# SPDX-License-Identifier: LGPL-3.0-or-later
#
# Runs the forbid-ship-namespace hook from this checkout against the fixtures:
# every file in bad/ must fail it, every file in good/ must pass.
set -u

repo_root=$(git rev-parse --show-toplevel)
fixtures="$repo_root/tests/forbid-ship-namespace"
status=0

check() {
    local expect=$1 file=$2
    if pre-commit try-repo "$repo_root" forbid-ship-namespace --files "$file" >/dev/null 2>&1; then
        got=pass
    else
        got=fail
    fi
    if [ "$got" = "$expect" ]; then
        echo "ok   ${file#"$repo_root"/} ($got)"
    else
        echo "FAIL ${file#"$repo_root"/} (expected $expect, got $got)"
        status=1
    fi
}

for f in "$fixtures"/bad/*; do check fail "$f"; done
for f in "$fixtures"/good/*; do check pass "$f"; done
exit $status
