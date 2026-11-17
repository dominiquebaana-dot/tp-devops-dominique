# Rapport Final DevOps – Sujet IC GROUP (Legeni Academy, Odoo & pgAdmin 4)

> Ce document constitue le rapport complet du sujet **[TPAFAIRE/Projet final/Guide.md](../TPAFAIRE/Projet%20final/Guide.md)** (IC GROUP).
> L'ensemble des fichiers sources, rôles Ansible, `Dockerfile`, `Jenkinsfile` et manifests Kubernetes sont disponibles dans [`solution/`](solution/).

---

## Partie 1 : Conteneurisation du site vitrine *Legeni Academy*

* **Fichiers réalisés :**
  * [`solution/app.py`](solution/app.py) : Application Flask écoutant sur le port `8080` et injectant dynamiquement `ODOO_URL` et `PGADMIN_URL`.
  * [`solution/releases.txt`](solution/releases.txt) : Fichier de métadonnées contenant sur 3 lignes et 2 colonnes (`ODOO_URL`, `PGADMIN_URL`, `Version`).
  * [`solution/Dockerfile`](solution/Dockerfile) : Image Alpine légère lisant automatiquement `releases.txt` avec `awk` et `export` dans l'`ENTRYPOINT`.

### Commandes de build et de test (Partie 1) :
```bash
cd "Projet final/solution"
docker build -t legeni-academy:1.0 .
docker run -d --name test-legeni-academy -p 8080:8080 \
  -e ODOO_URL="https://www.odoo.com" \
  -e PGADMIN_URL="https://www.pgadmin.org" \
  legeni-academy:1.0
curl -s http://localhost:8080 | grep -E "odoo|pgadmin"
docker rm -f test-legeni-academy
```

---

## Partie 2 : Pipeline CI/CD avec Jenkins et Rôles Ansible

* **Rôles Ansible variabilisés :**
  1. **[`odoo_role`](solution/ansible/roles/odoo_role/)** : Déploie PostgreSQL + Odoo avec variabilisation complète du réseau (`odoo_network_name`), du volume (`odoo_volume_name`), du chemin hôte de persistance de la BDD (`odoo_db_host_path`) et des noms de services/conteneurs dans [`defaults/main.yml`](solution/ansible/roles/odoo_role/defaults/main.yml) et [`templates/docker-compose.odoo.yml.j2`](solution/ansible/roles/odoo_role/templates/docker-compose.odoo.yml.j2).
  2. **[`pgadmin_role`](solution/ansible/roles/pgadmin_role/)** : Génère automatiquement le fichier `servers.json` pré-configuré pour se connecter à la base Odoo, et déploie `pgAdmin 4` + le site vitrine `Legeni Academy` via [`templates/docker-compose.pgadmin.yml.j2`](solution/ansible/roles/pgadmin_role/templates/docker-compose.pgadmin.yml.j2).
* **Pipeline Jenkins :**
  * [`solution/Jenkinsfile`](solution/Jenkinsfile) : Extrait dynamiquement `Version`, `ODOO_URL` et `PGADMIN_URL` depuis `releases.txt` via `awk`, construit l'image `legeni-academy:<Version>`, exécute les tests d'acceptance HTTP, pousse l'image sur Docker Hub et déclenche le déploiement Ansible [`deploy_icgroup.yml`](solution/ansible/deploy_icgroup.yml).

---

## Partie 3 : Architecture et Déploiement Kubernetes (Minikube)

### 1. Identification des ressources du synoptique Kubernetes (A à H)

