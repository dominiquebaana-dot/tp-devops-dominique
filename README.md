# Plateforme DevOps B3 – Dominique (100 % Autonome & Déportable)

Cette plateforme DevOps regroupe l'ensemble des travaux pratiques et projets de Dominique :
- **TP Git** (TP 2.1 : GitHub Flow, branches, PR, résolution de conflit, `git revert`, tags, protection `main`, hook `pre-commit`)
- **TP Docker** (TP 2.2 à 2.10 : conteneurs, réseaux, volumes, multi-stage, Compose, troubleshooting)
- **App Fil Rouge** (Microservice Flask, architecture 3-tiers, tests unitaires, linter, packaging non-root)
- **TP Jenkins** (TP 3.1 à 3.8 : image contrôleur personnalisée, Docker-in-Docker CLI, pipelines CI/CD)
- **TP Kubernetes** (TP 4.1 à 4.13 : Pods, Deployments, Services, Ingress, TLS, Kustomize, HPA, StatefulSet)
- **TP Ansible** (TP 5.1 à 5.6 : lab 3 nœuds SSH/systemd, playbooks, variables, rôles, Vault, déploiement K8s)
- **Projet CI/CD** (Solution IaC Ansible complète, tests, coverage, linters, déploiement K8s avec rollback)
- **Projet Final IC GROUP** (Intégration Odoo 17 ERP, PostgreSQL 15, pgAdmin 4, portail Legeni Academy)

L'ensemble des scripts et configurations a été audité et fiabilisé pour garantir une exécution autonome sans aucune intervention manuelle préalable sur un système vierge (**Ubuntu 24.04 LTS**, **Debian 12** ou **WSL2 avec accès sudo**).

> [!TIP]
> Consultez **[GUIDE_TESTS_COMPLET.md](GUIDE_TESTS_COMPLET.md)** pour vérifier l'ensemble des services actifs, relancer pas à pas les travaux pratiques (`TP git` à `TP ansible`) et les projets (`Projet CICD`, `Projet final IC GROUP`), exécuter les tests manuels de qualité/sécurité, piloter Jenkins et contrôler les publications GitHub / Docker Hub.

---

## 💻 1. Prérequis Système et Ressources

| Ressource | Recommandation minimale | Notes |
| :--- | :--- | :--- |
| **Système d'exploitation** | Ubuntu 24.04 LTS, Debian 12 ou WSL2 (Windows 10/11) | Prise en charge native de systemd ou fallback service |
| **Privilèges** | Utilisateur avec droits `sudo` sans mot de passe recommandé | Rechargement automatique du groupe Docker via `sg docker` |
| **Processeur** | 2 vCPU minimum | Détection automatique d'architecture (`amd64` / `arm64`) |
| **Mémoire vive (RAM)** | 4 Go de RAM (3 Go dédiés à Minikube) | Minikube adapte sa mémoire automatiquement |
| **Accès réseau** | Accès Internet actif lors du premier lancement | Téléchargement des paquets `apt`, images Docker Hub et binaire Minikube |

---

## 🚀 2. Démarrage Rapide

Ouvrez un terminal dans le répertoire `Dominique/` et exécutez la commande de votre choix :

### Lancement global (Installation de zéro + Exécution intégrale)
```bash
# Installe TOUS les outils nécessaires (Docker, Kubectl, Minikube, Ansible, venv Python)
# et lance automatiquement l'ensemble des modules DevOps séquentiellement :
bash setup_and_run_everything.sh
```

### Lancement modulaire ciblé
```bash
# 1. Installer et configurer uniquement les outils système et dépendances :
bash setup_and_run_everything.sh install

# 2. Exécuter uniquement le TP Git (2.1) :
bash setup_and_run_everything.sh git

# 3. Exécuter uniquement la suite des TPs Docker (2.2 à 2.10) :
bash setup_and_run_everything.sh docker

# 4. Exécuter uniquement la suite des TPs Jenkins (3.1 à 3.8) :
bash setup_and_run_everything.sh jenkins

# 5. Exécuter uniquement la suite des TPs Kubernetes (4.1 à 4.13) :
bash setup_and_run_everything.sh k8s

# 6. Exécuter uniquement la suite des TPs Ansible (5.1 à 5.6) :
bash setup_and_run_everything.sh ansible

# 7. Exécuter le Projet CI/CD (Lots 0 à 5, Playbooks Ansible, Déploiement K8s & Soutenance) :
bash setup_and_run_everything.sh final

# 8. Exécuter le Projet Final IC GROUP (Odoo, pgAdmin, Legeni Academy sur Minikube/Docker) :
bash setup_and_run_everything.sh icgroup

# 9. Nettoyer complètement l'environnement (conteneurs, réseaux, Minikube, caches) :
bash setup_and_run_everything.sh clean
```

