#!/usr/bin/env bash
# Bidirectional sync. Filled in by ACB-5.
acb_cmd_status()  { acb_config_validate || return 1; }
acb_cmd_pull()    { echo "✗ 'acb pull' is not implemented until ACB-5." >&2; return 1; }
acb_cmd_propose() { echo "✗ 'acb propose' is not implemented until ACB-5." >&2; return 1; }
