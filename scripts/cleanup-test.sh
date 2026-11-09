#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || -z "$1" ]]; then
  echo "Usage: $0 YOUR_LAB_CONTEXT" >&2
  exit 1
fi
NAMESPACE="datastore-load-test"
KUBECTL=(kubectl --context "$1" --request-timeout=30s)
namespace="$("${KUBECTL[@]}" get namespace "$NAMESPACE" --ignore-not-found -o name)"
if [[ -z "$namespace" ]]; then
  echo "Test namespace does not exist; nothing to remove."
  exit 0
fi
owner="$("${KUBECTL[@]}" get namespace "$NAMESPACE" \
  -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}')"
if [[ "$owner" != "$NAMESPACE" ]]; then
  echo "Refusing cleanup: namespace ownership does not match." >&2
  exit 1
fi
echo "This deletes namespace $NAMESPACE and its PVC/data in context $1."
read -r -p "Type '$NAMESPACE' to confirm: " confirmation
if [[ "$confirmation" != "$NAMESPACE" ]]; then
  echo "Cleanup cancelled." >&2
  exit 1
fi
"${KUBECTL[@]}" delete namespace "$NAMESPACE" --wait=true --timeout=5m
