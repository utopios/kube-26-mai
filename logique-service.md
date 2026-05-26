# Application A dans le namespace A
    - Deployment 3 pods avec label app=a
    - Service serviceA clusterIP qui ecoute le port 80 et redirige vers le port 80 du pod.
# Application B dans le namespace B
    - Deployment 3 pods avec label app=b
    - Envoie une requete vers le deployment app=a
        curl http://serviceA.B.cluster.svc.local

# 3 types de service
- ClusterIP
- NodePort
    - Node A: 15.200.100.4
    - Node B: 15.200.100.5
    - Node C: 15.200.100.6
    - Deployment app avec service nodeport sna, nodePort:30000-32767 port:80 targetPort: 80 
- LoadBalancer
