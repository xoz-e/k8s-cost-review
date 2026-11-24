#!/usr/bin/env bash
# Dry run against test/mock/kubectl. No cluster required.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tool="${root}/bin/k8s-cost-review"
mock="${root}/test/mock/kubectl"
sample="${root}/examples/sample-report.md"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

run() {
  # Prefix assignments so the mock sees MOCK_* even when this function is
  # itself called with a temporary assignment.
  MOCK_TOP="${MOCK_TOP:-ok}" \
    MOCK_PROM="${MOCK_PROM:-ok}" \
    MOCK_SLICES="${MOCK_SLICES:-ok}" \
    KUBECTL="$mock" \
    REVIEW_TIMESTAMP=2026-11-24T09:00:00Z \
    "$tool" "$@"
}

run --help >/dev/null

if run --nope >/dev/null 2>"$tmp/nope.err"; then
  printf '%s\n' "expected an unknown argument to fail" >&2
  exit 1
fi
grep -q "unknown argument" "$tmp/nope.err"

happy="$(run --context demo --internal-registry registry.internal.example)"
printf '%s\n' "$happy" >"$tmp/actual.md"

if grep -n '[$%]' "$tmp/actual.md"; then
  printf '%s\n' "report contains a currency or percent sign" >&2
  exit 1
fi

awk 'f { print } $0 == "<!-- BEGIN REPORT -->" { f = 1 }' "$sample" >"$tmp/expected.md"
diff -u "$tmp/expected.md" "$tmp/actual.md"

grep -q "Fictional" "$sample"
grep -q "old-edge" "$tmp/actual.md"
grep -q "pv-orphan" "$tmp/actual.md"
grep -q "nothing running" "$tmp/actual.md"
if grep -q "203.0.113.20" "$tmp/actual.md"; then
  printf '%s\n' "in-use LoadBalancer was reported" >&2
  exit 1
fi

skipped="$(MOCK_PROM=fail MOCK_TOP=fail run --context demo --internal-registry registry.internal.example)"
grep -q "Rightsizing waits on a measurement" <<<"$skipped"
grep -q "sandbox" <<<"$skipped"
if grep -q "request well above usage" <<<"$skipped"; then
  printf '%s\n' "skip path still listed a rightsizing row" >&2
  exit 1
fi

top_only="$(MOCK_PROM=fail MOCK_TOP=ok run --context demo --internal-registry registry.internal.example)"
grep -q "metrics-server, one sample" <<<"$top_only"
grep -q "request well above usage" <<<"$top_only"

endpoints="$(MOCK_SLICES=fail run --context demo --internal-registry registry.internal.example)"
grep -q "old-edge" <<<"$endpoints"
grep -q "203.0.113.31" <<<"$endpoints"
grep -q "Prometheus monitoring/prometheus" <<<"$endpoints"

plain="$(run --context demo)"
if grep -q "registry.internal.example" <<<"$plain"; then
  printf '%s\n' "mirror host appeared without --internal-registry" >&2
  exit 1
fi
grep -q "nginx:1.25" <<<"$plain"
grep -q "public registry" <<<"$plain"

context="$(run)"
grep -q "| Context | demo |" <<<"$context"

if grep -nE '^[^#]*\b(k_get|k_top)\b.*\b(apply|delete|patch|replace|scale|edit|create|exec|drain|cordon)\b' \
  "${root}/bin/k8s-cost-review"; then
  printf '%s\n' "mutating kubectl invocation" >&2
  exit 1
fi

printf '%s\n' "dry run ok"
