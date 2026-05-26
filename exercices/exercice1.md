# Exercice 01 — Architecture du cluster (20 min)

**Objectifs** : comprendre les composants et savoir les inspecter.

1. Listez tous les nœuds et identifiez le control-plane et les workers.
    kubectl get nodes
    kubectl get nodes -o wide
2. Listez les pods du namespace `kube-system` et identifiez :
    kubectl get pods -n kube-system
   - L'API Server, le scheduler, le controller-manager
   - Le CNI utilisé
   - CoreDNS
3. Quel container runtime est utilisé sur les nœuds ? Quelle version ?
kubectl get nodes -o wide
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.nodeInfo.containerRuntimeVersion}{"\n"}{end}'
4. Quelles StorageClass sont disponibles ? Laquelle est par défaut (annotation `storageclass.kubernetes.io/is-default-class`) ?
kubectl get sc
5. Quels CSI drivers sont enregistrés ?
kubectl get csidriver avec kind aucun
6. Trouvez la version de Kubernetes du client et du serveur.