

## One-line install

```bash
curl -L https://raw.githubusercontent.com/AlexisDucastel/argocd-generic-k8s/refs/heads/main/setup.sh | bash
```

## Enable an app with cluster flag 

```bash
kubectl label -n argocd secretlocal app/<application>=true
```

Catalog of Apps to enable via label:
- cert-manager

Mandatory apps: 
- argocd-self-managed

## Troubleshooting ArgoCD

```bash
# Get ArgoCD initial password :
k get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Start tunnel to ArgoCD
kubectl port-forward -n argocd svc/argocd-server  8080:80

open https://localhost:8080
```