# Exercice 02 — Pods, Labels, Services (30 min)

1. Créez un namespace `exercice-02`.

2. Déployez 3 Pods dans ce namespace :
   - `frontend` : image `nginx:1.25`, labels `app=frontend, tier=web`
   - `backend` : image `hashicorp/http-echo:0.2.3` avec arg `-text=API OK`, labels `app=backend, tier=api`
   - `database` : image `redis:7`, labels `app=database, tier=data`

3. Ajoutez des `readinessProbe` et `livenessProbe` HTTP au pod `frontend`.

4. Testez les sélecteurs :
   ```bash
   kubectl get pods -n exercice-02 -l tier=web
   kubectl get pods -n exercice-02 -l "tier in (api, data)"
   kubectl get pods -n exercice-02 -l "app!=database"
   ```

5. Créez un Service `backend-svc` de type ClusterIP qui pointe vers le pod `backend`.

6. Vérifiez les `EndpointSlices` du Service. (ne pas faire)

7. Depuis le pod `frontend`, testez la connectivité vers `backend-svc` :
   ```bash
   kubectl exec -n exercice-02 frontend -- curl backend-svc