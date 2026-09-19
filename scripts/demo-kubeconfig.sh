#!/bin/bash
# Build a kubeconfig for User "demo" from the CSR-signed client cert.
# Run this with an admin kubeconfig already working (the one from the master node).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/RBAC/demo.kubeconfig}"
CRT="$ROOT/RBAC/demo.crt"
KEY="$ROOT/RBAC/demo.key"

if ! kubectl version --client >/dev/null 2>&1; then
  echo "kubectl is required" >&2
  exit 1
fi

if ! kubectl get --raw=/readyz >/dev/null 2>&1; then
  echo "Admin kubeconfig is not working. Copy /etc/kubernetes/admin.conf from master first:" >&2
  echo "  vagrant ssh master -c 'sudo cat /etc/kubernetes/admin.conf' > ~/.kube/teleport" >&2
  echo "  export KUBECONFIG=~/.kube/teleport" >&2
  exit 1
fi

if [[ ! -f "$CRT" || ! -f "$KEY" ]]; then
  echo "Missing $CRT or $KEY" >&2
  exit 1
fi

SERVER="$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.server}')"
CA_B64="$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
CA_FILE="$(mktemp)"
trap 'rm -f "$CA_FILE"' EXIT
printf '%s' "$CA_B64" | base64 --decode > "$CA_FILE"

rm -f "$OUT"
kubectl config --kubeconfig="$OUT" set-cluster kubernetes \
  --server="$SERVER" \
  --certificate-authority="$CA_FILE" \
  --embed-certs=true
kubectl config --kubeconfig="$OUT" set-credentials demo \
  --client-certificate="$CRT" \
  --client-key="$KEY" \
  --embed-certs=true
kubectl config --kubeconfig="$OUT" set-context demo \
  --cluster=kubernetes \
  --user=demo \
  --namespace=nginx-demo
kubectl config --kubeconfig="$OUT" use-context demo

echo "Wrote $OUT"
echo "Use it with:"
echo "  export KUBECONFIG=$OUT"
echo "  kubectl get pods -n nginx-demo"
