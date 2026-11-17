# Compte-Rendu Complet – Travaux Pratiques Kubernetes (TP 4.1 à TP 4.13)

> **Module 4 – Orchestration de conteneurs avec Kubernetes**
> Ce document regroupe l'ensemble des réponses aux questions, les tableaux comparatifs complétés, les diagnostics de pannes et les solutions des défis pour les **TPs 4.1 à 4.13**.
> Tous les manifests YAML et Kustomize sont prêts dans [`solutions/`](solutions/) et exécutables automatiquement via [`run_all_tp_kubernetes.sh`](run_all_tp_kubernetes.sh).

---

## TP 4.1 : Installation du cluster Minikube et exploration

### 1. Rôle des composants de `kube-system` (`kubectl get pods -n kube-system`)
| Pod dans `kube-system` | Plan | Rôle dans l'architecture Kubernetes |
| :--- | :--- | :--- |
| `kube-apiserver-minikube` | Control Plane | Point d'entrée unique (API REST) du cluster : valide les requêtes `kubectl` et authentifie les acteurs ; seul composant autorisé à parler à `etcd`. |
| `etcd-minikube` | Control Plane | Base de données clé-valeur distribuée qui stocke tout l'état du cluster (configurations, secrets, état désiré et réel). |
| `kube-scheduler-minikube` | Control Plane | Surveille les Pods nouvellement créés (`Pending`) et choisit le nœud optimal où les placer selon leurs `requests` CPU/RAM et contraintes. |
| `kube-controller-manager-minikube` | Control Plane | Exécute les boucles de contrôle (Deployment, ReplicaSet, Node, Job) qui rapprochent en permanence l'état réel de l'état désiré. |
| `kube-proxy-...` | Data Plane (Worker) | Présent sur chaque nœud (DaemonSet) : programme les règles réseau (`iptables`/`ipvs`) pour router le trafic des `Services` vers les IP des Pods. |
| `coredns-...` | Addon Cluster | Serveur DNS interne du cluster : résout les noms de Services (`<svc>.<ns>.svc.cluster.local`). |

### 2. Runtime de conteneurs et IP du nœud (`kubectl get nodes -o wide`)
* **Adresse IP interne du nœud Minikube :** `192.168.49.2` (réseau Docker `minikube`).
* **Container Runtime :** `containerd://2.3.4` (avec le driver Docker de Minikube et Kubernetes `v1.37.0`).

---

## TP 4.2 : Le Pod – la plus petite unité de Kubernetes

### 1. Réponses aux questions
1. **Quels composants apparaissent dans la colonne `From` des événements de `kubectl describe pod my-pod` ?**
   * `default-scheduler` : choisit le nœud `minikube` (`Scheduled`).
   * `kubelet` : agent du nœud qui tire l'image (`Pulling` / `Pulled`), crée le conteneur (`Created`) et le démarre (`Started`).
2. **Dans `kubectl get pod my-pod -o yaml`, quels champs ont été ajoutés par Kubernetes ?**
   * Dans `metadata` : `uid`, `resourceVersion`, `creationTimestamp`, `managedFields`.
   * Dans `spec` : `nodeName`, `serviceAccountName`, `tolerations`, `dnsPolicy`, `restartPolicy: Always`.
   * Tout le bloc `status` (`phase: Running`, `podIP`, `hostIP`, `conditions`, `containerStatuses`), renseigné par l'**API Server** et le **kubelet**.
3. **Pourquoi un Pod seul ne suffit-il pas en production ?**
   * Le **kubelet** redémarre un conteneur qui plante à l'intérieur d'un Pod existant (`kill 1` → `RESTARTS = 1`), mais si le Pod est supprimé (`kubectl delete pod`) ou si son nœud tombe en panne, **personne ne le recrée**. Il faut un contrôleur (`Deployment` / `ReplicaSet`).
