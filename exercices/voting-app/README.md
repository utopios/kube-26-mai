# Correction — TP fil rouge : application de vote

Correction complète du TP [TP.md](../TP.md). Tous les manifests ont été testés sur un cluster Kind 4 nœuds (1 control-plane + 3 workers).

## Structure du dossier

```
voting-app/
├── 01-namespace/        # Namespace + ResourceQuota + LimitRange
├── 02-config/           # ConfigMap + Secret
├── 03-database/         # Postgres : Service + StatefulSet + PVC
├── 04-redis/            # Redis : Service + Deployment
├── 05-worker/           # Worker : Deployment (consomme Redis, ecrit Postgres)
├── 06-vote/             # Vote backend (Python:5000) + frontend (Nginx:80, NodePort 31000)
├── 07-result/           # Result backend (Node:5000) + frontend (Nginx:80, NodePort 31001)
├── 10-daemonset/        # DaemonSet metrics-agent (workers seulement)
├── 11-jobs/             # Job vote-report (3 completions / 2 parallel) + CronJob vote-stats
├── 11-scaling-update/   # Script d'execution pour scaling, rolling update, rollback (etape 11)
└── 12-rbac/             # ServiceAccount worker + Role/RoleBinding alice + ClusterRole/Binding ops-team
```

## Deploiement complet

```bash
cd voting-app

# Dans l'ordre des etapes
kubectl apply -f 01-namespace/
kubectl apply -f 02-config/
kubectl apply -f 03-database/
kubectl wait --for=condition=ready pod -n voting -l app=db --timeout=180s

kubectl apply -f 04-redis/
kubectl wait --for=condition=ready pod -n voting -l app=redis --timeout=120s

kubectl apply -f 12-rbac/                 # SA worker AVANT le worker
kubectl apply -f 05-worker/
kubectl apply -f 06-vote/
kubectl apply -f 07-result/
kubectl apply -f 10-daemonset/
kubectl apply -f 11-jobs/

# Verification globale
kubectl get all -n voting
```

## Tests end-to-end

### Acces HTTP via port-forward

```bash
kubectl port-forward -n voting svc/vote-ui   31000:80 &
kubectl port-forward -n voting svc/result-ui 31001:80 &
```

Ouvrir dans le navigateur :
- http://localhost:31000  — voter
- http://localhost:31001  — voir les resultats en temps reel (socket.io)

### Voter en CLI

L'API attend du **JSON** (pas du form-urlencoded) :

```bash
for v in a a b a b a a a b a; do
  curl -s -X POST -H "Content-Type: application/json" \
    --cookie "voter_id=user-$RANDOM" \
    -d "{\"vote\":\"$v\"}" \
    -o /dev/null -w "vote=$v HTTP %{http_code}\n" \
    http://localhost:31000/api/
done
```

### Verifier en base

```bash
kubectl exec -n voting db-0 -- psql -U postgres -c \
  "SELECT vote, COUNT(*) FROM votes GROUP BY vote;"
```

Resultat attendu (apres 10 votes) :
```
 vote | count
------+-------
 a    |     7
 b    |     3
```

---

## Notes importantes sur les images du TP

J'ai inspecte les vraies images `mohamed1780/*` avant d'ecrire la correction. Plusieurs choses ne collent pas avec l'enonce du TP :

### 1. Ports d'ecoute reels

| Service | Port reel (binaire) | Tableau TP | Remarque |
|---|---|---|---|
| `vote`      | **5000** (gunicorn) | 8080 ❌ | Le tableau du TP est faux, mais les probes plus bas mentionnent bien 5000 |
| `vote-ui`   | **80** (nginx) | 8080 ❌ | Le tableau du TP est faux. Nginx ecoute sur 80. |
| `result`    | **5000** (node + nodemon) | 8080 ❌ | idem |
| `result-ui` | **80** (nginx) | 8080 ❌ | idem |

Les valeurs choisies dans cette correction reflettent la **realite des images**, sinon rien ne marche.

### 2. Connexion DB hardcodee dans `mohamed1780/result`

L'image `result` **ignore les variables d'environnement Postgres** et se connecte en dur a :
- host : `db`
- user : `postgres`
- password : `postgres`
- database : `postgres`

C'est visible dans les logs au demarrage :
```
connecting to db with connection string postgres://postgres:postgres@db/postgres
```

Le TP demande `POSTGRES_PASSWORD: v0t1ng-p4ss` et `POSTGRES_DB: votes`. Pour que **l'application fonctionne reellement** :
- Le Secret utilise password `postgres` (pas `v0t1ng-p4ss`).
- Le ConfigMap utilise database `postgres` (pas `votes`).

