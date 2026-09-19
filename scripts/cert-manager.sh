#!/bin/bash
set -euo pipefail

kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.18.2/cert-manager.yaml
kubectl -n cert-manager rollout status deploy/cert-manager --timeout=180s
kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=180s
kubectl -n cert-manager rollout status deploy/cert-manager-cainjector --timeout=180s

kubectl apply -f "$(dirname "$0")/../manifests/cert-manager-issuers.yaml"
kubectl -n cert-manager wait --for=condition=Ready certificate/nginx-demo-ca --timeout=180s
