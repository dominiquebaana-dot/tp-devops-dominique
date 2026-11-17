# Compte-Rendu Complet – Travaux Pratiques Ansible (TP 5.1 à TP 5.6)

> **Module 5 – Gestion de Configuration et Infrastructure as Code avec Ansible**
> Ce document regroupe l'ensemble des réponses aux questions, les tableaux complétés, les explications d'idempotence et les solutions des défis pour les **TPs 5.1 à 5.6**.
> Tous les playbooks, rôles et inventaires sont dans [`lab/`](lab/) et exécutables via [`run_all_tp_ansible.sh`](run_all_tp_ansible.sh).

---

## TP 5.1 : Mise en place du lab, inventaire et commandes ad-hoc

### 1. Réponses aux questions
1. **Quels sont les groupes ? Que contient le groupe `lab` ?**
   * Les groupes définis dans [`lab/inventory.ini`](lab/inventory.ini) (et son équivalent YAML [`lab/inventory.yml`](lab/inventory.yml)) sont : `web` (`web1`, `web2`), `db` (`db1`), `wordpress_servers` (`db1`), et `lab` (`[lab:children]` regroupe les sous-groupes `web` et `db`, donc les 3 hôtes `web1`, `web2`, `db1`).
2. **Où est définie la clé SSH utilisée ? Et l'utilisateur ?**
   * Dans la section `[lab:vars]` de l'inventaire : `ansible_user=ansible` et `ansible_ssh_private_key_file=keys/id_ansible`.
3. **Pourquoi `host_key_checking = False` est acceptable en lab mais pas en production ?**
   * Désactiver la vérification d'empreinte SSH facilite les tests sur des conteneurs éphémères recréés fréquemment. En production, cela exposerait aux attaques *Man-in-the-Middle* (usurpation de serveur sans alerte).
4. **Pourquoi préférer les modules (`apt`, `user`, `copy`, `lineinfile`…) aux modules `command`/`shell` ?**
   * Les modules déclaratifs vérifient d'abord l'état cible avant d'agir : ils sont **idempotents** (`CHANGED` uniquement si nécessaire, sinon `OK`), portables et structurés. `command`/`shell` réexécutent systématiquement la commande (`CHANGED` à chaque passage) et peuvent dupliquer des données (ex. `echo ligne >> /tmp/fichier.txt`).

### 2. Défi & Vérifications
* Inventaire YAML équivalent créé dans [`lab/inventory.yml`](lab/inventory.yml) et validé avec `ansible-inventory -i inventory.yml --graph`.
* Défi ad-hoc validé : `ansible_kernel`, suppression de `stagiaire`, et ajout idempotent de `alias ll='ls -alF'` dans `/home/ansible/.bashrc`.

---

## TP 5.2 : Premier playbook – Nginx, templates et handlers

### 1. Fonctionnement & Défi
* [`lab/nginx.yml`](lab/nginx.yml) déploie Nginx sur `web` (`web1:8001`, `web2:8002`), génère `/var/www/html/index.html` depuis [`lab/templates/index.html.j2`](lab/templates/index.html.j2), déclenche le handler `Recharger nginx` via `notify` uniquement en cas de modification, et corrige toute dérive manuelle (`PIRATE`).
* **Défi TP 5.2 intégré** : déploie `/etc/nginx/conf.d/status.conf` (`stub_status;` sur le port `8090`), valide la syntaxe par `nginx -t` (`changed_when: false`), applique le rechargement immédiat (`meta: flush_handlers`), puis contrôle `http://127.0.0.1:8090/nginx_status` via `ansible.builtin.uri`.

### 2. Vérifications
- [x] 2ᵉ exécution de `nginx.yml` : `changed=0`
- [x] Pages `web1:8001` et `web2:8002` accessibles avec leurs facts (`inventory_hostname`, RAM, CPU)
- [x] Dérive `PIRATE` détectée et corrigée automatiquement avec `--diff`

---

## TP 5.3 : Variables, facts, boucles et conditions

### 1. Tableau Notion / Tâche (`lab/variables.yml`)

| Tâche dans `variables.yml` | Notion Ansible mise en œuvre |
| :--- | :--- |
| Afficher quelques facts | Facts système (`ansible_facts['distribution']`, `memtotal_mb`) |
| Installer les paquets communs | Liste issue de `group_vars` (`web.yml` vs `db.yml`) |
| Créer les groupes | `loop` + filtres Jinja2 `map(attribute='groupe') \| unique` |
| Créer les utilisateurs | `loop` sur une liste de dictionnaires + `loop_control.label` |
| Installer nginx uniquement… | Condition `when` combinant `ansible_facts` et `group_names` |
| Mesurer l'espace disque libre | `register` + `changed_when: false` |
| Publier la page | Template Jinja2 + variable surchargée par `host_vars/web2.yml` |

### 2. Améliorations & Défi
* [`lab/variables.yml`](lab/variables.yml) inclut les `tags: [utilisateurs]` et le bloc `block / rescue / always` (fondation du rollback automatique).
* **Défi TP 5.3 ([`lab/utilisateurs.yml`](lab/utilisateurs.yml))** : gère les comptes de `comptes` dans [`lab/group_vars/all.yml`](lab/group_vars/all.yml) (`present`/`absent`), déploie la clé SSH via `ansible.posix.authorized_key`, et configure `/etc/sudoers.d/ops1` (`visudo -cf %s`) **uniquement** sur les serveurs du groupe `db`.

---

## TP 5.4 : Les rôles – Docker et Application Fil Rouge