Le worker, lui, lit correctement les variables d'environnement, donc il s'aligne sur les memes valeurs.

### 3. URLs hardcodees dans les UIs

Les images `vote-ui` et `result-ui` sont des nginx avec une `nginx.conf` qui proxifie en dur :
- `vote-ui` : `/api` -> `http://vote:5000/`
- `result-ui` : `/socket.io` -> `http://result:5000/socket.io`

Les variables d'environnement `VOTE_API_URL` et `RESULT_API_URL` demandees par le TP **ne sont pas utilisees** par les images. Je les conserve quand meme dans les manifests pour respecter l'enonce, mais elles sont inertes.

### 4. API de vote attend du JSON

Le backend `vote` retourne `HTTP 415 Unsupported Media Type` si on envoie du form-urlencoded.
Il faut envoyer du JSON :
```bash
curl -X POST -H "Content-Type: application/json" -d '{"vote":"a"}' http://vote:5000/
```

---

## Reponses aux questions du TP

### Etape 1 — Pod sans `resources:` dans `voting`

Le `LimitRange` `voting-limits` applique automatiquement les valeurs par defaut :
- requests : cpu=100m, memory=128Mi
- limits : cpu=500m, memory=512Mi

Demonstration :
```bash
kubectl run test --image=nginx --restart=Never -n voting
kubectl get pod test -n voting -o jsonpath='{.spec.containers[0].resources}'
# {"limits":{"cpu":"500m","memory":"512Mi"},"requests":{"cpu":"100m","memory":"128Mi"}}
```

### Etape 3 — Suppression manuelle du pod Postgres

`kubectl delete pod db-0 -n voting` : le StatefulSet recree immediatement le pod (~10s) avec le **meme nom** `db-0` et **le meme PVC** `db-data-db-0`. Les donnees sont preservees grace au volume persistant.

### Etape 4 — Pourquoi Redis en Deployment et Postgres en StatefulSet ?

- **Postgres** : etat persistant, identite stable necessaire (un pod = un PVC), ordre de demarrage important (replication). -> StatefulSet
- **Redis** : ici utilise comme **file de messages volatile** (les votes y sont temporaires, le worker les consomme aussitot). Une perte du cache = perte des votes en transit, jugee acceptable. Pas besoin d'identite stable. -> Deployment.

En production avec persistance Redis, on utiliserait un StatefulSet.

### Etape 7 — Pourquoi `vote` en ClusterIP et pas NodePort ?

Le backend `vote` est un service **interne**, consomme uniquement par `vote-ui`. L'exposer en NodePort :
- ouvre une porte d'entree publique sur l'API non documentee,
- contourne la couche UI (auth, rate-limit, validation cote frontend),
- expose la version technique aux clients (gunicorn header).

Reflexe a garder : **un seul point d'entree expose par flow utilisateur**, le reste reste interne au cluster.

### Etape 10 — DNS Kubernetes

- **Forme complete** : `<service>.<namespace>.svc.<cluster-domain>` ex. `redis.voting.svc.cluster.local`
- **Short name** : marche dans le meme namespace grace aux `search` du `/etc/resolv.conf` du pod :
  ```
  search voting.svc.cluster.local svc.cluster.local cluster.local
  options ndots:5
  ```
- **Depuis un autre namespace** : `redis` echoue (NXDOMAIN), il faut le FQDN ou au moins `redis.voting`.
- `vote-ui` accede a `http://vote:8080` (selon le TP) : c'est le **service Kubernetes** `vote` du meme namespace, resolu par CoreDNS. **Mais en realite** l'image nginx hardcode `http://vote:5000` (port reel du backend).

### Etape 11 — ConfigMap modifie : les pods le voient-ils ?

