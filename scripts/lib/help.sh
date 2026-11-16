#!/bin/bash
# Shared --help support: prints the "#:" lines of the calling script.
# Usage in a script:  source "$(dirname "$0")/lib/help.sh"; maybe_show_help "${1:-}"

show_help() { sed -n 's/^#: \{0,1\}//p' "$0"; }

# Prints help and exits if the first arg is -h/--help; otherwise does nothing.
maybe_show_help() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then show_help; exit 0; fi
}
