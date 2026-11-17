# Compte-Rendu Complet – Travaux Pratiques Jenkins (TP 3.1 à TP 3.8)

> **Module 3 – Intégration et Déploiement Continus (CI/CD) avec Jenkins**
> Ce document regroupe l'ensemble des réponses aux questions, explications d'architecture, scripts et `Jenkinsfile` pour les **TPs 3.1 à 3.8**.
> Tous les livrables techniques sont disponibles dans [`solutions/`](solutions/) et exécutables via [`run_all_tp_jenkins.sh`](run_all_tp_jenkins.sh).

---

## TP 3.1 : Installation reproductible de Jenkins en conteneur

### 1. Pourquoi utiliser une image personnalisée (`jenkins-docker/Dockerfile`) et `DOCKER_GID` ?
* **Problème de l'approche manuelle (`chmod 666 /var/run/docker.sock`) :** Installer des outils à la main dans un conteneur (`apt-get install`) disparaît dès que le conteneur est recréé. De plus, ouvrir `/var/run/docker.sock` en `666` donne les droits `root` sur l'hôte à n'importe quel processus ou utilisateur non privilégié de la machine.
* **Solution propre mise en œuvre :**
  1. Un [`Dockerfile`](jenkins-docker/Dockerfile) versionné hérite de `jenkins/jenkins:lts-jdk21` et pré-installe **Docker CLI + Compose + Buildx**, **kubectl**, **Ansible** (avec les collections `kubernetes.core` et `community.docker`) ainsi que les plugins listés dans [`plugins.txt`](jenkins-docker/plugins.txt).
  2. Le fichier `.env` transmet uniquement le GID du groupe `docker` de l'hôte (`DOCKER_GID=$(stat -c %g /var/run/docker.sock)`) via `group_add` dans [`docker-compose.yml`](jenkins-docker/docker-compose.yml).

### 2. Livrable réalisé
* Pipeline de vérification des outils : [`solutions/tp3.1/Jenkinsfile.verif-outils`](solutions/tp3.1/Jenkinsfile.verif-outils)

---

## TP 3.2 : Premier Job Freestyle paramétré (`build`)

### 1. Réponses aux questions
1. **Pourquoi un job de CI doit-il être idempotent (pouvoir être relancé N fois avec le même résultat) ?**
   * Parce qu'un pipeline CI est exécuté des dizaines de fois par jour à chaque commit. S'il échoue au 2ᵉ lancement parce qu'un conteneur du build précédent porte déjà le même nom (`Conflict. The container name "/legeni_website" is already in use`), le pipeline devient inutilisable. D'où l'utilisation systématique de `docker rm -f legeni_website 2>/dev/null || true` avant le `docker run`.
2. **Où se trouve physiquement l'espace de travail (*workspace*) du job ? Et sur quelle machine l'image est-elle construite ?**
   * Le workspace se trouve dans `/var/jenkins_home/workspace/<nom_du_job>` à l'intérieur du conteneur Jenkins, qui est persisté dans le volume nommé Docker `jenkins-docker_jenkins_home` sur l'hôte (`/var/lib/docker/volumes/...`).
   * L'image Docker est construite **sur le démon Docker de la machine hôte** (car le conteneur Jenkins partage le socket `/var/run/docker.sock` de l'hôte : architecture *Docker-outside-of-Docker* / DooD).
3. **Trois inconvénients d'un job Freestyle configuré uniquement dans l'interface web :**
   * **Aucune traçabilité / historique Git :** On ne sait pas qui a modifié une étape du job ni pourquoi, et on ne peut pas faire de `git revert`.
   * **Pas de revue de code (*Pull Request*) :** Impossible de faire relire les changements du pipeline par l'équipe avant de les appliquer.
   * **Non-portabilité :** Si le serveur Jenkins est perdu sans sauvegarde de `jenkins_home`, il faut recréer et reconfigurer tous les écrans à la main.