### Exécution via les runners autonomes dédiés
Chaque sous-module dispose de son propre runner exécutable et indépendant :
```bash
./"TP git/run_all_tp_git.sh"                     # Runner Git
./"TP docker/run_all_tp_docker.sh"               # Runner Docker
./TP_jenkins/run_all_tp_jenkins.sh              # Runner Jenkins
./"TP kubernetes/run_all_tp_kubernetes.sh"       # Runner Kubernetes
./"TP ansible/run_all_tp_ansible.sh"             # Runner Ansible
./"Projet CICD/run_projet_cicd.sh"              # Runner Projet CI/CD
./"Projet final/run_projet_final.sh" [all|k8s|ansible] # Runner Projet Final IC GROUP
```

---

## 🌐 3. Tableau de Référence des Ports Réseau

| Port hôte / NodePort | Service / Conteneur | Module / TP | Description |
| :--- | :--- | :--- | :--- |
| **5000** | `registry:3` | TP 3.4 / Jenkins | Registre Docker local pour la publication d'artefacts |
| **5001** | `legeni-webapp:1.0.0` | TP 2.5 (dev) | Environnement de développement Flask |
| **5002** | `legeni-webapp:1.0.0` | TP 2.5 (prod) | Environnement de production Flask |
| **5003** | `legeni-webapp:1.0.0` | TP 2.5 (staging) | Environnement de staging Flask (via `staging.env`) |
| **5050** | `pgadmin4` | Projet final IC GROUP | Interface d'administration web PostgreSQL |
| **8000** | `wordpress` | TP 2.8 | CMS WordPress relié à MariaDB |
| **8069** | `odoo` | Projet final IC GROUP | ERP Odoo 17 relié à PostgreSQL 16 |
| **8080** | `jenkins` | TP 3.1 à 3.8 / CI/CD | Interface Web du contrôleur Jenkins |
| **8081** | `web` (deploy staging) | TP 3.8 | Application fil rouge déployée par Jenkins en staging |
| **8085** | `nginx` | TP 2.10 (Panne 2) | Conteneur Nginx pour démonstration conflit de port |
| **8086** | `legeni-webapp` | TP 2.10 (Panne 3) | Diagnostic mapping port interne 5000 vs 80 |
| **8087** | `legeni-webapp` | TP 2.10 (Panne 4) | Diagnostic connexion réseau bridge Redis |
| **8090** | `proxy` (Nginx) | App Fil Rouge & TP 2.8 | Reverse-proxy Nginx avec DNS Docker dynamique |
| **8092** | `legeni_website` | TP 3.2 | Déploiement Freestyle du site restaurant |
| **8095** | `demo:entrypoint` | TP 2.5 | Test de l'injection d'environnement au démarrage |
| **30080** | `my-service` / `webapp` | TP 4.3 & TP 4.7 | Service NodePort démonstrateur Kubernetes |
| **30081** | `webapp-service` | Projet CI/CD | NodePort Kubernetes environnement Staging |
| **30082** | `webapp-service` | Projet CI/CD | NodePort Kubernetes environnement Production |
| **30085** | `legeni-academy-service`| Projet Final IC GROUP | Portail vitrine Legeni Academy sur Minikube |
| **30180** | `webapp-deployment` | TP 4.4 | Déploiement applicatif fil rouge dev |
| **30181** | `webapp-prod` | TP 4.4 | Déploiement applicatif fil rouge prod |
| **50000** | `jenkins` | TP 3.1 | Port de connexion TCP pour les agents Jenkins (JNLP) |

---

## 🔐 4. Gabarits d'Environnement et Gestion des Secrets

Conformément aux bonnes pratiques DevOps, aucun secret, mot de passe ou certificat local n'est stocké en clair dans les dépôts publics. Des fichiers modèles `.example` sont mis à disposition pour chaque composant :

