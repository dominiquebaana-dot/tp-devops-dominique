# Guide Complet de Test, Vérification et Soutenance

Ce document explique pas à pas comment vérifier l'ensemble des services actifs, relancer les travaux pratiques (`TP git` à `TP ansible`) ainsi que les deux projets (`Projet CICD` et `Projet final IC GROUP`), exécuter les tests manuels de qualité/sécurité, piloter Jenkins et contrôler les publications GitHub et Docker Hub.

---

## 1. Architecture de test : Windows vs WSL2 (Ubuntu)

> [!IMPORTANT]
> Sous WSL2, les fichiers situés sous `/mnt/c/Dominique` sont montés via `drvfs` avec des droits `0777` (dossier considéré *world-writable*). Par mesure de sécurité, Ansible ignore alors `ansible.cfg`.
> * **Édition / consultation :** depuis Windows dans `C:\Dominique`.
> * **Exécution (Ansible, Docker, Minikube, scripts) :** depuis la copie Linux native `~/Dominique` dans Ubuntu WSL2 (avec `chmod -R go-w ~/Dominique`).

### Synchroniser `C:\Dominique` vers `~/Dominique` avant une exécution dans WSL
```bash
mkdir -p ~/Dominique
rsync -a --exclude='.git' --exclude='TP ansible/lab/keys' /mnt/c/Dominique/ ~/Dominique/
chmod -R go-w ~/Dominique
cd ~/Dominique
```
*(Si `rsync` n'est pas installé, utilisez `cp -a /mnt/c/Dominique/. ~/Dominique/`.)*

### Maintenir Minikube actif quand on teste depuis Windows
Windows met automatiquement Ubuntu WSL2 en veille quelques secondes après la fermeture de toutes ses fenêtres/sessions, ce qui stoppe le conteneur `minikube` (alors que `jenkins`, `minikube-port-proxy` et `lab-*` redémarrent automatiquement).
1. **Gardez au moins un terminal Ubuntu (`wsl`) ouvert** pendant vos tests navigateur sous Windows.
2. Si les ports Kubernetes (`30050`, `30069`, `30081`, `30082`, `30085`) ne répondent plus après une mise en veille ou un redémarrage du PC :
```bash
minikube start
minikube update-context
```

---

## 2. Vérification rapide des services actifs (Smoke Check complet)

### A. Depuis Windows (PowerShell)
```powershell
@(
  "http://localhost:8080/login",
  "http://localhost:30081/api/info",
  "http://localhost:30082/api/info",
  "http://localhost:30085/",
  "http://localhost:30069/web/login",
  "http://localhost:30050/",
  "http://localhost:8001/",
  "http://localhost:8002/",
  "http://localhost:8101/api/info",
  "http://localhost:8102/api/info",
  "http://localhost:8103/"
) | ForEach-Object {
  $code = curl.exe -s -m 5 -o NUL -w "%{http_code}" $_
  "$_ -> HTTP $code"
}
```

#### Table des accès attendus sur `http://localhost`
| Service | URL Windows | Code attendu | Remarque / Identifiants |
| :--- | :--- | :--- | :--- |
| **Jenkins Web UI** | `http://localhost:8080` | `200` | Utilisateur `admin` / Mot de passe `1234` |
| **Legeni WebApp (Staging K8s)** | `http://localhost:30081/api/info` | `200` | JSON (`"env":"staging"`) via relais `minikube-port-proxy` |
| **Legeni WebApp (Prod K8s)** | `http://localhost:30082/api/info` | `200` | JSON (`"env":"prod"`) via relais `minikube-port-proxy` |
| **Legeni Academy (`icgroup`)** | `http://localhost:30085/` | `200` | Portail vitrine IC GROUP sur Minikube |
| **Odoo (`icgroup`)** | `http://localhost:30069/web/login` | `200` / `303` | ERP Odoo sur Minikube |
| **pgAdmin (`icgroup`)** | `http://localhost:30050/` | `200` / `302` | Interface d'administration PostgreSQL |
| **Lab Ansible Nginx (`web1` / `web2`)** | `http://localhost:8001/` et `:8002/` | `200` | Déploiement TP 5.2 (`lab-web1-1`, `lab-web2-1`) |
| **Lab Ansible WebApp (`web1` / `web2`)** | `http://localhost:8101/api/info` et `:8102/api/info` | `200` | Rôle Ansible `webapp` (`env: dev` vs `preprod`) |
| **Lab Ansible WordPress (`db1`)** | `http://localhost:8103/` | `200` / `302` | Déploiement WordPress + MariaDB (TP 5.5) |

### B. Depuis WSL Ubuntu (Conteneurs & Cluster Kubernetes)
```bash
# État des conteneurs Docker (jenkins, minikube, minikube-port-proxy, lab Ansible)
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# État des namespaces déployés sur Minikube
kubectl get all,pvc,ingress,hpa,cronjob -n legeni-staging
kubectl get all,pvc,ingress,hpa,cronjob -n legeni-prod
kubectl get all,pvc,cm,secret -n icgroup
```

---

## 3. Exécuter et tester tous les modules automatiquement

Toutes les commandes ci-dessous s'exécutent dans **Ubuntu WSL2** depuis `~/Dominique` :

### A. Via l'orchestrateur maître `setup_and_run_everything.sh`
```bash
cd ~/Dominique

bash setup_and_run_everything.sh install   # Installe/vérifie prérequis (Docker, kubectl, Minikube, Ansible, /opt/k8s-python)
bash setup_and_run_everything.sh git       # TP 2.1 Git
bash setup_and_run_everything.sh docker    # TP 2.2 à 2.10 Docker
bash setup_and_run_everything.sh jenkins   # TP 3.1 à 3.8 Jenkins
bash setup_and_run_everything.sh k8s       # TP 4.1 à 4.13 Kubernetes
bash setup_and_run_everything.sh ansible   # TP 5.1 à 5.6 Ansible
bash setup_and_run_everything.sh final     # Projet CI/CD (Lots 0 à 5 + Soutenance)
bash setup_and_run_everything.sh icgroup   # Projet Final IC GROUP
bash setup_and_run_everything.sh           # Enchaîne toute la suite de A à Z
```

### B. Runners individuels et journaux d'exécution
| Module | Commande d'exécution (dans `~/Dominique`) | Compte-rendu | Trace d'exécution vérifiée |
| :--- | :--- | :--- | :--- |
| **TP Git (2.1)** | `bash "TP git/run_all_tp_git.sh"` | `TP git/COMPTE_RENDU_TP_GIT.md` | `TP git/logs_execution_tp_git.txt` |
| **TP Docker (2.2–2.10)** | `bash "TP docker/run_all_tp_docker.sh"` | `TP docker/COMPTE_RENDU_TP_DOCKER.md` | `TP docker/logs_execution_tp_docker.txt` |
| **TP Jenkins (3.1–3.8)** | `bash TP_jenkins/run_all_tp_jenkins.sh` | `TP_jenkins/COMPTE_RENDU_TP_JENKINS.md` | `TP_jenkins/logs_execution_tp_jenkins.txt` |
| **TP Kubernetes (4.1–4.13)** | `bash "TP kubernetes/run_all_tp_kubernetes.sh"` | `TP kubernetes/COMPTE_RENDU_TP_KUBERNETES.md` | `TP kubernetes/logs_execution_tp_kubernetes.txt` |
| **TP Ansible (5.1–5.6)** | `bash "TP ansible/run_all_tp_ansible.sh"` | `TP ansible/COMPTE_RENDU_TP_ANSIBLE.md` | `TP ansible/logs_execution_tp_ansible.txt` |
| **Projet CI/CD** | `bash "Projet CICD/run_projet_cicd.sh"` | `Projet CICD/legeni-webapp/docs/rapport.md` | `Projet CICD/logs_soutenance_projet_cicd.txt` |
| **Projet Final IC GROUP** | `bash "Projet final/run_projet_final.sh" all` | `Projet final/RAPPORT_PROJET_FINAL_ICGROUP.md` | `Projet final/logs_execution_projet_final.txt` |

*(Pour rapatrier de nouveaux logs exécutés dans `~/Dominique` vers Windows `C:\Dominique` : `cp ~/Dominique/*/logs_*.txt /mnt/c/Dominique/...`.)*

### C. Tester chaque TP individuellement (pas à pas)

1. **`TP git` (TP 2.1) :**
```bash
# Exécution autonome complète (GitHub Flow, conflit rebase, git revert, tag v1.0.0, pre-receive, git undo, pre-commit flake8)
bash ~/Dominique/"TP git"/run_all_tp_git.sh
# Vérifier les hooks fournis :
ls -la ~/Dominique/"TP git"/solutions/   # .gitignore, pre-commit, pre-receive.protected-main
```

2. **`TP docker` (TP 2.2 à TP 2.10) :**
```bash
cd ~/Dominique/"TP docker"/solutions
bash tp2.2/defi_tp22.sh                             # Défi Redis cache
docker compose -f tp2.2/odoo-compose/compose.yml config
bash tp2.4/tp24_reseaux_volumes.sh                  # Réseaux, PostgreSQL & 3-tiers
docker build --target test ~/Dominique/app-fil-rouge # TP 2.6 tests + flake8
docker run --rm -i hadolint/hadolint:v2.12.0 < tp2.9/Dockerfile.restaurant.clean
bash tp2.7/tp27_reseaux_stockage.sh                 # Isolation 3-tiers, bind :ro, tmpfs, backup
bash tp2.7/backup_volume.sh                         # Défi rotation (7 archives max)
docker compose -f tp2.8/compose.yml up -d --wait --scale web=3 && curl -sf http://127.0.0.1:8090/api/info
bash tp2.10/depannage_5_pannes.sh                   # Reproduction & résolution des 5 pannes
```

3. **`TP_jenkins` (TP 3.1 à TP 3.8) :**
```bash
# Contrôle des outils dans le conteneur Jenkins
docker exec jenkins sh -c 'docker --version; docker compose version; kubectl version --client; ansible --version | head -n1'
# Scripts Freestyle, Acceptance (< 500ms) & Artefact + Trivy :
cd ~/Dominique/TP_jenkins/solutions
# (Cloner restaurant dans /tmp puis exécuter tp3.2/build_freestyle.sh, tp3.3/test_acceptance.sh, tp3.4/artefact_publish.sh, tp3.4/deploy_freestyle.sh)
ls -1 tp3.1/Jenkinsfile.verif-outils tp3.5/Jenkinsfile.tp35 tp3.6/Jenkinsfile.multibranch tp3.7/Jenkinsfile.qualite tp3.8/Jenkinsfile.cd
```

4. **`TP kubernetes` (TP 4.1 à TP 4.13) :**
```bash
cd ~/Dominique/"TP kubernetes"/solutions
kubectl apply --dry-run=client -f tp4.2/pods.yaml
kubectl apply --dry-run=client -f tp4.3/deployment-service.yaml
kubectl apply --dry-run=client -f tp4.4/webapp.yaml
kubectl apply --dry-run=client -f tp4.5/wordpress-mysql.yaml
kubectl apply --dry-run=client -f tp4.6/job-echec.yaml -f tp4.6/jobs-cronjobs-daemonset.yaml
kubectl apply --dry-run=client -f tp4.7_a_4.11/legeni-dev-stack.yaml -f tp4.7_a_4.11/blog-ingress.yaml
kubectl apply --dry-run=client -f tp4.9/oom.yaml -f tp4.9/quota-dev.yaml -f tp4.10/pv-manuel.yaml -f tp4.10/wordpress-statefulset.yaml
kubectl apply --dry-run=client -f tp4.13_depannage/pannes_corrigees.yaml -f tp4.13_depannage/panne7_defi_corrigee.yaml
```

5. **`TP ansible` (TP 5.1 à TP 5.6) :**
```bash
cd ~/Dominique/"TP ansible"/lab
docker compose ps                         # web1 (2221), web2 (2222), db1 (2223)
ansible all -m ping                       # Test connectivité SSH du lab
ansible-playbook --syntax-check nginx.yml variables.yml utilisateurs.yml docker.yml site.yml wordpress.yml k8s_deploy.yml wordpress-playbook.yaml
ansible-playbook site.yml                 # Test idempotence du rôle webapp (changed=0 au 2e passage)
ansible-playbook tests/test_webapp.yml    # Tests automatisés HTTP (:8101 dev, :8102 preprod)
ansible-playbook k8s_deploy.yml -e app_version=2.0.0   # Déploiement K8s TP 5.6
```

---

## 4. Tests unitaires, Qualité, Sécurité et Playbooks (commandes ciblées)

### A. Tests Git (`Projet CICD/legeni-webapp`)
```bash
cd ~/Dominique/"Projet CICD"/legeni-webapp
git status
git log --oneline --graph --decorate --all
git branch -a
git tag -l
```

### B. Tests Python (`pytest`, couverture `>= 80 %`, `flake8`)
```bash
cd ~/Dominique/"Projet CICD"/legeni-webapp

# Test complet via Docker multi-stage (cible test)
docker build --target test -t legeni-webapp:test .

# Mesure détaillée de la couverture de code
docker run --rm -v "$PWD:/app" -w /app python:3.12-slim sh -c \
  "pip install -q -r requirements.txt -r requirements-dev.txt && pytest -v --cov=app --cov-fail-under=80 && flake8 app.py tests/"
```

### C. Linter Dockerfile (`hadolint`), Scan d'image (`trivy`) et Scan de secrets (`gitleaks`)
```bash
cd ~/Dominique/"Projet CICD"/legeni-webapp

# Hadolint (0 erreur attendue)
docker run --rm -i hadolint/hadolint:v2.12.0 < Dockerfile
docker run --rm -i hadolint/hadolint:v2.12.0 < ~/Dominique/"TP docker"/solutions/tp2.9/Dockerfile.restaurant.clean

# Trivy (0 vulnérabilité CRITICAL corrigeable attendue)
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy_cache:/root/.cache \
  aquasec/trivy:0.57.1 image --severity CRITICAL --ignore-unfixed --exit-code 1 legeni-webapp:1.0.0-1

# Gitleaks (0 secret détecté)
docker run --rm -v "$PWD:/src:ro" --entrypoint="" zricethezav/gitleaks:v8.21.2 \
  gitleaks detect --source /src --exit-code 1
```

### D. Vérifications Ansible (`syntax-check`, Vault, Idempotence, déploiement Staging/Prod)
```bash
cd ~/Dominique/"Projet CICD"/legeni-webapp/ansible

# Préparer le fichier mot de passe Vault en /tmp (droits 0600 requis)
cp .vault_pass.example /tmp/.vault_pass && chmod 600 /tmp/.vault_pass

# Vérification syntaxe & lecture du Vault
ansible-playbook --syntax-check provision.yml
ansible-playbook --syntax-check deploy.yml -e vault_file=vars/vault.yml.example
ansible-vault view vars/vault.yml --vault-password-file /tmp/.vault_pass

# Tester l'idempotence du provisionnement (doit retourner changed=0)
sudo ansible-playbook provision.yml

# Déployer une version vers Staging ou Prod (avec Job init-migration préalable au rollout)
ansible-playbook deploy.yml --vault-password-file /tmp/.vault_pass \
  -e target_env=staging -e webapp_image=legeni-webapp -e app_version=1.1.0-2
```

### E. Tests de soutenance à la main (les 3 scénarios)
1. **Scénario 1 — Déploiement sans coupure (`1.0.0-1` -> `1.1.0-2`) :**
   * Lancer dans un terminal : `while true; do curl -s -o /dev/null -w "%{http_code} " http://127.0.0.1:30082/api/info; sleep 0.5; done` (ou via `docker exec minikube curl ...`).
   * Lancer dans un autre terminal : `ansible-playbook deploy.yml --vault-password-file /tmp/.vault_pass -e target_env=prod -e webapp_image=legeni-webapp -e app_version=1.1.0-2`.
   * Attendu : uniquement des `200`, `init-migration` à l'état `Complete` avant la bascule des pods.
2. **Scénario 2 — Test unitaire cassé bloquant :**
   * Copier le projet dans `/tmp/test_ko`, casser `"ok"` en `"ko"` dans `app.py`, puis exécuter `docker build --target test /tmp/test_ko`.
   * Attendu : arrêt immédiat avec code de sortie non nul (`1`), aucune image runtime construite.
3. **Scénario 3 — Panne `readinessProbe` & Rollback automatique :**
   * Exécuter : `ansible-playbook deploy.yml --vault-password-file /tmp/.vault_pass -e target_env=prod -e webapp_image=legeni-webapp -e app_version=1.1.0-2 -e readiness_path=/chemin-inexistant-panne`.
   * Attendu : le rollout bloque sur la sonde `/chemin-inexistant-panne`, le bloc `rescue` déclenche `kubectl rollout undo`, et les 3 pods sains précédents restent `Running` sans coupure.

### F. Vérification Kustomize (TP 4.12)
```bash
cd ~/Dominique/"TP kubernetes"/solutions/tp4.12_kustomize
kubectl kustomize overlays/staging | kubectl apply --dry-run=client -f -
kubectl kustomize overlays/prod    | kubectl apply --dry-run=client -f -
kubectl kustomize overlays/dev     | kubectl apply --dry-run=client -f -
```

---

## 5. Tester Jenkins depuis l'interface Web (`http://localhost:8080`)

1. Ouvrez **`http://localhost:8080`** dans votre navigateur Windows et connectez-vous avec **`admin`** / **`1234`**.
2. Vérifiez dans **Administrer Jenkins → Credentials** la présence de :
   * `kubeconfig` (Secret file Minikube)
   * `ansible-vault-pass` (Secret file `.vault_pass`)
   * `registry-credentials` (`heyitsdom` — Docker Hub pour `legeni-webapp`)
   * `dockerhub` (`heyitsdom` — Docker Hub pour `projet-final-icgroup`)
3. Pipelines configurés et testables en un clic (**Lancer un build / Build Now**) :
   * **`tp31-verif-outils`** : contrôle des binaires (`docker`, `docker compose`, `kubectl`, `kustomize`, `ansible`) dans le conteneur `jenkins`.
   * **`projet-final-icgroup`** : clone `https://github.com/dominiquebaana-dot/projet-final-icgroup.git`, build + test réseau + push Docker Hub + mise à jour du déploiement `legeni-academy-deployment` dans `icgroup`.
   * **`projet-cicd-legeni-webapp`** (Multibranch Pipeline lié à `https://github.com/dominiquebaana-dot/legeni-webapp.git`) :
     * Cliquez sur **Scan Multibranch Pipeline Now** puis ouvrez **`main`** → **Build Now**.
     * Consultez l'onglet **Tests** (rapport JUnit + Couverture) et **Warnings / Flake8** dans la vue du build.
     * Lorsque l'étape **`Validation Humaine Production`** s'affiche sur la carte *Stage View* (ou dans la console du build), cliquez sur **`Déployer en Production`** pour autoriser la mise en production dans `legeni-prod`.

---

## 6. Vérifier GitHub et Docker Hub en ligne

### GitHub (`dominiquebaana-dot`)
```bash
gh auth status
gh repo list dominiquebaana-dot --limit 10
```
* `https://github.com/dominiquebaana-dot/legeni-webapp`
* `https://github.com/dominiquebaana-dot/projet-final-icgroup`
* `https://github.com/dominiquebaana-dot/tp-devops-dominique`

### Docker Hub (`heyitsdom`)
```bash
docker pull heyitsdom/legeni-webapp:1.1.0-2
docker pull heyitsdom/restaurant:multistage
docker pull heyitsdom/legeni-academy:1.0
```
Pages web : `https://hub.docker.com/u/heyitsdom`

---

## 7. Dépannage express

| Symptôme | Cause probable | Commande de correction |
| :--- | :--- | :--- |
| `http://localhost:30081`, `30082`, `30085`, `30069`, `30050` inaccessibles depuis Windows | WSL s'est mis en veille et a arrêté `minikube` | Dans WSL : `minikube start` *(le conteneur `minikube-port-proxy` reprend le relais tout seul dès que `minikube` est démarré)* |
| `kubectl` affiche `connection refused` ou `kubeconfig: Misconfigured` | Changement de port local après redémarrage Minikube | Dans WSL : `minikube update-context` |
| Jenkins échoue sur un job Kubernetes après redémarrage | L'IP ou le port du conteneur Minikube a changé dans `kubeconfig-jenkins.yml` | Relancer `sudo ansible-playbook ~/Dominique/"Projet CICD"/legeni-webapp/ansible/provision.yml` puis recharger le credential `kubeconfig` |
| `ansible-playbook` ignore `ansible.cfg` | Exécution depuis `/mnt/c/Dominique` (`0777`) | Toujours exécuter depuis `~/Dominique` après `chmod -R go-w ~/Dominique` |
| `Permission denied` sur `/tmp/.vault_pass` ou fichier Vault | Fichier `.vault_pass` resté sous `/mnt/c` sans `chmod 600` | Copier le mot de passe Vault sous `/tmp/.vault_pass` et faire `chmod 600 /tmp/.vault_pass` |
