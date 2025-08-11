#!/bin/bash

# Check if binaries are present
for binary in helm kubectl grep sed mktemp curl tr; do
  [ -x "$(command -v "${binary}")" ] || {
    echo "Error: ${binary} not found"
    exit 1
  }
done

# If namespace argocd already exists 
if [ "$(kubectl get namespace argocd >/dev/null 2>&1; echo $?)" -eq 0 ]; then
  # and has no label argocd-generic-k8s/installed, then it's a custom install and we should not overwrite it
  if [ "$(kubectl get namespace argocd -o jsonpath='{.metadata.labels.argocd-generic-k8s/installed}')" != "true" ]; then
    echo "Error: namespace argocd already exists and is not a argocd-generic-k8s install, aborting..."
    exit 1
  fi
fi 

AUTOREMOVE_ARGO_APP=0
ARGO_APP_PATH="apps/argocd.yaml"

function cleanup() {
  [ "${AUTOREMOVE_ARGO_APP}" -eq 1 ] && rm -f "${ARGO_APP_PATH}"
}

# Download the argocd.yaml file if it doesn't exist
[ -e "${ARGO_APP_PATH}" ] || {
  ARGO_APP_PATH=$(mktemp)
  AUTOREMOVE_ARGO_APP=1
  curl -o "${ARGO_APP_PATH}" https://raw.githubusercontent.com/AlexisDucastel/argocd-generic-k8s/refs/heads/main/apps/argocd.yaml
}

ARGOVERSION=$(grep "targetRevision:" "${ARGO_APP_PATH}" | sed 's/.*targetRevision: //' | tr -d '"')

[ "${ARGOVERSION}" == "" ] && {
  echo "Error: ARGOVERSION not found in ${ARGO_APP_PATH}"
  exit 1
}

# Install Argo CD
grep -A10000 "valuesObject:" "${ARGO_APP_PATH}" \
  | grep -v "valuesObject:" \
  | sed 's/^        //' \
  | helm upgrade --install argocd \
    --namespace argocd --create-namespace \
    --repo https://argoproj.github.io/argo-helm argo-cd --version "${ARGOVERSION}" \
    -f -

# Label the namespace as installed
kubectl label namespace argocd argocd-generic-k8s/installed=true

kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: 0000-app-of-the-apps
  namespace: argocd
spec:
  project: default
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ApplyOutOfSyncOnly=true
      - ServerSideApply=true
  sources:
  - repoURL: https://github.com/AlexisDucastel/argocd-generic-k8s.git
    path: apps
    targetRevision: main
    directory:
      jsonnet: {}
      recurse: true
EOF

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: local
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: local
  server: https://kubernetes.default.svc
  # Empty credentials ⇒ Argo CD talks to the local API using its Pod SA
  # (keep TLS verification on; Argo CD already has the cluster CA mounted)
  config: |
    {
      "tlsClientConfig": { "insecure": false }
    }
EOF

# Cleanup
cleanup