### 2. Solution du Défi TP 3.2 (`PORT` + `NETTOYER` gardant les 3 derniers builds)
* Script complet : [`solutions/tp3.2/build_freestyle.sh`](solutions/tp3.2/build_freestyle.sh)

---

## TP 3.3 : Test d'acceptance et Porte de Qualité (*Quality Gate*)

### 1. Réponses aux questions
1. **Pourquoi `curl http://localhost/` ne fonctionne-t-il pas depuis le script Jenkins ?**
   * Parce que le script s'exécute **à l'intérieur du conteneur `jenkins`**. Dans ce conteneur, `localhost` (`127.0.0.1`) désigne le conteneur Jenkins lui-même (où écoute seulement le port 8080 de Jenkins), et non la machine hôte ni le conteneur `restaurant-test`. En plaçant `restaurant-test` sur le même réseau Docker que `jenkins` (`--network ${JENKINS_NET}`), Jenkins le joint directement par son nom DNS `http://restaurant-test/`.
2. **Si l'étape de test échoue dans un job Freestyle, la dernière étape `docker rm -f` est-elle exécutée ?**
   * **Non.** Dans un job Freestyle, dès qu'une étape de build retourne un code d'erreur (`!= 0`), Jenkins interrompt immédiatement le job et n'exécute pas les étapes suivantes. Conséquence : le conteneur `restaurant-test` reste actif en arrière-plan. C'est ce que résout élégamment le bloc `post { always { ... } }` d'un `Jenkinsfile` (TP 3.5).
3. **Différence entre un test unitaire (`pytest`) et un test d'acceptance :**
   * Le **test unitaire** vérifie des fonctions isolées du code en mémoire (très rapide, quelques millisecondes, sans réseau ni serveur réel) → il doit s'exécuter **en premier** (*Fail Fast*) avant même de construire l'image finale.
   * Le **test d'acceptance** teste l'application empaquetée dans son conteneur final (serveur Gunicorn/Nginx démarré, requêtes HTTP réelles de bout en bout) → il s'exécute **après** le build de l'image et **avant** le `docker push`.