4. **Comment vérifier que les deux conteneurs du Pod `web-sidecar` partagent la même adresse IP ?**
   * Tous les conteneurs d'un même Pod partagent le même *network namespace* (`localhost` et même IP). Depuis le conteneur `generateur` (qui ne fait pas tourner Nginx), la commande `kubectl exec web-sidecar -c generateur -- wget -qO- http://localhost:80` interroge directement le serveur Nginx du conteneur voisin `web` sur `127.0.0.1:80`.

### 2. Livrables réalisés
* Manifests (`my-pod`, `web-sidecar` et Défi `redis`) : [`solutions/tp4.2/pods.yaml`](solutions/tp4.2/pods.yaml)

---

## TP 4.3 : Deployment, ReplicaSet et Service

### 1. Réponses aux questions
1. **À quoi correspond le hash dans `my-deployment-<hash>-<suffixe>` et quel objet intermédiaire a été créé ?**
   * Le `Deployment` ne gère pas directement les Pods : il crée un **ReplicaSet** (`my-deployment-<pod-template-hash>`). Le `<hash>` est l'empreinte du `spec.template` du Pod (ce qui permet au Deployment de créer un nouveau ReplicaSet à chaque changement de version et de conserver les anciens pour le rollback).
2. **Qui recrée immédiatement les Pods lorsqu'on exécute `kubectl delete pod -l app=myapp` ?**
   * C'est le contrôleur **ReplicaSet** (au sein du `kube-controller-manager`) : il observe que le nombre de Pods actifs portant le label `app=myapp` est tombé à 0 alors que `replicas: 3` est demandé, et demande aussitôt à l'API Server d'en créer 3 nouveaux.
3. **Pourquoi la méthode déclarative (`kubectl apply -f`) est-elle préférable à `kubectl scale` ?**
   * Parce que le fichier YAML dans Git reste l'unique source de vérité (*Single Source of Truth*). Si un opérateur fait un `kubectl scale --replicas=5` à la main sans modifier le YAML, le prochain déploiement (`kubectl apply -f deployment.yaml` contenant `replicas: 3`) écrasera son réglage et ramènera l'application à 3 réplicas.

### 2. Tableau comparatif des types d'exposition

| Type | Accessible depuis | Usage typique |
| :--- | :--- | :--- |
| **`ClusterIP`** *(défaut)* | Uniquement l'**intérieur du cluster** (via IP virtuelle et DNS interne) | Bases de données (Redis, MySQL), microservices internes (backend) |
| **`NodePort`** | L'extérieur du cluster via `<IP_Noeud>:<30000-32767>` | Environnements de dev/test locaux (Minikube), démonstrations |
| **`LoadBalancer`** | L'extérieur via un répartiteur de charge provisionné par le Cloud (AWS ALB/NLB, GCP, ou `minikube tunnel`) | Exposition directe d'un service TCP/HTTP en Cloud public |
| **`Ingress`** *(objet L7)* | L'extérieur en HTTP/HTTPS (ports 80/443) par **nom de domaine** (`Host`) et **chemin** (`Path`) | Production web : un seul point d'entrée (Ingress Controller Nginx/Traefik) routant vers plusieurs Services `ClusterIP` avec terminaison TLS |

---

## TP 4.4 : Déploiement de l'application fil rouge sur Kubernetes

### 1. Réponses aux questions
1. **Pourquoi le compteur de visites « saute-t-il » d'une valeur à l'autre au TP 4.4 ?**
   * La ligne *« Stockage du compteur : memoire »* montre que `REDIS_HOST` n'est pas encore défini : chacun des 2 Pods maintient son propre compteur en RAM locale. Comme le Service répartit les requêtes entre les 2 Pods, l'utilisateur voit alternativement le compteur du Pod A et celui du Pod B. La solution (TP 4.7) consiste à brancher un service **Redis** partagé.
