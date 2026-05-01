# flask-app-jenkins — demo app for the jenkins-shared-lib pipeline

A tiny Flask "Hello, World" service used to exercise the full pipeline provided by
[`jenkins-shared-lib`](../jenkins-shared-lib):

```
docker build  →  Trivy SBOM (CycloneDX)  →  upload to MinIO  →  helm package  →  ArgoCD deploy → docker-desktop k8s
```

## Layout

```
flask-app-jenkins/
├── app.py                                    # Flask hello-world (port 8080)
├── requirements.txt                          # flask + gunicorn
├── Dockerfile                                # python:3.12-slim, runs as non-root
├── .dockerignore
├── Jenkinsfile                               # one-line ciCdPipeline call
└── charts/flask-app-jenkins/                 # Helm chart
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
        ├── _helpers.tpl
        ├── deployment.yaml
        ├── service.yaml
        ├── ingress.yaml
        └── NOTES.txt
```

## Run the app locally (smoke test before Jenkins)

```bash
# 1. Run with python directly
pip install -r requirements.txt
python app.py
# in another terminal:
curl http://localhost:8080/
# {"app":"flask-app-jenkins","host":"...","message":"Hello, World!","version":"0.1.0"}

# 2. Or with docker
docker build -t flask-app-jenkins:dev .
docker run --rm -p 8080:8080 flask-app-jenkins:dev
curl http://localhost:8080/healthz   # {"status":"ok"}
```

## What you need running before the Jenkins pipeline will succeed

The pipeline assumes a few services are reachable from the Jenkins agent. Get these up
first — copy-paste-runnable on macOS / docker-desktop:

### 1. Local Docker registry (so `docker push localhost:5000/...` works)

```bash
docker run -d --restart=always --name registry -p 5000:5000 registry:2
# verify
curl -s http://localhost:5000/v2/_catalog
```

### 2. MinIO (for SBOM storage)

```bash
docker run -d --restart=always --name minio \
  -p 9000:9000 -p 9001:9001 \
  -e MINIO_ROOT_USER=minioadmin \
  -e MINIO_ROOT_PASSWORD=minioadmin \
  -v minio-data:/data \
  quay.io/minio/minio:latest server /data --console-address ":9001"
```

- API endpoint: `http://localhost:9000`
- Web console: `http://localhost:9001`  (login `minioadmin` / `minioadmin`)
- The pipeline expects the API at `http://localhost:9001` per the original requirement;
  if your MinIO uses port 9000 for the API, change `minio.endpoint` in the Jenkinsfile.

After login, create a bucket called `sboms` (the pipeline will also auto-create it via
`mc mb --ignore-existing`).

### 3. ArgoCD on docker-desktop Kubernetes

Make sure Kubernetes is enabled in Docker Desktop, then:

```bash
kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# wait for it
kubectl -n argocd rollout status deploy/argocd-server

# get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d ; echo

# expose the UI
kubectl -n argocd port-forward svc/argocd-server 8080:443
# open https://localhost:8080  (login: admin / <pw above>)
```

### 4. Jenkins (with required tools on the agent)

If you don't already have Jenkins, the quickest way is the LTS image with the Docker
socket mounted so it can build images:

```bash
docker run -d --name jenkins -p 8081:8080 -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --group-add $(stat -c '%g' /var/run/docker.sock 2>/dev/null || echo 0) \
  jenkins/jenkins:lts-jdk17

# initial admin password
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Then in Jenkins:

1. Install suggested plugins, plus: **Pipeline Utility Steps**, **AnsiColor**,
   **Timestamper**, **Credentials Binding** (most are bundled with the suggested set).
2. Make sure the agent has Docker, `helm`, `kubectl`, and (optional) `argocd` CLI on the
   PATH. With the `jenkins/jenkins` image you'll need to `docker exec -u root jenkins`
   and install them — or run a sidecar agent that has these tools.
3. Mount your kubeconfig into Jenkins so `kubectl` can reach docker-desktop:
   `-v ~/.kube:/var/jenkins_home/.kube` when starting the container, then set
   `KUBECONFIG=/var/jenkins_home/.kube/config` in the agent's environment.

## Register the shared library in Jenkins

(Detailed walkthrough in `../jenkins-shared-lib/README.md`.) Quick version:

1. Push `jenkins-shared-lib/` to a Git host Jenkins can reach (or expose it locally over HTTP).
2. **Manage Jenkins → System → Global Pipeline Libraries → Add**:
   - Name: `jenkins-shared-lib`
   - Default version: `main`
   - Retrieval method: *Modern SCM → Git*
   - Project Repository: URL of the shared lib repo
3. Save.

## Add the Jenkins credential the pipeline needs

**Manage Jenkins → Credentials → System → Global → Add Credentials**

- **Kind:** Username with password
- **ID:** `minio-creds`
- **Username:** `minioadmin`  *(MinIO access key)*
- **Password:** `minioadmin`  *(MinIO secret key)*

(Optional — only if you set `registry.credentialsId` in the Jenkinsfile)
- **Kind:** Username with password
- **ID:** `docker-registry-creds`
- Username/password for your private registry

## Create the Jenkins job for this app

1. **New Item → Pipeline → OK**
2. Pipeline section:
   - **Definition:** Pipeline script from SCM
   - **SCM:** Git
   - **Repository URL:** wherever you push `flask-app-jenkins/`
   - **Branch Specifier:** `*/main`
   - **Script Path:** `Jenkinsfile`
3. Save → **Build Now**.

## What happens when the pipeline runs

| Stage | What it does | Where to see it |
| --- | --- | --- |
| Checkout | Clones this repo | Build console |
| Build image | `dockerBuild` → `localhost:5000/flask-app-jenkins:<build#>` | Build console; `docker images` |
| Generate SBOM | Trivy → `sbom/sbom.cdx.json` (CycloneDX JSON) | Archived as build artifact |
| Upload SBOM to MinIO | `mc cp` → `sboms/<job>/<build#>/sbom.cdx.json` | http://localhost:9001 → `sboms` bucket |
| Package Helm chart | `helm lint` + `helm package`, rewrites image repo/tag | Archived as `helm-pkg/flask-app-jenkins-1.0.<build#>.tgz` |
| Deploy via ArgoCD | Renders an ArgoCD `Application`, applies it to the `argocd` namespace, syncs, waits for Healthy | https://localhost:8080 (ArgoCD UI) |

