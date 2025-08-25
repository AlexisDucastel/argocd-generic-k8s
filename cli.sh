#!/bin/bash

# Check if binaries are present
for binary in helm kubectl grep sed mktemp curl tr; do
  [ -x "$(command -v "${binary}")" ] || {
    echo "Error: ${binary} not found"
    exit 1
  }
done


function init {
  # If namespace argocd already exists 
  if [ "$(kubectl get namespace argocd >/dev/null 2>&1; echo $?)" -eq 0 ]; then
    # and has no label argocd-generic-k8s/installed, then it's a custom install and we should not overwrite it
    if [ "$(kubectl get namespace argocd -o jsonpath='{.metadata.labels.argocd-generic-k8s/installed}')" != "true" ]; then
      echo "Error: namespace argocd already exists and is not a argocd-generic-k8s install, aborting..."
      exit 1
    fi
  fi
  
  # We install or upgrade argocd
  local AUTOREMOVE_ARGO_APP=0
  local ARGO_APP_PATH="apps/argocd.yaml"

  # Download the argocd.yaml file if it doesn't exist
  [ -e "${ARGO_APP_PATH}" ] && echo "Using ${ARGO_APP_PATH} ..." || {
    ARGO_APP_PATH=$(mktemp)
    echo "Downloading argocd yaml in ${ARGO_APP_PATH} ..."
    AUTOREMOVE_ARGO_APP=1
    curl -o "${ARGO_APP_PATH}" https://raw.githubusercontent.com/AlexisDucastel/argocd-generic-k8s/refs/heads/main/apps/argocd.yaml
  }

  local ARGOVERSION=$(grep "targetRevision:" "${ARGO_APP_PATH}" | sed 's/.*targetRevision: //' | tr -d '"')

  [ "${ARGOVERSION}" == "" ] && {
    echo "Error: ARGOVERSION not found in ${ARGO_APP_PATH}"
    [ "${AUTOREMOVE_ARGO_APP}" -eq 1 ] && rm -f "${ARGO_APP_PATH}"
    exit 1
  }

  echo "Install or upgrade Argo CD ..."
  # Install Argo CD
  grep -A10000 "valuesObject:" "${ARGO_APP_PATH}" \
    | grep -v "valuesObject:" \
    | sed 's/^        //' \
    | helm upgrade --install argocd \
      --namespace argocd --create-namespace \
      --repo https://argoproj.github.io/argo-helm argo-cd --version "${ARGOVERSION}" \
      -f -

  # Label the namespace as installed
  echo "Labeling namespace argocd as installed from argocd-generic-k8s ..."
  kubectl label namespace argocd argocd-generic-k8s/installed=true

  echo "Installing app-of-the-apps ..."
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

  echo "Adding local cluster secret ..."
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

  [ "${AUTOREMOVE_ARGO_APP}" -eq 1 ] && echo "Removing temporary file ${ARGO_APP_PATH} ..." && rm -f "${ARGO_APP_PATH}"

  echo "Setup done."
}

function help {
    echo "Usage: $0 <command>"
    echo "Commands:"
    echo "  help - Show this help message"
    echo "  init - Install or upgrade argocd-generic-k8s stack"
    echo "  list - List all available features"
    echo "  ps - List all installed features"
    echo "  add <alias> - Add a feature"
    echo "  remove <alias> - Remove a feature"
    echo "  get <alias> <var> - Get a feature variable"
    echo "  set <alias> <var> <value> - Set a feature variable"
    echo "  unset <alias> <var> - Unset a feature variable"
}


function ps {
  kubectl -n argocd get secret local \
    -o go-template='{{range $k,$v := .metadata.labels}}{{printf "%s %s\n" $k $v}}{{end}}' \
    | grep -E "^(feat|app)/" | while read label flavor; do
      echo "Feature $label=$flavor:"
      local feature=$(echo $label | cut -d'/' -f2)
      kubectl get applications.argoproj.io -n argocd -l feat=$feature,flavor=$flavor \
        -o go-template='{{range $k,$v := .items}}{{printf "%s %s %s\n" $v.metadata.name $v.status.sync.status $v.status.health.status }}{{end}}' \
        | while read name sync health; do
          echo "  [$health] App $name is $sync"
        done
    done
}
function list {
  local filter=""
  [ ! -z "$1" ] && filter="-l feat=$1"
  kubectl get appset -n argocd $filter \
    -o go-template='{{range $k,$v := .items}}{{printf "feat/%s=%s\n => %s\n" $v.metadata.labels.feat $v.metadata.labels.flavor (or $v.metadata.annotations.description "")}}{{end}}'
}

function add {
  kubectl -n argocd label secret local "$1"
}

function remove {
  local feature=$(echo $1 | cut -d'=' -f1)
  kubectl -n argocd label secret local "$feature"-
}

function get {
  local filter="feat/"
  [ ! -z "$1" ] && filter="$(echo $1 | cut -d'=' -f1).$2"
  kubectl -n argocd get secret local \
    -o go-template='{{range $k,$v := .metadata.annotations}}{{printf "%s=%s\n" $k $v}}{{end}}' \
    | grep -E "^${filter}"
}

function set {
  local feature="$(echo $1 | cut -d'=' -f1)"
  local var="$2"
  local value="$3"
  kubectl -n argocd annotate secret local "${feature}.${var}"="$value"
}
function unset {  
  local feature="$(echo $1 | cut -d'=' -f1)"
  local var="$2"
  kubectl -n argocd annotate secret local "${feature}.${var}"-
}

if [ $# -eq 0 ]; then
    help
    exit 1
fi

case $1 in
    help)
        help
        ;;
    init|i)
        init
        ;;
    list|l)
        list $2
        ;;
    ps|p)
        ps
        ;;
    add|a)
        add $2
        ;;
    remove|rm)
        remove $2
        ;;
    get|g)
        shift
        get $@
        ;;
    set|s)
        shift
        set $@
        ;;
    unset|u)
        shift
        unset $@
        ;;
    *)
        help
        ;;
esac