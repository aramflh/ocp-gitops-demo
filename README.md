# OpenShift GitOps Demo

A minimal GitOps demonstration for OpenShift. Two apps are managed by Argo CD: one is **live** at the start; the other is **empty** so you can add manifests during the demo and watch them sync.

## Prerequisites

- `oc` CLI installed and logged in (cluster admin or sufficient privileges)

## Setup

1. **Install OpenShift GitOps and get Argo CD URL & credentials**

   ```bash
   ./scripts/setup-gitops.sh
   ```

   Open the printed URL in a browser and log in with the shown credentials.

2. **Connect the repository to Argo CD**

   Argo CD must be able to clone this Git repo. Choose one:

   - **Public repo (GitHub/GitLab/etc.)**  
     Push this repo to your Git server. No extra Argo CD config is needed; the Application manifests will reference the repo URL.

   - **Private repo**  
     Add the repo in Argo CD with credentials.

     **Via Argo CD UI:** Settings → Repositories → Connect Repo. Enter the repo URL, and username/password or SSH key, then Connect.

     **Via CLI (after installing `argocd`):**
     ```bash
     argocd repo add https://github.com/YOUR_ORG/ocp-gitops-demo.git \
       --username YOUR_GIT_USER \
       --password YOUR_TOKEN_OR_PASSWORD
     ```
     For SSH:
     ```bash
     argocd repo add git@github.com:YOUR_ORG/ocp-gitops-demo.git
     ```

     **Via OpenShift (Secret in `openshift-gitops`):** Create a Secret of type `argocd.argoproj.io/secret` with the repo URL and credentials so the GitOps operator picks it up.

3. **Configure the Git repo URL in the Application manifests**

   In `application-app1.yaml` and `application-app2.yaml`, set `spec.source.repoURL` to your Git repository URL (e.g. `https://github.com/YOUR_ORG/ocp-gitops-demo.git`). Use the same URL and branch/tag as in step 2.

4. **Register the applications with Argo CD**

   ```bash
   oc apply -f application-app1.yaml
   oc apply -f application-app2.yaml
   ```

   Argo CD will sync from the connected repo; ensure your commits are pushed to the `targetRevision` branch (e.g. `main`).

## Repo layout

| Path | Purpose |
|------|--------|
| `apps/app1/` | **Live app** — namespace, deployment, service, and route. Running and accessible at the start of the demo. |
| `apps/app2/` | **Empty app** — only `.gitkeep`. Add Kubernetes manifests here during the demo; Argo CD will sync them to the cluster. |
| `application-app1.yaml` | Argo CD Application that points to `apps/app1`. |
| `application-app2.yaml` | Argo CD Application that points to `apps/app2`. |
| `doc/` | Additional documentation (unchanged). |
| `scripts/` | Setup and helper scripts (unchanged). |

## Demo flow

1. **Before the demo**: Push the repo (with `apps/app1` and `apps/app2` as above). Apply the two Application manifests. Argo CD shows **demo-app-live** (Synced/Healthy) and **demo-app-empty** (Synced, no resources or minimal state).

2. **Live app**: Open the route for the live app (e.g. `oc get route -n gitops-demo-live`) and show the app in the browser. Show it in the Argo CD UI and in the OpenShift cluster.

3. **Empty app**: Add one or more Kubernetes manifests under `apps/app2/` (e.g. a Namespace and a Deployment), commit and push. Argo CD syncs; the new resources appear in the Argo CD UI and in the cluster.

## Accessing the live app

After sync, get the route host:

```bash
oc get route -n gitops-demo-live demo-app -o jsonpath='{.spec.host}'
```

Open `https://<host>` in a browser (accept the TLS warning if needed).

## Manual installation

See [doc/manual-installation.md](doc/manual-installation.md) for manual GitOps operator installation and troubleshooting.
