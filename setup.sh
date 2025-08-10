#!/bin/bash

# Check if binaries are present
for binary in helm kubectl grep sed mktemp curl tr; do
  [ -x "$(command -v "${binary}")" ] || {
    echo "Error: ${binary} not found"
    exit 1
  }
done

AUTOREMOVE_ARGO_APP=0
AUTOREMOVE_APP_OF_THE_APPS=0
ARGO_APP_PATH="apps/argocd.yaml"

function cleanup() {
  [ "${AUTOREMOVE_ARGO_APP}" -eq 1 ] && rm -f "${ARGO_APP_PATH}"
  [ "${AUTOREMOVE_APP_OF_THE_APPS}" -eq 1 ] && rm -f "${APP_OF_THE_APPS_PATH}"
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

APP_OF_THE_APPS_PATH="app-of-the-apps.yaml"

[ -e "${APP_OF_THE_APPS_PATH}" ] || {
  APP_OF_THE_APPS_PATH=$(mktemp)
  AUTOREMOVE_APP_OF_THE_APPS=1
  curl -o "${APP_OF_THE_APPS_PATH}" https://raw.githubusercontent.com/AlexisDucastel/argocd-generic-k8s/refs/heads/main/app-of-the-apps.yaml
}

kubectl apply -f "${APP_OF_THE_APPS_PATH}"

# Cleanup
cleanup