| Repère | Type de ressource Kubernetes | Rôle dans l'architecture IC GROUP |
| :--- | :--- | :--- |
| **A** | **`Namespace`** (`icgroup`) | Isole logiquement toutes les ressources du projet IC GROUP au sein du cluster Minikube (avec le label obligatoire `env: prod`). |
| **B** | **`Service` (`type: NodePort`)** | Expose les applications frontales (`legeni-academy-service`, `odoo-service`, `pgadmin-service`) vers l'extérieur du cluster et répartit la charge entre les Pods. |
| **C** | **`Deployment` / `ReplicaSet`** (`legeni-academy` & `odoo`) | Garantit la haute disponibilité et l'auto-réparation des applications web en maintenant plusieurs réplicas actifs. |
| **D** | **`Pod`** | Unité d'exécution hébergeant les conteneurs applicatifs (`legeni-academy`, `odoo`, `pgadmin4`, `postgres`). |
| **E** | **`Service` (`type: ClusterIP`)** (`postgres-service`) | Fournit une adresse IP interne et un nom DNS stable (`postgres-service:5432`) permettant à Odoo et pgAdmin de joindre la base PostgreSQL sans l'exposer à l'extérieur. |
| **F** | **`ConfigMap`** (`pgadmin-servers-config`) | Injecte le fichier `/pgadmin4/servers.json` dans le conteneur pgAdmin pour pré-enregistrer automatiquement le serveur PostgreSQL Odoo au démarrage. |
| **G** | **`Secret`** (`icgroup-secrets`) | Stocke de manière sécurisée (hors des manifests Git publics) les identifiants sensibles : `POSTGRES_USER`, `POSTGRES_PASSWORD`, `PGADMIN_DEFAULT_EMAIL`, `PGADMIN_DEFAULT_PASSWORD`. |
| **H** | **`PersistentVolumeClaim` (PVC) & `PersistentVolume` (PV)** | Assure la persistance des données de la base PostgreSQL (`/var/lib/postgresql/data`) et de la configuration pgAdmin (`/var/lib/pgadmin`) sur le stockage hôte en cas de redémarrage ou suppression d'un Pod. |

### 2. Déploiement des manifests dans le cluster (`namespace: icgroup`, `env: prod`)
```bash
# 1. Création du namespace et du Secret (hors Git pour protéger les mots de passe)
kubectl create namespace icgroup --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace icgroup env=prod --overwrite

kubectl create secret generic icgroup-secrets -n icgroup \
  --from-literal=postgres-user=odoo \
  --from-literal=postgres-password=OdooProdSecret2026! \
  --from-literal=pgadmin-email=admin@icgroup.com \
  --from-literal=pgadmin-password=PgAdminSecret2026! \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl label secret icgroup-secrets -n icgroup env=prod --overwrite

# 2. Application de l'ensemble des manifests (PVC, ConfigMap, Deployments, Services)
kubectl apply -f "Projet final/solution/k8s/icgroup-manifests.yaml"
kubectl get all,pvc,cm,secret -n icgroup -l env=prod
```

---

## 4. Résultats d'Exécution Réels & Dépôts Publiés

* **Déploiement Kubernetes (`icgroup`, `env: prod`) :**
  * `deployment.apps/postgres-deployment` (`1/1 Running`, `postgres-pvc` `Bound` 2Gi)
  * `deployment.apps/odoo-deployment` (`2/2 Running`, NodePort `30069`)
  * `deployment.apps/pgadmin-deployment` (`1/1 Running`, `pgadmin-pvc` `Bound` 1Gi, NodePort `30050`)
  * `deployment.apps/legeni-academy-deployment` (`2/2 Running`, NodePort `30085`, page `<title>Legeni Academy - IC GROUP</title>` avec liens `http://localhost:30069` et `http://localhost:30050`)
* **Pipeline Jenkins réel (`projet-final-icgroup` #1) :**
  * Exécuté sur `http://localhost:8080` : **`SUCCESS`** (`80 296 ms`) — lecture de `releases.txt`, build image `heyitsdom/legeni-academy:1.0`, test réseau conteneur, push Docker Hub `heyitsdom`, validation syntaxe `deploy_icgroup.yml` et rollout Kubernetes `icgroup`.
* **Traces & Dépôts en ligne :**
  * Log local complet : [`logs_execution_projet_final.txt`](logs_execution_projet_final.txt)
  * GitHub : `https://github.com/dominiquebaana-dot/projet-final-icgroup` (`main`, `feature/*`, `v1.0.0`)
  * Docker Hub : `heyitsdom/legeni-academy:1.0` & `:latest`