2. **Pourquoi les anciens Pods restent-ils en place quand on déploie l'image inexistante `:9.9.9` ?**
   * Grâce à la stratégie par défaut `RollingUpdate` : Kubernetes attend que le nouveau Pod soit `Ready` avant de terminer tous les anciens Pods, garantissant ainsi qu'une erreur de tag d'image ne coupe pas le service en production.

---

## TP 4.5 : WordPress + MySQL (Application à état)

### 1. Réponses aux questions
1. **Pourquoi `strategy: Recreate` et non `RollingUpdate` pour le Deployment MySQL ?**
   * Parce que les deux Pods MySQL (l'ancien et le nouveau pendant un `RollingUpdate`) monteraient simultanément le même volume de fichiers de base de données (`/var/lib/mysql`), ce qui corromprait les fichiers InnoDB ou échouerait sur un volume `ReadWriteOnce`. `Recreate` éteint complètement l'ancien Pod avant de démarrer le nouveau.
2. **Pourquoi le Service `mysql` est-il en `clusterIP: None` (et non `NodePort`) ?**
   * Une base de données ne doit **jamais** être exposée à l'extérieur du cluster. Seul le Pod WordPress (dans le même namespace) a besoin de la joindre via le nom DNS `mysql:3306`.
3. **Que se passe-t-il avec `kubectl delete -f .` ou `kubectl delete namespace wordpress` ?**
   * Cela supprime également l'objet `PersistentVolumeClaim` (`10-mysql-pvc.yaml`). Avec la StorageClass par défaut (`reclaimPolicy: Delete`), la suppression du PVC entraîne la **suppression définitive du PersistentVolume et des données**. En production, on isole les PVC, on utilise une politique `Retain` et on sauvegarde régulièrement la base.

---

## TP 4.6 : Jobs, CronJobs, DaemonSets et initContainers

### 1. Réponses aux questions
1. **Pourquoi lancer un Job de migration de base *avant* de mettre à jour le Deployment de l'application dans un pipeline CI/CD ?**
   * Si on déploie d'abord la nouvelle version de l'application alors que les nouvelles tables/colonnes n'existent pas encore en base, l'application va générer des erreurs 500 dès les premières requêtes. En exécutant un `Job` unique de migration (`kubectl wait --for=condition=complete job/migration`) avant le rolling update, on garantit que le schéma est prêt et qu'un seul processus exécute la migration (au lieu de N réplicas en concurrence).
2. **Deux exemples d'outils réels déployés en `DaemonSet` dans un cluster Kubernetes :**
   * **`kube-proxy`** et le plugin réseau CNI (**Calico**, **Cilium**, **Flannel**, **`kindnet`**) dans `kube-system`.
   * Les agents de supervision et de collecte de logs : **Prometheus `node-exporter`**, **Fluent Bit / Fluentd**, **Datadog Agent**, **Falco**.

---

## TP 4.7 : Namespaces, ConfigMaps et Secrets

### 1. Réponses aux questions
1. **Base64 est-il du chiffrement ? Qui peut lire un Secret Kubernetes ?**
   * **Non**, Base64 est un simple **encodage** réversible sans clé (`base64 -d`). Toute personne ou tout Pod disposant du droit RBAC `get`/`list` sur la ressource `secrets` du namespace (ainsi que quiconque a accès à un fichier YAML commité dans Git) peut lire le mot de passe en clair. C'est pourquoi on utilise **Ansible Vault**, **Sealed Secrets** ou **External Secrets Operator** dans Git.
2. **Pourquoi la modification d'une `ConfigMap` n'est-elle pas prise en compte immédiatement par les Pods ?**
   * Les variables d'environnement d'un processus Linux (`env` / `envFrom`) sont figées au **démarrage du processus** et ne peuvent pas être modifiées de l'extérieur pendant son exécution. Il faut donc redémarrer les Pods (`kubectl rollout restart`) ou utiliser un hash d'annotation / `configMapGenerator` Kustomize pour déclencher un RollingUpdate automatique.
3. **Défi 1 – Que renvoie `/ready` et `/health` si on retire `secretRef` de `webapp` ?**
   * `GET /health` continue de renvoyer `200 OK` (le processus Flask/Gunicorn tourne).
   * `GET /ready` renvoie **`503 Service Unavailable`** (`{"status": "redis indisponible"}`) car `REDIS_PASSWORD` n'est plus injecté et l'authentification auprès de Redis échoue (`NOAUTH` / `WRONGPASS`). Les Pods passent en `0/1 READY` et le Service leur retire le trafic.

---

## TP 4.8 : Scaling, RollingUpdate, Rollback et HPA

### 1. Comportement des stratégies de mise à jour (Défi TP 4.8)
* **`maxSurge: 1 / maxUnavailable: 0` (Recommandé en prod) :** Crée d'abord 1 nouveau Pod, attend qu'il soit `Ready`, puis supprime 1 ancien Pod → **100 % de capacité maintenue, 0 coupure**.
* **`maxSurge: 0 / maxUnavailable: 1` :** Supprime d'abord 1 ancien Pod avant de créer le nouveau → **0 coupure** si `replicas >= 2`, capacité réduite temporairement à `N-1`, mais n'exige aucune ressource CPU/RAM supplémentaire sur un cluster saturé.
* **`type: Recreate` :** Tue tous les anciens Pods avant de créer les nouveaux → **coupure de service temporaire**, utilisé uniquement quand deux versions ne peuvent pas coexister ou partagent un verrou exclusif sur un volume.

---

## TP 4.9 : Sondes (`livenessProbe` / `readinessProbe`), Ressources et Quotas

### 1. Réponse à la question
* **Pourquoi ne faut-il PAS vérifier Redis dans la `livenessProbe` de l'application web ?**
  * Si Redis tombe en panne quelques secondes et que la `livenessProbe` de `webapp` vérifie Redis, Kubernetes va croire que tous les Pods `webapp` sont plantés et va les **tuer et redémarrer en boucle (`CrashLoopBackOff`)**, alors que le processus Python fonctionne très bien ! Vérifier Redis uniquement dans la `readinessProbe` retire proprement les Pods du Service le temps de la panne Redis, et rétablit le trafic dès la seconde où Redis revient, sans aucun redémarrage inutile.

---

## TP 4.10 : Stockage Persistant – PV, PVC et StatefulSet

### 1. Réponses aux questions
* **Modes d'accès :**
  * `ReadWriteOnce (RWO)` : Le volume peut être monté en lecture/écriture par **un seul nœud**.
  * `ReadOnlyMany (ROX)` : Le volume peut être monté en lecture seule par **plusieurs nœuds**.
  * `ReadWriteMany (RWX)` : Le volume peut être monté en lecture/écriture par **plusieurs nœuds simultanément** (ex. NFS, CephFS, EFS).
* **Politiques de recyclage (`persistentVolumeReclaimPolicy`) :**
  * `Retain` : À la suppression du PVC, le PV et ses données sont **conservés** (état `Released`) jusqu'à intervention d'un administrateur.
  * `Delete` : À la suppression du PVC, le PV et le disque sous-jacent sont **automatiquement détruits**.

### 2. Tableau comparatif `Deployment` vs `StatefulSet`

| Critère | `Deployment` | `StatefulSet` |
| :--- | :--- | :--- |
| **Nom des Pods** | Aléatoire (`webapp-7c9f...`) | Stable et ordonné (`redis-0`, `redis-1`) |
| **Stockage** | Partagé ou aucun | Un PVC dédié par Pod (`volumeClaimTemplates`) |
| **Ordre de démarrage/arrêt** | Parallèle | Séquentiel (`0`, `1`, `2` puis suppression inverse) |
| **Usage typique** | Applications sans état (*stateless*) | Bases de données, caches persistants, files de messages |

### 3. Défi TP 4.10 (WordPress + MySQL StatefulSet + PVC `/var/www/html`)
* Manifest complet avec `StatefulSet/mysql` (`volumeClaimTemplates`) et PVC `wp-html-pvc` pour `/var/www/html` : [`solutions/tp4.10/wordpress-statefulset.yaml`](solutions/tp4.10/wordpress-statefulset.yaml).

---

## TP 4.11 & 4.12 : Ingress TLS, Cert-Manager et Kustomize

* **Solution du Défi TP 4.11 (`cert-manager` + Let's Encrypt) :** Voir [`solutions/tp4.7_a_4.11/cert-manager-defi.yaml`](solutions/tp4.7_a_4.11/cert-manager-defi.yaml).
* **Comparaison Kustomize vs Helm (Défi TP 4.12) :**
  * **Kustomize :** Natif dans `kubectl` (`-k`), manipule du pur YAML Kubernetes valide via un système d'héritage (`base/` + `overlays/` et patchs), idéal pour gérer ses propres applications internes entre `dev`, `staging` et `prod`.
  * **Helm :** Gestionnaire de paquets utilisant des templates Go (`{{ .Values.xxx }}`), intègre la gestion des releases, rollbacks et dépendances ; idéal pour distribuer et installer des briques tierces complexes (`kube-prometheus-stack`, `redis`, `ingress-nginx`).

---

## TP 4.13 : Dépannage – Tableau complet des 6 pannes résolues

| # | Ressource | Symptôme observé | Commande de diagnostic clé | Cause racine | Correction appliquée |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1** | `deploy/front` | `ErrImagePull` / `ImagePullBackOff` | `kubectl describe pod -l app=front` | Faute de frappe dans le tag de l'image : `nginx:1.27-alpnie` | Corriger l'image en `nginx:1.27-alpine` |
| **2** | `deploy/api` | `CrashLoopBackOff` | `kubectl logs -l app=api --previous` | `ModuleNotFoundError: No module named 'flask'` sur l'image nue `python:3.12-slim` (et la commande se termine aussitôt) | Utiliser l'image applicative construite `legeni-webapp:1.0.0` |
| **3** | `svc/web` | `wget: download timed out` | `kubectl describe svc web` → `Endpoints: <none>` | Le Service sélectionne `app: website` alors que les Pods ont le label `app: web` | Corriger le `selector` du Service en `app: web` |
| **4** | `svc/app` | `wget: can't connect: Connection refused` | `kubectl describe svc app` + `kubectl get pod -l app=app -o yaml` | Le Service cible `targetPort: 8080` alors que le conteneur `nginx` écoute sur le port `80` | Corriger `targetPort: 80` dans le Service `app` |
| **5** | `deploy/conf` | `CreateContainerConfigError` | `kubectl describe pod -l app=conf` | Le conteneur référence la ConfigMap `config-app` qui n'existe pas dans le namespace | Créer la `ConfigMap` `config-app` (ou ajouter `optional: true`) |
| **6** | `pod/db` & `pvc/data` | Pod `Pending` et PVC `Pending` | `kubectl describe pvc data` | Le PVC demande `storageClassName: rapide`, qui n'existe pas dans le cluster (`kubectl get sc`) | Supprimer le PVC immuable et le recréer avec `storageClassName: standard` |

* Fichier YAML regroupant les 6 pannes corrigées : [`solutions/tp4.13_depannage/pannes_corrigees.yaml`](solutions/tp4.13_depannage/pannes_corrigees.yaml)
* **Défi en binôme (Panne 7 originale)** : [`solutions/tp4.13_depannage/panne7_defi_corrigee.yaml`](solutions/tp4.13_depannage/panne7_defi_corrigee.yaml) — Pod `Running` mais `0/1 READY` dû à une `readinessProbe` pointant vers `/inexistant` au lieu de `/health` (`kubectl describe pod` montrant `Readiness probe failed: HTTP probe failed with statuscode: 404`).
