#!/usr/bin/env bash
# ============================================================================
# escalate-demo.sh — the money demo. Apache-2.0 (see LICENSE+NOTICE).
# A FROZEN SMALL model hits its ceiling and hands a hard question UP; a FRONTIER
# tier (a bigger model, or a human) claims it and writes the answer BACK into the
# SAME row; the small model just reads the answer. The asker never held the
# answerer's keys, never knew who would answer. Coordination without coupling.
#
# Usage:  bash escalate-demo.sh [dbname]     (default db: membrane_demo)
# ============================================================================
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
DB="${1:-membrane_demo}"

echo "1) stand up a fresh sovereign membrane from nothing…"
bash "$here/membrane.sh" "$DB" setup

echo
echo "2) a FROZEN SMALL model (small-local) hits its ceiling and hands the question up:"
ID=$(bash "$here/membrane.sh" "$DB" escalate "small-local" "agent-knowledge" \
  "Should we fine-tune the small model or use retrieval + a shared commons? Crisp recommendation.")
echo "   posted escalation #$ID  (status = needs_help)"

echo
echo "3) a FRONTIER seat looks at the pending lane (this is what a watcher sees):"
bash "$here/membrane.sh" "$DB" pending

echo
echo "4) the FRONTIER seat claims it and writes the answer BACK into the row:"
bash "$here/membrane.sh" "$DB" answer "$ID" "frontier" \
  "Retrieval + a shared commons. Fine-tuning freezes knowledge and each seat drifts; the commons stays live and every seat reads the same facts. The small model stays cheap and current."

echo
echo "5) the SMALL model just READS the answer — it never held the frontier's keys:"
bash "$here/membrane.sh" "$DB" read "$ID"

echo
echo "done. asker and answerer never coupled; the row carried the handoff."