### Fichiers d'environnement Docker Compose
Les scripts d'orchestration génèrent ou injectent automatiquement les variables requises si les fichiers `.env` n'existent pas. Pour une configuration manuelle, copiez simplement le gabarit :

```bash
# 1. Application Fil Rouge (développement local) :
cp app-fil-rouge/.env.example app-fil-rouge/.env

# 2. Application Fil Rouge (déploiement automatisé) :
cp app-fil-rouge/deploy/.env.example app-fil-rouge/deploy/.env

# 3. Contrôleur Jenkins Docker :
cp TP_jenkins/jenkins-docker/.env.example TP_jenkins/jenkins-docker/.env
# Ou calcul automatique du GID :
echo "DOCKER_GID=$(stat -c %g /var/run/docker.sock 2>/dev/null || echo 999)" > TP_jenkins/jenkins-docker/.env

# 4. Rôle Ansible Jenkins :
cp "Projet CICD/legeni-webapp/ansible/roles/jenkins/files/jenkins-docker/.env.example" \
   "Projet CICD/legeni-webapp/ansible/roles/jenkins/files/jenkins-docker/.env"
```

### Secrets Kubernetes & Ansible Vault
- **Ansible Vault (`vars/vault.yml`)** : Le mot de passe par défaut pour déchiffrer `vars/vault.yml` est stocké dans `Projet CICD/legeni-webapp/ansible/.vault_pass.example` (`LegeniVault2026!`). Le script `run_projet_cicd.sh` sécurise automatiquement les permissions (`0600`) et chiffre le fichier modèle `vars/vault.yml.example` si aucun coffre-fort n'existe.
  ```bash
  cd "Projet CICD/legeni-webapp/ansible"
  ansible-vault view vars/vault.yml --vault-password-file .vault_pass.example
  ```
- **Secrets Kubernetes** : Des gabarits de manifests déclaratifs sont fournis :
  - `TP kubernetes/solutions/tp4.5/mysql-pass.secret.yaml.example` (Secret `mysql-pass` pour WordPress/MySQL)
  - `TP kubernetes/solutions/tp4.7_a_4.11/redis-secret.secret.yaml.example` (Secret `redis-secret` pour Redis/App)
  - `Projet final/solution/k8s/icgroup-secrets.yaml.example` (Secret `icgroup-secrets` pour Odoo, Postgres et pgAdmin)
  - `Projet CICD/legeni-webapp/ansible/kubeconfig-jenkins.yml.example` (Gabarit Kubeconfig)

---

## 🧹 5. Procédures de Remise à Zéro et Nettoyage

Pour réinitialiser complètement votre système et retrouver un état vierge avant une nouvelle évaluation :

```bash
# Commande intégrée de nettoyage :
bash setup_and_run_everything.sh clean

# Ou commandes manuelles équivalentes :
# 1. Arrêter et supprimer tous les conteneurs Docker :
docker rm -f $(docker ps -aq) 2>/dev/null || true

# 2. Supprimer les réseaux résiduels inutilisés :
docker network prune -f

# 3. Supprimer le cluster Minikube :
minikube delete

# 4. Nettoyer les caches Python locaux et logs résiduels :
find . -type d \( -name "__pycache__" -o -name ".pytest_cache" \) -exec rm -rf {} + 2>/dev/null || true
find . -type f -name "*.pyc" -delete 2>/dev/null || true
```

---

## 📂 6. Structure Complète du Dossier

