



```bash

# Get ArgoCD initial password :
k get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Start tunnel to ArgoCD
kubectl port-forward -n argocd svc/argocd-server  8080:80

open https://localhost:8080
```