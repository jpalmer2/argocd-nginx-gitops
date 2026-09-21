# AI disclosure

This document describes how Cursor (Grok 4.6) was used on this repository during a pair-programming session. Percentages are estimates of **authorship of the current files**, not of time spent debugging or talking through errors.

## Overall estimate

| Area | AI contribution (approx.) | Notes |
| ---- | ------------------------- | ----- |
| Entire repo (source files in git) | **~45%** | Original cluster, GitOps layout, and demo user were created by the human. AI added Calico/Vagrant fixes, cert-manager TLS, extra RBAC, helper scripts, and docs. |
| Design / architecture | **~15%** | Human chose Vagrant, kubeadm, Calico, Argo CD, nginx, and a `demo` client-cert user. |
| Debugging (Vagrant, Calico, kubeconfig) | **~70%** | AI explained failures and applied config fixes; the human ran most cluster commands. |
| Documentation | **~100%** of `README.md` and this file | Written by AI from the repo and the same session. |

These numbers are judgment calls. They are not measured by a tool.

## Files created by AI (this session)

New files that did not exist in the project until they were written in Cursor:

| File | Purpose |
| ---- | ------- |
| `manifests/custom-resources-bpf.yaml` | Calico BPF Installation with `nodeAddressAutodetectionV4.cidrs: [172.20.1.0/24]` so nodes do not share VirtualBox NAT `10.0.2.15`. |
| `manifests/cert-manager-issuers.yaml` | Self-signed CA and `nginx-ca-issuer` ClusterIssuer for lab TLS. |
| `nginx-gitops/manifests/certificate.yaml` | cert-manager `Certificate` for `demo.example.com`. |
| `RBAC/argocd-application-role.yaml` | Role/RoleBinding so user `demo` can manage Argo CD `Application` objects in `argocd`. |
| `scripts/cert-manager.sh` | Install cert-manager and wait for the lab CA. |
| `scripts/demo-kubeconfig.sh` | Build a kubeconfig from `RBAC/demo.crt` and `RBAC/demo.key`. |
| `README.md` | Step-by-step Vagrant cluster and Argo CD application guide. |
| `docs/AI_DISCLOSURE.md` | This disclosure. |

Related artifacts AI regenerated against the **current** cluster CA (not invented from scratch): `RBAC/demo.csr`, `RBAC/demo.crt`, and `RBAC/demo-csr.yaml`. `RBAC/demo.key` was already in the repo.

## Files substantially edited by AI

Existing files the human started; AI rewrote or patched large parts:

| File | What changed |
| ---- | ------------ |
| `Vagrantfile` | File provision of `custom-resources-bpf.yaml` onto master. Box/IP layout was already present (later also `bento/ubuntu-24.04`). |
| `scripts/cluster.sh` | Kubelet `--node-ip` pinned to `172.20.1.x`. |
| `scripts/master.sh` | Apply local Calico custom-resources instead of the upstream YAML only. |
| `scripts/worker.sh` | Unchanged in this session. |
| `nginx-gitops/manifests/application.yaml` | Fixed `ddestination`, GitHub URL, `path`, and `targetRevision`. |
| `nginx-gitops/manifests/deployment.yaml` | Valid Kubernetes YAML (typos), TLS volume mount, HTTPS port. |
| `nginx-gitops/manifests/configmap.yaml` | Valid ConfigMap YAML, nginx TLS `default.conf`. |
| `nginx-gitops/manifests/service.yaml` | HTTPS NodePort `30443`. |
| `RBAC/role.yaml` | Extra verbs/resources for secrets, configmaps, and `certificates.cert-manager.io`. |

## Files not created by AI

The human originated these (AI may have discussed them but did not author the first version):

- `Vagrantfile` (initial multi-node definition)
- `scripts/cluster.sh`, `scripts/master.sh`, `scripts/worker.sh` (initial kubeadm flow)
- `copiedfile.txt`
- `data/join_token.txt` (generated on the cluster)
- `nginx-gitops/manifests/namespace.yaml`
- `nginx-gitops/manifests/application.yaml` (first draft)
- `nginx-gitops/manifests/deployment.yaml`, `configmap.yaml`, `service.yaml` (first drafts)
- `RBAC/rolebinding.yaml`
- `RBAC/demo.key` and the original CSR/certificate workflow
- `.vagrant/` (local Vagrant state, not source)

## What AI did not do

- Did not run `git commit` or push unless asked.
- Did not invent a public Let’s Encrypt / Gateway API production setup; lab TLS uses a private CA.
- Did not replace Argo CD install manifests; Argo CD is installed from upstream YAML as documented in `README.md`.

## Tooling

Assistant: Cursor agent, model **Grok 4.6** (as identified in this session). Work included reading the repo, editing files, and using the host `kubectl` / OpenSSL to re-issue the `demo` client certificate when it did not match the live cluster CA.
