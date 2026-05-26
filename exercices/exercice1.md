# Exercice 01 — Architecture du cluster (20 min)

**Objectifs** : comprendre les composants et savoir les inspecter.

1. Listez tous les nœuds et identifiez le control-plane et les workers.
2. Listez les pods du namespace `kube-system` et identifiez :
   - L'API Server, le scheduler, le controller-manager
   - Le CNI utilisé
   - CoreDNS
3. Quel container runtime est utilisé sur les nœuds ? Quelle version ?
4. Quelles StorageClass sont disponibles ? Laquelle est par défaut (annotation `storageclass.kubernetes.io/is-default-class`) ?
5. Quels CSI drivers sont enregistrés ?
6. Trouvez la version de Kubernetes du client et du serveur.