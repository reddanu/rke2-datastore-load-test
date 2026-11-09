#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || -z "$1" ]]; then
  echo "Usage: $0 YOUR_LAB_CONTEXT" >&2
  exit 1
fi
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="datastore-load-test"
KUBECTL=(kubectl --context "$1" --request-timeout=30s)

"${KUBECTL[@]}" get --raw=/readyz
"${KUBECTL[@]}" top nodes
namespace="$("${KUBECTL[@]}" get namespace "$NAMESPACE" --ignore-not-found -o name)"
if [[ -n "$namespace" ]]; then
  owner="$("${KUBECTL[@]}" get namespace "$NAMESPACE" \
    -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}')"
  if [[ "$owner" != "$NAMESPACE" ]]; then
    echo "Refusing to modify a namespace without the expected ownership label." >&2
    exit 1
  fi
  jobs="$("${KUBECTL[@]}" -n "$NAMESPACE" get jobs \
    -l app.kubernetes.io/name=load-generator -o name)"
  if [[ -n "$jobs" ]]; then
    echo "Existing load jobs found. Review and delete them before rerunning." >&2
    exit 1
  fi
fi
mkdir -p "$ROOT_DIR/results"
log_file="$ROOT_DIR/results/k6-$(date -u +%Y%m%dT%H%M%SZ).log"
printf 'Started at %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$log_file"
"${KUBECTL[@]}" top nodes >> "$log_file"
"${KUBECTL[@]}" apply -k "$ROOT_DIR/manifests"
"${KUBECTL[@]}" -n "$NAMESPACE" rollout status deployment/api --timeout=5m
"${KUBECTL[@]}" -n "$NAMESPACE" wait \
  --for=jsonpath='{.status.phase}'=Bound --timeout=5m pvc/api-data
job="$("${KUBECTL[@]}" -n "$NAMESPACE" create \
  -f "$ROOT_DIR/manifests/load-generator.yaml" -o name)"
printf 'Job: %s\n' "$job" >> "$log_file"
deadline=$((SECONDS + 780))
outcome=1
while (( SECONDS < deadline )); do
  complete="$("${KUBECTL[@]}" -n "$NAMESPACE" get "$job" \
    -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')"
  failed="$("${KUBECTL[@]}" -n "$NAMESPACE" get "$job" \
    -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}')"
  if [[ "$complete" == "True" ]]; then
    outcome=0
    break
  fi
  if [[ "$failed" == "True" ]]; then
    break
  fi
  sleep 5
done
if ! "${KUBECTL[@]}" -n "$NAMESPACE" logs "$job" >> "$log_file" 2>&1; then
  echo "Could not retrieve Job logs; inspect $job." >&2
  outcome=1
fi
"${KUBECTL[@]}" -n "$NAMESPACE" get "$job" -o yaml >> "$log_file"
"${KUBECTL[@]}" top nodes >> "$log_file"
tail -n 55 "$log_file"
echo "Results: $log_file"
if (( outcome != 0 )); then
  echo "Load test failed or timed out. Resources retained for inspection." >&2
fi
exit "$outcome"
