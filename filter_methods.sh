#!/bin/bash
# Root-level entry point — delegates to scripts/filter_methods.sh
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${REPO_ROOT}/scripts/filter_methods.sh" "$@"