**Non.** Les valeurs du ConfigMap sont injectees comme **variables d'environnement au demarrage du pod**. Une fois le pod cree, les env vars sont gelees. Pour faire prendre en compte le changement, il faut :
- soit recreer les pods : `kubectl rollout restart deployment/vote`
- soit monter le ConfigMap en volume (les fichiers se mettent a jour mais l'app doit reloader)

Avec `maxUnavailable: 0`, le rolling update garantit **zero downtime** : on ne descend jamais en dessous des 3 replicas Ready, on ajoute un nouveau pod (maxSurge 1), il devient Ready, puis on enleve un ancien.

### Etape 12 — Pourquoi le DaemonSet evite le control-plane ?

Le nœud control-plane porte un **taint** :
```
node-role.kubernetes.io/control-plane:NoSchedule
```
Notre DaemonSet ne declare **aucune `tolerations`** pour ce taint, donc le scheduler refuse d'y placer le pod. Si on voulait l'inclure, il faudrait ajouter :
```yaml
tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
```

Resultat sur 4 nodes (1 cp + 3 workers) : **3 pods crees, un par worker**.

### Etape 14 — Token monte sur le worker ?

Le SA `voting-worker-sa` a `automountServiceAccountToken: false`. Le pod worker n'a donc **aucun volume `kube-api-access-*`**, et `/var/run/secrets/kubernetes.io/serviceaccount/` n'existe pas dans le container. C'est une bonne pratique de **defense en profondeur** : si l'app est compromise, l'attaquant n'a aucun token pour parler a l'API K8s.

On mettrait `true` si l'app avait besoin d'appeler l'API : par exemple un Operator, un controller custom, ou une app qui watch des ressources K8s.

### Etape 14 — Permissions de `dev-alice`

`dev-alice` est dans le groupe `dev-team`, lie a un Role *namespaced* sur `voting`. Elle peut :
- ✅ list/get/watch pods, services, configmaps, endpoints, deployments dans `voting`
- ❌ delete (verb non autorise)
- ❌ secrets (resource non autorisee)
- ❌ tout autre namespace (Role limite a voting)

Pour qu'elle puisse list les pods dans `default`, il faudrait soit :
- Un RoleBinding equivalent dans `default`,
- Soit un ClusterRoleBinding sur un ClusterRole equivalent (acces a tous les namespaces).

### Etape 13 — Sequence d'execution du Job

`completions: 3, parallelism: 2` :

```
t=0   : pod-1 + pod-2 demarrent
t~5s  : pod-1 termine OK -> pod-3 demarre
t~7s  : pod-2 termine OK
t~12s : pod-3 termine OK -> Job complete (3/3)
```

Le controlleur veille a avoir **au plus 2 pods en parallele** et `completions` *succes* au total. `backoffLimit: 2` autorise 2 echecs avant marquage `Failed`.

---

## Commandes de validation par etape

### Etape 1
```bash
kubectl get namespace voting --show-labels
kubectl describe resourcequota voting-quota -n voting
kubectl describe limitrange voting-limits -n voting
```

### Etape 2
```bash
kubectl get configmap voting-config -n voting -o jsonpath='{.data}' | jq
kubectl get secret voting-secrets -n voting -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d
```

### Etape 3
```bash
kubectl get sts,pvc,pod -n voting -l app=db
kubectl exec -n voting db-0 -- psql -U postgres -c "\l"
```

### Etape 4
```bash
kubectl exec -n voting deploy/redis -- redis-cli ping     # PONG
```

### Etape 5
```bash
kubectl logs -n voting deploy/worker --tail=5
# -> Connected to Redis !
# -> connected to Postgres !
```

### Etape 6-9
```bash
kubectl get pods -n voting -l app=vote
kubectl get pods -n voting -l app=vote-ui
kubectl get pods -n voting -l app=result
kubectl get pods -n voting -l app=result-ui
```

### Etape 10 (DNS depuis un pod debug)
```bash
kubectl run debug --image=busybox:1.36 -n voting --rm -it -- sh
# Dans le pod :
nslookup redis.voting.svc.cluster.local
nc -zv redis 6379
nc -zv db 5432
```

### Etape 11 — Scaling + Rolling update + Rollback
Voir le script complet [11-scaling-update/commands.sh](11-scaling-update/commands.sh).

### Etape 12
```bash
kubectl get ds metrics-agent -n voting       # 3 desired / 3 ready
kubectl logs -n voting -l app=metrics-agent --tail=2
```

### Etape 13
```bash
kubectl get jobs,cronjob -n voting
kubectl logs -n voting -l job-name=vote-report
```

### Etape 14
```bash
# Alice : read-only sur voting
kubectl auth can-i list pods   -n voting --as dev-alice    # yes
kubectl auth can-i delete pods -n voting --as dev-alice    # no
kubectl auth can-i list secrets -n voting --as dev-alice   # no
kubectl auth can-i list pods   -n default --as dev-alice   # no

# Ops-team : deploiement sur tous namespaces
kubectl auth can-i update deployments -n voting --as=ops-bob --as-group=ops-team   # yes
kubectl auth can-i create deployments -n default --as=ops-bob --as-group=ops-team  # yes
kubectl auth can-i delete namespaces --as=ops-bob --as-group=ops-team              # no
```

---

## Cleanup

```bash
kubectl delete namespace voting
kubectl delete clusterrole voting-deployer
kubectl delete clusterrolebinding ops-team-binding
```