```
Dominique/
├── setup_and_run_everything.sh      # Orchestrateur général maître « La Totale »
├── README.md                        # Guide complet d'utilisation et d'évaluation
├── .gitignore                       # Protection contre les artefacts, logs et caches
├── .gitattributes                   # Enforce 100% de fins de ligne UNIX LF
├── TP git/
│   ├── run_all_tp_git.sh            # Runner autonome TP 2.1 (GitHub Flow, conflits, revert, tag, hooks)
│   ├── COMPTE_RENDU_TP_GIT.md       # Réponses aux questions et solutions des défis Git
│   └── solutions/                   # .gitignore, hook pre-commit flake8, pre-receive protection main
├── TP docker/
│   ├── run_all_tp_docker.sh         # Runner modulaire autonome des TPs Docker
│   ├── COMPTE_RENDU_TP_DOCKER.md    # Rapport d'évaluation complet des TPs 2.2 à 2.10
│   └── solutions/                   # Solutions tp2.2 à tp2.10 (Dockerfile.alpine autonome, 5 pannes, Compose)
├── app-fil-rouge/
│   ├── app.py, Dockerfile, docker-compose.yml, .env.example
│   ├── deploy/ (docker-compose.deploy.yml, smoke-test.sh, .env.example)
│   ├── nginx/default.conf           # Reverse-proxy port 8090
│   └── tests/ (test_app.py)         # Tests unitaires Pytest & intégration Flask
├── TP_jenkins/
│   ├── run_all_tp_jenkins.sh        # Runner modulaire autonome des TPs Jenkins
│   ├── COMPTE_RENDU_TP_JENKINS.md   # Rapport complet des TPs 3.1 à 3.8
│   ├── jenkins-docker/              # Image personnalisée, plugins.txt, compose, .env.example
│   └── solutions/ (tp3.1 à tp3.8)   # Pipelines déclaratifs, scripts Freestyle, Acceptance, Artefact
├── Projet CICD/
│   ├── run_projet_cicd.sh           # Runner autonome IaC Ansible, tests, déploiement & soutenance
│   └── legeni-webapp/
│       ├── app.py, Dockerfile, Jenkinsfile, requirements.txt, VERSION
│       ├── docs/rapport.md          # Rapport de soutenance complet
│       ├── tests/                   # 6 tests unitaires Flask (couverture 84%)
│       └── ansible/                 # Playbooks provision.yml, deploy.yml, requirements.yml, roles/
├── TP kubernetes/
│   ├── run_all_tp_kubernetes.sh     # Runner modulaire autonome des TPs Kubernetes
│   ├── COMPTE_RENDU_TP_KUBERNETES.md# Rapport complet des TPs 4.1 à 4.13
│   └── solutions/                   # Manifests tp4.2 à tp4.13 (Pods, Ingress, Kustomize, Dépannage)
├── TP ansible/
│   ├── run_all_tp_ansible.sh        # Runner modulaire autonome des TPs Ansible (5.1 à 5.6)
│   ├── COMPTE_RENDU_TP_ANSIBLE.md   # Rapport complet des TPs 5.1 à 5.6 et défis
│   └── lab/                         # Lab 3 nœuds (web1, web2, db1), playbooks, rôles, Vault, K8s
└── Projet final/
    ├── run_projet_final.sh          # Runner autonome du Projet Final IC GROUP (all|k8s|ansible)
    ├── RAPPORT_PROJET_FINAL_ICGROUP.md # Rapport complet du projet IC GROUP
    └── solution/                    # Manifests k8s (NodePort 30085), Dockerfile, Ansible (odoo + pgadmin)
```

---

## 🔗 6. Dépôts Publiés & Accès Rapide (Windows / WSL)

* **GitHub (`dominiquebaana-dot`) :**
  * Application fil rouge CI/CD : `https://github.com/dominiquebaana-dot/legeni-webapp` (`main`, `feature/*`, tags `v1.0.0`, `v1.1.0`)
  * Projet Final IC GROUP : `https://github.com/dominiquebaana-dot/projet-final-icgroup` (`main`, `feature/*`, tag `v1.0.0`)
  * Portfolio complet des TPs & Projets : `https://github.com/dominiquebaana-dot/tp-devops-dominique`
* **Docker Hub (`heyitsdom`) :**
  * `heyitsdom/legeni-webapp` (`1.0.0`, `1.0.0-1`, `1.0.1`, `1.1.0-2`, `2.0.0`, `latest`)
  * `heyitsdom/restaurant` (`1.0`, `multistage`, `latest`)
  * `heyitsdom/legeni-academy` (`1.0`, `latest`)
* **Services actifs accessibles depuis Windows (`http://localhost`) :**
  * Jenkins : `http://localhost:8080` (identifiants configurés : `admin` / `1234`)
  * Staging `legeni-webapp` : `http://localhost:30081/api/info` (relais `minikube-port-proxy`)
  * Production `legeni-webapp` : `http://localhost:30082/api/info` (relais `minikube-port-proxy`)
  * Portail Legeni Academy (`icgroup`) : `http://localhost:30085` (relais `minikube-port-proxy`)
  * Odoo (`icgroup`) : `http://localhost:30069/web/login` (relais `minikube-port-proxy`)
  * pgAdmin (`icgroup`) : `http://localhost:30050` (relais `minikube-port-proxy`)