### 1. Réponses aux questions
1. **Comment l'URL du dépôt Docker s'adapte-t-elle à la distribution et à l'architecture ?**
   * `roles/docker/tasks/main.yml` utilise `ansible_facts['distribution'] | lower`, `ansible_facts['distribution_release']` et une expression conditionnelle sur `ansible_facts['architecture']` (`amd64` pour `x86_64`, sinon `arm64`).
2. **Pourquoi installer `python3-docker` / `python3-requests` sur les nœuds ?**
   * Les modules Ansible `community.docker.*` et `uri` s'exécutent en Python **sur le nœud cible** et s'appuient sur le SDK Docker Python (`docker` / `requests`) pour dialoguer avec le socket `/var/run/docker.sock`.
3. **Que se passe-t-il au 2ᵉ passage si Docker est déjà installé ?**
   * Toutes les tâches retournent `ok` (`changed=0`) : aucune clé n'est réécrite, aucun paquet n'est réinstallé.
4. **Que se passe-t-il avec `-e webapp_version=9.9.9` ? Le service est-il coupé ?**
   * L'image `9.9.9` étant introuvable au téléchargement, la tâche échoue **avant** de remplacer le conteneur existant : le conteneur précédent reste actif et l'application continue de répondre sans coupure.
5. **Comparaison `geerlingguy.docker` (Galaxy) vs notre rôle `docker` :**
   * `geerlingguy.docker` supporte de multiples distributions (Debian, Ubuntu, RHEL, Rocky, Fedora, etc.), gère de nombreuses variables (miroirs, options du daemon, utilisateurs, compose v1/v2, rootless), alors que notre rôle `docker` est minimaliste, ciblé Debian/Ubuntu et facile à auditer en quelques dizaines de lignes.

### 2. Livrables & Défi
* [`lab/host_vars/web2.yml`](lab/host_vars/web2.yml) complété (`preprod`, `#bf8700`, `2.0.0`).
* [`lab/requirements.yml`](lab/requirements.yml) avec `geerlingguy.docker:7.4.1`, `community.docker`, `kubernetes.core`.
* **Défi TP 5.4** : variable `webapp_state` (`present`/`absent`) ajoutée dans [`lab/roles/webapp/`](lab/roles/webapp/tasks/main.yml) et test automatisé dans [`lab/tests/test_webapp.yml`](lab/tests/test_webapp.yml) vérifiant `/api/info` et l'absence de port publié sur `redis`.

---

## TP 5.5 : Secrets avec Ansible Vault – Déploiement WordPress

### 1. Réponse à la question & Comportement observé
* **Où placer `no_log: true` ?**
  * Sur toutes les tâches qui manipulent ou affichent des variables sensibles en argument, en `content` ou en sortie (`template` générant `docker-compose.yml`, `docker_container_exec` utilisant `$MARIADB_ROOT_PASSWORD`, `copy` écrivant le dump SQL, `debug` éventuels), afin qu'aucun secret n'apparaisse même avec `-v`.
* **Faux positif d'idempotence `community.docker` 3.7 :**
  * Avec `community.docker` `3.7.0`, `docker_compose_v2` signale `changed` au 2ᵉ passage bien que `docker inspect wordpress-db-1 --format '{{.Created}}'` conserve exactement la même date de création (aucune recréation de conteneur).

### 2. Livrables & Défi
* [`lab/wordpress.yml`](lab/wordpress.yml) intègre la validation de longueur des mots de passe (`>= 12`), les droits `0600 root` sur `/opt/wordpress/docker-compose.yml`, et le **Défi TP 5.5** : sauvegarde `mariadb-dump` pré-déploiement dans `/opt/wordpress/backups/wordpress_*.sql` (`0600`) avec rétention des 5 plus récentes.

---

## TP 5.6 : Ansible pilote Kubernetes – Déploiement multi-environnement & Rollback

### 1. Réponses aux questions
* **Quelles tâches sont `changed` au 2ᵉ passage à version identique (`2.0.0`) et pourquoi `changed_when: false` sur le smoke test ?**
  * Au 2ᵉ passage de [`lab/k8s_deploy.yml`](lab/k8s_deploy.yml) à version identique, **aucune** ressource Kubernetes ne change (`changed=0`) car l'annotation `checksum/config` et le tag `app_version` sont inchangés. Le smoke test (`k8s_exec`) est une lecture HTTP (`GET /api/info`) qui ne modifie pas l'état du cluster : sans `changed_when: false`, Ansible le compterait à tort comme `changed` à chaque exécution.
* **Jinja2 vs `kubernetes.core.kustomize` :**
  * **Templates Jinja2** (`templates/k8s/webapp.yml.j2`) : idéaux quand une variable unique (`app_version`, `app_color`, `readiness_path`) est injectée dynamiquement par Jenkins/Ansible en un seul fichier paramétré.
  * **Kustomize** (`lookup('kubernetes.core.kustomize', ...)`): idéal pour garder du YAML pur 100 % natif Kubernetes testable sans Ansible (`kubectl apply -k`), avec surcharge par environnement via patches et `configMapGenerator`.

### 2. Livrables Étape 7 & Vérifications
* [`lab/k8s_deploy.yml`](lab/k8s_deploy.yml) : staging (`1.0.0`), prod (`1.0.0` $\rightarrow$ `2.0.0`), échec `9.9.9` avec rollback automatique vers `2.0.0`, et idempotence vérifiés.
* [`lab/wordpress-playbook.yaml`](lab/wordpress-playbook.yaml) + [`lab/k8s-wordpress/`](lab/k8s-wordpress/) : déploie WordPress + MySQL dans le namespace `blog` à partir de `vars/wordpress_secrets.yml` chiffré par Ansible Vault.
