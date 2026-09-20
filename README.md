# Teleport kubeadm lab

This repo builds a three-node Kubernetes cluster with Vagrant and VirtualBox, installs Calico, and deploys an nginx demo through Argo CD. A limited Kubernetes user named `demo` creates the Argo CD `Application`; cluster-admin is used for the control plane, Calico, Argo CD, cert-manager, and RBAC.

| Node     | IP           | Role           |
| -------- | ------------ | -------------- |
| master   | 172.20.1.50  | control plane  |
| worker1  | 172.20.1.51  | worker         |
| worker2  | 172.20.1.52  | worker         |

Kubernetes v1.37, Ubuntu 24.04 (`bento/ubuntu-24.04`), pod CIDR `192.168.0.0/16`. Each VM is 4 CPUs and 4 GB RAM (about 12 GB RAM plus the host).

## Prerequisites

On the Mac (or Linux host):

- [VirtualBox](https://www.virtualbox.org/)
- [Vagrant](https://developer.hashicorp.com/vagrant)
- `kubectl` matching the cluster (1.37.x)
- Enough disk for three boxes and images

Optional: `vagrant-vbguest` if guest additions fail to update.

Clone this repository and work from the repo root (the directory that contains `Vagrantfile`).

```bash
cd /path/to/teleport
```

## 1. Create the Kubernetes cluster with Vagrant

### 1.1 Bring up all three VMs

Do **not** run `vagrant up master` by itself. Workers are never created that way, and a later `vagrant provision` will print `VM not created. Moving on...`.

```bash
vagrant up
```

What this does:

1. Creates `master`, `worker1`, and `worker2` on the host-only network `172.20.1.0/24`.
2. On every node, `scripts/cluster.sh` installs containerd, kubelet, kubeadm, and kubectl, and pins kubelet `--node-ip` to `172.20.1.x` (VirtualBox NAT is `10.0.2.15` on every VM; Calico cannot use that address).
3. On **master**, `scripts/master.sh` runs `kubeadm init`, installs Calico (Tigera operator + BPF custom resources), and writes a join command to `data/join_token.txt`.
4. On **workers**, `scripts/worker.sh` runs that join command.

The first `vagrant up` can take a long time (box download, packages, kubeadm, Calico). Leave it running until Vagrant returns to the shell.

If master already exists and you only need workers:

```bash
vagrant up worker1 worker2
```

If a machine was already provisioned and you need to re-run scripts:

```bash
vagrant up --provision
# or
vagrant provision
```

`vagrant provision` only works on VMs that already exist.

### 1.2 Confirm the VMs and the cluster

```bash
vagrant status
vagrant ssh master -c "kubectl get nodes -o wide"
vagrant ssh master -c "kubectl get pods -A"
```

All three nodes should be `Ready`. Calico pods in `calico-system` and CoreDNS in `kube-system` should be `Running`. There is no `kube-proxy` DaemonSet; Calico BPF replaces it.

If `calico-node` crash-loops with `IPv4 address conflict` on `10.0.2.15`, autodetection is still using NAT. The Installation CR must use only:

```yaml
nodeAddressAutodetectionV4:
  cidrs:
    - 172.20.1.0/24
```

Replace the whole field (do not merge `cidrs` on top of `firstFound: true`):

```bash
vagrant ssh master -c 'kubectl patch installation default --type=json -p "[{\"op\": \"replace\", \"path\": \"/spec/calicoNetwork/nodeAddressAutodetectionV4\", \"value\": {\"cidrs\": [\"172.20.1.0/24\"]}}]"'
```

### 1.3 Copy admin kubeconfig to the host

From the host:

```bash
mkdir -p ~/.kube
vagrant ssh master -c "sudo cat /etc/kubernetes/admin.conf" > ~/devops/kubeconfig
# or any path you prefer, for example ~/.kube/teleport
export KUBECONFIG=~/devops/kubeconfig
kubectl config use-context kubernetes-admin@kubernetes
kubectl get nodes -o wide
```

`server:` in that file should be `https://172.20.1.50:6443`. The host must reach that address on the VirtualBox host-only network.

If you already have both `kubernetes-admin` and `demo` in `~/devops/kubeconfig`, keep using `--context` so you do not apply cluster-admin objects as `demo`.

## 2. Install Argo CD (cluster-admin)

The Application CRD and `argocd` namespace are not created by Vagrant. Install Argo CD once as admin:

```bash
export KUBECONFIG=~/devops/kubeconfig
kubectl config use-context kubernetes-admin@kubernetes

kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
kubectl get pods -n argocd
```

Wait until `argocd-server`, `argocd-repo-server`, `argocd-application-controller`, and Redis are `Running`.

Optional: port-forward the UI.

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

Initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 --decode; echo
```

Log in at `https://localhost:8080` as `admin`.

## 3. Install cert-manager (cluster-admin)

Needed so the nginx GitOps path can request `Certificate` `nginx-demo-tls`. Run from the repo root with the admin context:

```bash
export KUBECONFIG=~/devops/kubeconfig
kubectl config use-context kubernetes-admin@kubernetes
chmod +x scripts/cert-manager.sh
./scripts/cert-manager.sh
```

This installs cert-manager v1.18.2 and a private CA `ClusterIssuer` named `nginx-ca-issuer`. Let’s Encrypt is not used: this lab has no public DNS.

## 4. Namespaces and RBAC (cluster-admin)

`demo` is a Kubernetes user (client certificate CN `demo`), not a ServiceAccount. Create the app namespace and bind roles **before** `demo` applies anything.

```bash
export KUBECONFIG=~/devops/kubeconfig
kubectl config use-context kubernetes-admin@kubernetes

kubectl apply -f nginx-gitops/manifests/namespace.yaml
kubectl apply -f RBAC/role.yaml
kubectl apply -f RBAC/rolebinding.yaml
kubectl apply -f RBAC/argocd-application-role.yaml
```

That grants `demo`:

- pods, deployments, services, configmaps, secrets, and cert-manager `certificates` in `nginx-demo`
- Argo CD `applications` in `argocd`

`demo` cannot create cluster-scoped objects (namespaces, ClusterIssuers) and cannot install Argo CD.

## 5. Demo user kubeconfig

Client certs in `RBAC/demo.crt` are only valid if they were **signed by this cluster’s CA**. After `vagrant destroy` / a new `vagrant up`, the old cert is rejected with `Unauthorized`. Re-issue as admin:

```bash
export KUBECONFIG=~/devops/kubeconfig
kubectl config use-context kubernetes-admin@kubernetes

openssl req -new -key RBAC/demo.key -out RBAC/demo.csr -subj "/CN=demo/O=developers"
kubectl delete csr demo --ignore-not-found
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: demo
spec:
  request: $(base64 < RBAC/demo.csr | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 31536000
  usages:
    - client auth
EOF
kubectl certificate approve demo
kubectl get csr demo -o jsonpath='{.status.certificate}' | base64 --decode > RBAC/demo.crt

kubectl config set-credentials demo \
  --client-certificate="$PWD/RBAC/demo.crt" \
  --client-key="$PWD/RBAC/demo.key" \
  --embed-certs=true
```

`--embed-certs=true` is required. Relative paths such as `demo.crt` resolve from the current directory and fail if the files live in `RBAC/`.

Switch to `demo` and confirm authentication. Success is a normal API response or `Forbidden`, **not** `Unauthorized`.

```bash
kubectl config use-context demo@kubernetes
kubectl get pods -n nginx-demo
```

`kubectl auth whoami` may return `Forbidden` because `demo` cannot create `selfsubjectreviews`. That does not mean login failed.

If OpenAPI validation returns `the server has asked for the client to provide credentials`, the context is still not sending the client cert. Fix the kubeconfig first, or use `--validate=false` only after `kubectl get pods -n nginx-demo` works.

## 6. Create the Argo CD Application (demo user)

The Application points at GitHub `https://github.com/jpalmer2/argocd-nginx-gitops.git`, branch `master`, path `nginx-gitops/manifests`, destination namespace `nginx-demo`.

Push this repo to that remote (or change `spec.source` in `nginx-gitops/manifests/application.yaml` to your fork) **before** Argo syncs, or the application will stay `Unknown` / `ComparisonError`.

As **demo**:

```bash
export KUBECONFIG=~/devops/kubeconfig
kubectl config use-context demo@kubernetes

kubectl apply -f nginx-gitops/manifests/application.yaml
kubectl get applications.argoproj.io -n argocd
```

Do not apply the whole `nginx-gitops/manifests` directory as the Argo Application if you want GitOps to own the nginx resources. Apply **only** `application.yaml`. Argo then syncs Deployment, Service, ConfigMaps, Certificate, and related objects from Git.

`CreateNamespace=true` is set, but `demo` still needed the namespace (or cluster-admin) in step 4 if that option is insufficient for your Argo version/project.

Watch the app:

```bash
kubectl get applications.argoproj.io nginx-demo -n argocd -w
kubectl get pods,svc,certificate -n nginx-demo
```

Healthy state: Application `Synced` / `Healthy`, nginx pods `Running`, Certificate `nginx-demo-tls` `Ready`.

Optional UI: create the same app in Argo CD with repository URL, revision `master`, path `nginx-gitops/manifests`, destination `https://kubernetes.default.svc` / `nginx-demo`.

## 7. What Argo deploys

| File | Purpose |
| ---- | ------- |
| `namespace.yaml` | `nginx-demo` namespace |
| `configmap.yaml` | HTML + nginx TLS server config |
| `deployment.yaml` | nginx 1.25.3, mounts cert-manager Secret `nginx-demo-tls` |
| `service.yaml` | NodePort `30443` → container 443 |
| `certificate.yaml` | cert-manager cert for `demo.example.com` |
| `application.yaml` | Argo CD Application (applied by `demo`, not by the nginx workload) |

Because `application.yaml` lives in the same Git path Argo syncs, Argo may also try to apply that CR into `nginx-demo`. If that causes sync errors, move `application.yaml` out of `nginx-gitops/manifests` (for example to `argocd/application.yaml`) and set `spec.source.path` to the folder that contains only the nginx manifests.

## 8. Hit nginx over TLS (optional)

cert-manager does not register DNS. On the host:

```text
# /etc/hosts
172.20.1.50  demo.example.com
```

Then open `https://demo.example.com:30443`. The browser will warn: the issuer is the lab CA, not a public CA.

## Useful commands

```bash
vagrant status
vagrant ssh master
vagrant halt          # stop VMs
vagrant up            # start existing VMs without wiping the cluster
vagrant destroy -f    # delete VMs; next vagrant up is a new cluster
```

After `destroy`, re-issue the `demo` client certificate (step 5) and reinstall Argo CD and cert-manager.

## Layout

```text
Vagrantfile
scripts/cluster.sh          # all nodes
scripts/master.sh           # kubeadm init + Calico
scripts/worker.sh           # kubeadm join
scripts/cert-manager.sh     # cert-manager + CA issuer
manifests/custom-resources-bpf.yaml
manifests/cert-manager-issuers.yaml
nginx-gitops/manifests/     # Argo application source
RBAC/                       # demo user CSR, roles, bindings
data/                       # join command (written on master)
```
