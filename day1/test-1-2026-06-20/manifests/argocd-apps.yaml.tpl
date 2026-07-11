apiVersion: elbv2.k8s.aws/v1beta1
kind: TargetGroupBinding
metadata:
  name: argocd-server-tgb
  namespace: argocd
spec:
  serviceRef:
    name: argocd-server
    port: 80
  targetGroupARN: ${TG_ARGO}
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: red-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}.git
    targetRevision: gitops-red
    path: manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: skills
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: green-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}.git
    targetRevision: gitops-green
    path: manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: skills
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