After a successful run, verify the deployment:

```bash
kubectl -n flask-app get pods,svc
kubectl -n flask-app port-forward svc/flask-app-jenkins-flask-app-jenkins 8080:80
curl http://localhost:8080/
```

## Trying it without Jenkins (local equivalent)

You can run the same steps end-to-end on your laptop to debug:

```bash
# 1) Build the image
docker build -t localhost:5000/flask-app-jenkins:dev .
docker push localhost:5000/flask-app-jenkins:dev

# 2) Generate SBOM with Trivy (same tool the library uses)
mkdir -p sbom
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PWD:/work" -w /work \
  aquasec/trivy:0.50.0 image \
    --format cyclonedx \
    --output sbom/sbom.cdx.json \
    localhost:5000/flask-app-jenkins:dev

# 3) Upload to MinIO
docker run --rm --network host \
  -e MC_ACCESS=minioadmin -e MC_SECRET=minioadmin \
  -v "$PWD:/work" -w /work \
  --entrypoint sh minio/mc:latest -c '
    mc alias set sbomstore http://localhost:9001 "$MC_ACCESS" "$MC_SECRET"
    mc mb --ignore-existing sbomstore/sboms
    mc cp sbom/sbom.cdx.json sbomstore/sboms/local/sbom.cdx.json
  '

# 4) Package the chart
helm lint charts/flask-app-jenkins
helm package charts/flask-app-jenkins -d helm-pkg --version 0.1.0 --app-version dev

# 5) Install directly with helm (skip ArgoCD)
helm upgrade --install flask-app charts/flask-app-jenkins \
  --namespace flask-app --create-namespace \
  --set image.repository=localhost:5000/flask-app-jenkins \
  --set image.tag=dev

kubectl -n flask-app port-forward svc/flask-app-flask-app-jenkins 8080:80
curl http://localhost:8080/
```

## Troubleshooting

- **`docker: Cannot connect to the Docker daemon`** in the Jenkins build — the agent
  isn't sharing the Docker socket. Re-run the Jenkins container with
  `-v /var/run/docker.sock:/var/run/docker.sock`.
- **`kubectl: error: ... unable to load configuration`** — the agent doesn't have a
  kubeconfig. Mount `~/.kube` into the Jenkins container or copy the file into the
  agent.
- **ArgoCD app stuck `OutOfSync`** — make sure the chart in the repo (`charts/flask-app-jenkins`)
  matches what's referenced in the Jenkinsfile and that the repo URL ArgoCD is hitting
  is reachable from the docker-desktop cluster.
- **MinIO upload fails with auth error** — verify the `minio-creds` credential's
  username/password match your MinIO root user/password.
- **Trivy DB download is slow** — Trivy downloads its vuln DB on first run. Subsequent
  runs hit the cache.

## Where the SBOM ends up

After every successful build:

- Build artifact in Jenkins (`sbom/sbom.cdx.json`) — downloadable from the build page.
- MinIO object: `sboms/<JOB_NAME>/<BUILD_NUMBER>/sbom.cdx.json` — visible at
  http://localhost:9001 → bucket `sboms`.

You can pull it back later with:

```bash
mc cp sbomstore/sboms/<job>/<build>/sbom.cdx.json ./sbom-from-minio.cdx.json
```

## Pointing this at a different cluster or registry

Edit `Jenkinsfile` — every change is in one place:

| What to change | Field |
| --- | --- |
| Different registry | `registry.url`, optionally `registry.credentialsId` |
| Don't push, just build locally | `registry.url: ''`, `registry.push: false` |
| Different MinIO instance | `minio.endpoint`, `minio.bucket`, `minio.credentialsId` |
| Different ArgoCD repo / branch | `argocd.repoUrl`, `argocd.targetRevision` |
| Different cluster | `argocd.destServer` (e.g. `https://my-prod-cluster.example.com`) |
# flask-app-jenkins