4. **Plugin HTTP Request vs `curl` dans un script shell :**
   * **Plugin HTTP Request :** Configuration graphique simple, mais dépend d'un plugin Jenkins spécifique et ne peut pas être testé en local hors de Jenkins.
   * **`curl` en script shell :** 100 % portable (fonctionne à l'identique sur le poste du développeur, dans Jenkins, GitLab CI ou GitHub Actions), versionnable et beaucoup plus flexible.

### 2. Solution du Défi TP 3.3 (Temps de réponse moyen < 500 ms sur 10 requêtes)
* Script complet : [`solutions/tp3.3/test_acceptance.sh`](solutions/tp3.3/test_acceptance.sh)

---

## TP 3.4 : Gestion de l'artefact, Credentials et Chaînage de jobs

### 1. Réponses aux questions
1. **Où Jenkins stocke-t-il le credential `dockerhub`, et sous quelle forme ?**
   * Il est stocké dans le fichier `/var/jenkins_home/credentials.xml`, **chiffré** (AES) à l'aide de la clé maîtresse de l'instance Jenkins située dans `/var/jenkins_home/secrets/master.key` et `hudson.util.Secret`. En console, Jenkins remplace automatiquement la valeur du secret par `****`.
2. **Pourquoi utiliser un tag unique (`1.0.12-3f9c2ab`) plutôt que `latest` ?**
   * Le tag `latest` est **muable** (il est écrasé à chaque nouveau build). En production, utiliser `latest` empêche de savoir quelle version exacte tourne, empêche de faire un rollback fiable vers le build précédent, et peut créer des incohérences si un nœud télécharge une nouvelle image `latest` au milieu d'un scaling. Un tag combinant `<version>.<build>-<git_sha>` garantit une **traçabilité totale et immuable** entre le conteneur en production, le build Jenkins et le commit Git.
3. **Combien de jobs, d'étapes et d'écrans de configuration manipulés depuis le TP 3.2, et temps de reconstruction si Jenkins est perdu ?**
   * On cumule déjà **4 jobs Freestyle** (`build`, `test-acceptance`, `artefact`, `deploy`), chacun avec ses paramètres, credentials, triggers SCM, étapes shell/HTTP Request et actions post-build (~15 écrans/formulaires graphiques). Si le serveur Jenkins est perdu sans sauvegarde de `jenkins_home`, tout reconfigurer à la main prend facilement **30 à 60 minutes** avec un risque élevé d'oubli — c'est précisément la motivation du **Pipeline as Code** (`Jenkinsfile` versionné dans Git au TP 3.5).

### 2. Livrables & Défi TP 3.4 (Tests d'acceptance + Trivy + Chaînage `deploy`)
* Script complet avec tests d'acceptance intégrés et scan Trivy : [`solutions/tp3.4/artefact_publish.sh`](solutions/tp3.4/artefact_publish.sh)
* Script du job chaîné `deploy` (Étape 9, port `8099`) : [`solutions/tp3.4/deploy_freestyle.sh`](solutions/tp3.4/deploy_freestyle.sh)

---

## TP 3.5 : Pipeline as Code (`Jenkinsfile`)

### 1. Réponses aux questions
1. **Rôle des blocs du `Jenkinsfile` déclaratif :**
   * `parameters` : Définit les paramètres saisissables au lancement du build (`DOCKERHUB_ID`, `PUSH`, `APP_COLOR`).
   * `environment` : Définit les variables d'environnement globales accessibles dans tous les stages (`IMAGE`, `VERSION`, `TEST_CONTAINER`, `CI_NETWORK`).
   * `options` : Configure le comportement global du pipeline (`timestamps()` pour horodater les logs, `timeout()` pour tuer un build bloqué, `buildDiscarder()` pour ne garder que les 10 derniers builds).
   * `post` : Définit les actions exécutées à la fin du pipeline selon l'état (`always` pour supprimer systématiquement le conteneur et le réseau de test même en cas de crash, `success`, `failure`).
2. **Pourquoi le test d'acceptance lance-t-il un conteneur `curlimages/curl` sur `$CI_NETWORK` ?**
   * Parce que le conteneur Jenkins n'est pas connecté à `$CI_NETWORK` et que publier un port sur l'hôte (`-p 5000:5000`) provoquerait des conflits si deux builds tournaient en même temps. En créant un réseau isolé par build (`ci-net-${BUILD_NUMBER}`) et en y lançant un conteneur éphémère `curlimages/curl`, le test est 100 % isolé et parallélisable.
3. **Que se passe-t-il si le stage `Tests unitaires` échoue ?**
   * Les stages suivants (`Build image`, `Test d'acceptance`, `Push Docker Hub`) sont immédiatement ignorés (*skipped*), aucune image défectueuse n'est produite ni poussée, et Jenkins exécute directement le bloc `post` (`always` puis `failure`).

### 2. Solution du Défi TP 3.5 (`APP_COLOR` vérifié dans le stage d'acceptance)
* Pipeline complet : [`solutions/tp3.5/Jenkinsfile.tp35`](solutions/tp3.5/Jenkinsfile.tp35)

---

## TP 3.6 : Pipeline Multibranch, Pull Requests et Webhooks

### 1. Fonctionnement mis en place
* Le pipeline [`solutions/tp3.6/Jenkinsfile.multibranch`](solutions/tp3.6/Jenkinsfile.multibranch) adapte dynamiquement la variable `VERSION` selon `env.BRANCH_NAME` :
  * Sur `main` → `1.0.<BUILD_NUMBER>` et exécution du stage `Push Docker Hub` (`when { branch 'main' }`).
  * Sur `feature/*` ou `PR-*` → `<nom-branche>-<BUILD_NUMBER>` et le stage `Push Docker Hub` est automatiquement ignoré (*skipped*).

---

## TP 3.7 : Qualité du code, Tests parallèles et Quality Gates

### 1. Réponses aux questions
1. **Pourquoi publier les rapports (`junit`, `recordCoverage`, `recordIssues`) dans un bloc `post { always { ... } }` plutôt qu'à la fin de `steps` ?**
   * Si un test unitaire échoue ou si la couverture est inférieure à 80 %, la commande `pytest` renvoie un code retour `!= 0` et interrompt immédiatement le bloc `steps`. Si `junit` était placé à la suite dans `steps`, il ne serait **jamais exécuté** lors des échecs — or c'est précisément quand un test échoue qu'on a besoin de consulter le rapport dans Jenkins ! Le bloc `post { always { ... } }` garantit que les rapports sont publiés même si `pytest` ou `flake8` échoue.
2. **Différence entre `UNSTABLE` (jaune) et `FAILURE` (rouge) :**
   * **FAILURE (rouge) :** Une erreur bloquante s'est produite (erreur de compilation, commande shell retournant `!= 0`, seuil de sécurité Trivy franchi).
   * **UNSTABLE (jaune) :** Le build est allé au bout mais des seuils de qualité non fatals ont été signalés (par ex. le plugin `junit` marque un build en `UNSTABLE` s'il trouve des tests en échec dans le XML alors que l'étape shell n'a pas interrompu le pipeline).

### 2. Solution du Défi TP 3.7 (Stage parallèle `Secrets` avec `gitleaks`)
* Pipeline complet incluant les 4 branches parallèles (`Tests unitaires`, `Lint Python`, `Lint Dockerfile`, `Secrets Gitleaks`) : [`solutions/tp3.7/Jenkinsfile.qualite`](solutions/tp3.7/Jenkinsfile.qualite)

---

## TP 3.8 : Déploiement Continu, Approbation Manuelle et Rollback Automatique

### 1. Réponses aux questions
1. **Différence entre *Continuous Delivery* (Livraison Continue) et *Continuous Deployment* (Déploiement Continu) :**
   * **Continuous Delivery (Livraison Continue) :** Chaque commit validé sur `main` est déployé automatiquement en *staging* et prêt à partir en production, mais le passage en **production** requiert une **décision humaine** (clic sur le bouton `input` *« Déployer »*). **C'est ce qu'implémente le pipeline du TP 3.8.**
   * **Continuous Deployment (Déploiement Continu) :** Toute la chaîne jusqu'à la **production** est 100 % automatique sans aucune intervention humaine. Pour passer en *Continuous Deployment*, il suffirait de supprimer le stage `Validation production` (`input`).
2. **Pourquoi l'option `disableConcurrentBuilds()` est-elle indispensable en CD ?**
   * Si deux commits sont poussés à quelques secondes d'intervalle sur `main`, deux exécutions du pipeline pourraient tenter de déployer deux versions différentes en même temps sur l'environnement `staging` ou `prod` (*race condition*), ou le build n°1 (plus lent) pourrait écraser la version du build n°2 plus récent. `disableConcurrentBuilds()` met les builds en file d'attente.
3. **Limites du rollback d'image vis-à-vis de la base de données :**
   * Le rollback redéploie le conteneur applicatif de la version `N-1`, mais **ne restaure pas l'état de la base de données**. Si la version `N` avait exécuté une migration destructive du schéma (suppression/renommage d'une colonne), l'ancienne image `N-1` plantera face au nouveau schéma. D'où la règle : des migrations de schéma rétro-compatibles (*expand and contract*) et une sauvegarde automatisée du volume avant déploiement (cf. TP 2.7 / TP 4.6).

### 2. Livrable réalisé
* Pipeline complet CI/CD avec rollback automatique : [`solutions/tp3.8/Jenkinsfile.cd`](solutions/tp3.8/Jenkinsfile.cd)
