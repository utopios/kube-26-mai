#!/usr/bin/env bash
# Etape 11 - Scaling, rolling update et rollback
# Lancer chaque section a la main, pas en script complet.

set -euo pipefail
NS=voting

# ============================================================
# 11.1 - Scaling du frontend vote-ui de 2 a 5 replicas
# ============================================================
kubectl scale deployment/vote-ui -n $NS --replicas=5
kubectl rollout status deployment/vote-ui -n $NS
kubectl get pods -n $NS -l app=vote-ui

# Retour a 2 replicas
kubectl scale deployment/vote-ui -n $NS --replicas=2

# ============================================================
# 11.2 - Rolling update du backend vote (changement de ConfigMap)
# ============================================================

# (a) Changer les valeurs du ConfigMap (Cats/Dogs -> Chiens/Chats)
kubectl patch configmap voting-config -n $NS --type merge -p '
data:
  OPTION_A: "Chiens"
  OPTION_B: "Chats"
'

# (b) IMPORTANT : un changement de ConfigMap ne redemarre PAS les pods automatiquement.
#     Solution : forcer un rollout avec une annotation qui change.
kubectl annotate deployment/vote -n $NS \
  kubernetes.io/change-cause="test rolling update Chiens/Chats" \
  --overwrite

# Forcer un nouveau rollout pour que les pods relisent le ConfigMap
kubectl rollout restart deployment/vote -n $NS

# Suivre le rolling update : maxUnavailable=0 => aucun pod ne descend tant que le nouveau n'est pas Ready
kubectl rollout status deployment/vote -n $NS
kubectl rollout history deployment/vote -n $NS

# ============================================================
# 11.3 - Rollback
# ============================================================

# Remettre les anciennes valeurs dans le ConfigMap
kubectl patch configmap voting-config -n $NS --type merge -p '
data:
  OPTION_A: "Cats"
  OPTION_B: "Dogs"
'

# Rollback du Deployment vote a la revision precedente
kubectl rollout undo deployment/vote -n $NS
kubectl rollout status deployment/vote -n $NS
kubectl rollout history deployment/vote -n $NS
