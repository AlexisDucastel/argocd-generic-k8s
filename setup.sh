#!/bin/bash

TARGET_FILE=${1:-"argocd-generic-k8s"}

# Download the cli.sh file
curl -L -o ${TARGET_FILE} https://raw.githubusercontent.com/AlexisDucastel/argocd-generic-k8s/refs/heads/main/cli.sh

# Make the file executable
chmod +x ${TARGET_FILE}

# Print helper
echo "argocd-generic-k8s cli downloaded in ${TARGET_FILE}"
