#!/usr/bin/env bash
###############################################################################
# create-cluster.sh — Créer un cluster Kind multi-nœuds pour la formation
# © Utopios — Formation Kubernetes
###############################################################################
set -euo pipefail

CLUSTER_NAME="${1:-formation-k8s}"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log()   { echo -e "${GREEN}[OK]${NC} $1"; }

# Supprimer le cluster s'il existe déjà
if kind get clusters 2>/dev/null | grep -q "$CLUSTER_NAME"; then
    info "Suppression du cluster existant '$CLUSTER_NAME'..."
    kind delete cluster --name "$CLUSTER_NAME"
fi

# Configuration du cluster Kind
cat > /tmp/kind-config.yaml << 'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: formation-k8s
networking:
  # Activer les NetworkPolicies (nécessite Calico)
  disableDefaultCNI: false
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/16"
nodes:
  # Control plane
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      # Ingress HTTP
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      # Ingress HTTPS
      - containerPort: 443
        hostPort: 443
        protocol: TCP
      # NodePort range
      - containerPort: 30000
        hostPort: 30000
        protocol: TCP
      - containerPort: 30001
        hostPort: 30001
        protocol: TCP
      - containerPort: 30080
        hostPort: 30080
        protocol: TCP
      - containerPort: 30443
        hostPort: 30443
        protocol: TCP
  # Worker nodes
  - role: worker
    labels:
      node-type: worker
      zone: zone-a
  - role: worker
    labels:
      node-type: worker
      zone: zone-b
  - role: worker
    labels:
      node-type: worker
      zone: zone-c
EOF

info "Création du cluster Kind '$CLUSTER_NAME' (1 control-plane + 3 workers)..."
kind create cluster --name "$CLUSTER_NAME" --config /tmp/kind-config.yaml

# Vérifier
kubectl cluster-info --context "kind-$CLUSTER_NAME"
kubectl get nodes -o wide

# Installer NGINX Ingress Controller
info "Installation de NGINX Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

info "Attente du démarrage de l'Ingress Controller..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s 2>/dev/null || echo "En cours de démarrage..."

# Installer le Metrics Server (pour HPA)
info "Installation du Metrics Server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Patch pour Kind (certificats auto-signés)
kubectl patch deployment metrics-server -n kube-system \
  --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' 2>/dev/null || true

# Créer les namespaces de formation
info "Création des namespaces..."
kubectl create namespace dev 2>/dev/null || true
kubectl create namespace staging 2>/dev/null || true
kubectl create namespace production 2>/dev/null || true
kubectl create namespace monitoring 2>/dev/null || true
kubectl create namespace argocd 2>/dev/null || true

echo ""
log "Cluster '$CLUSTER_NAME' prêt !"
echo ""
echo "Nœuds :"
kubectl get nodes
echo ""
echo "Namespaces :"
kubectl get namespaces
echo ""
echo "Commandes utiles :"
echo "  kubectl get nodes                    # Liste des nœuds"
echo "  kubectl get pods -A                  # Tous les pods"
echo "  kind delete cluster --name $CLUSTER_NAME  # Supprimer le cluster"
