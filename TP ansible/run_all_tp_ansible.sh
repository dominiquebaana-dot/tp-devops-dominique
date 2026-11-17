#!/bin/bash
# ==============================================================================
# SCRIPT MAÎTRE TOUT-EN-UN : EXÉCUTION COMPLÈTE DES TPs ANSIBLE (TP 5.1 à TP 5.6)
# Inclut le lab 3 nœuds (web1, web2, db1), tous les défis et Ansible + Kubernetes
# Usage : bash "TP ansible/run_all_tp_ansible.sh" [all|5.1|5.2|5.3|5.4|5.5|5.6]
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LAB_DIR="$SCRIPT_DIR/lab"
APP_DIR="$ROOT_DIR/app-fil-rouge"
LOG_FILE="$SCRIPT_DIR/logs_execution_tp_ansible.txt"
TARGET_TP="${1:-all}"

find "$SCRIPT_DIR" -type f \( -name "*.sh" -o -name "*.yml" -o -name "*.yaml" -o -name "*.j2" -o -name "*.ini" -o -name "*.cfg" -o -name "*.md" \) -exec sed -i 's/\r$//' {} + 2>/dev/null || true

exec > >(tee "$LOG_FILE") 2>&1

VAULT_PASS_TMP="/tmp/.tp_ansible_vault_pass_$$"
echo "LegeniAnsibleVault2026!" > "$VAULT_PASS_TMP"
chmod 600 "$VAULT_PASS_TMP"
trap 'rm -f "$VAULT_PASS_TMP"' EXIT

echo "=============================================================================="
echo " DÉMARRAGE DU PARCOURS AUTOMATISÉ TP ANSIBLE 5.1 À 5.6 ($(date))"
echo " Dossier lab : $LAB_DIR"
echo "=============================================================================="

ensure_vault_ready() {
    cd "$LAB_DIR"
    if [ ! -f "vars/wordpress_secrets.yml" ] || ! head -n 1 "vars/wordpress_secrets.yml" 2>/dev/null | grep -q '^\$ANSIBLE_VAULT'; then
        cp vars/wordpress_secrets.yml.exemple vars/wordpress_secrets.yml
        ansible-vault encrypt vars/wordpress_secrets.yml --vault-password-file "$VAULT_PASS_TMP"
    fi
}

ensure_lab_up() {
    cd "$LAB_DIR"
    mkdir -p keys
    local need_build=0
    if [ ! -f "keys/id_ansible" ]; then
        ssh-keygen -t ed25519 -f keys/id_ansible -N ""
        need_build=1
    fi
    chmod 600 keys/id_ansible
    chmod 644 keys/id_ansible.pub

    local all_ssh_ready=1
    if [ "$need_build" -eq 1 ]; then
        all_ssh_ready=0
    else
        for port in 2221 2222 2223; do
            if ! ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=2 \
                   -i keys/id_ansible -p "$port" ansible@127.0.0.1 hostname >/dev/null 2>&1; then
                all_ssh_ready=0
                break
            fi
        done
    fi
    if [ "$all_ssh_ready" -eq 1 ]; then
        return 0
    fi

    if [ "$need_build" -eq 1 ] || ! docker image inspect legeni/ansible-node:24.04 >/dev/null 2>&1; then
        docker compose build
        docker compose up -d --force-recreate
    else
        docker compose up -d
        local host_pub container_pub
        host_pub=$(cat keys/id_ansible.pub)
        container_pub=$(docker compose exec -T web1 cat /home/ansible/.ssh/authorized_keys 2>/dev/null || true)
        if [ "$host_pub" != "$container_pub" ]; then
            docker compose build
            docker compose up -d --force-recreate
        fi
    fi
    echo "Attente de disponibilité SSH des 3 nœuds (web1:2221, web2:2222, db1:2223)..."
    for port in 2221 2222 2223; do
        READY=0
        for i in $(seq 1 40); do
            if ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=2 \
                   -i keys/id_ansible -p "$port" ansible@127.0.0.1 hostname >/dev/null 2>&1; then
                READY=1
                break
            fi
            sleep 2
        done
        if [ "$READY" -ne 1 ]; then
            echo "❌ Timeout SSH sur le port $port"
            exit 1
        fi
    done
    ssh -o StrictHostKeyChecking=no -i keys/id_ansible -p 2221 ansible@127.0.0.1 hostname
}

run_tp5_1() {
    echo ""
    echo "=============================================================================="
    echo " TP 5.1 : LAB 3 NŒUDS, INVENTAIRES INI/YAML, COMMANDES AD-HOC & IDEMPOTENCE"
    echo "=============================================================================="
    ensure_lab_up
    cd "$LAB_DIR"

    echo "--- Inventaire INI et équivalent YAML (inventory.yml) ---"
    ansible-inventory --graph
    ansible-inventory -i inventory.yml --graph
    ansible-inventory --host web1

    echo "--- Étape 4 : Commandes ad-hoc ---"
    ansible all -m ping
    ansible web -m command -a "uptime"
    ansible db1 -m shell -a "df -h / | tail -1"
    ansible all -m setup -a "filter=ansible_distribution*"
    ansible all -m setup -a "filter=ansible_memtotal_mb"

    echo "--- Administration & Preuve d'idempotence (Étape 5) ---"
    ansible web -b -m apt -a "name=tree state=present update_cache=yes"
    ansible web -b -m apt -a "name=tree state=present update_cache=yes"
    ansible all -b -m user -a "name=stagiaire shell=/bin/bash"
    ansible all -b -m user -a "name=stagiaire shell=/bin/bash"
    ansible all -b -m copy -a "content='Serveur géré par Ansible\n' dest=/etc/motd mode=0644"
    ansible web1 -m command -a "cat /etc/motd"

    echo "--- Comparaison module vs shell (non idempotent) ---"
    ansible web1 -m shell -a "echo ligne >> /tmp/fichier_tp51.txt"
    ansible web1 -m shell -a "echo ligne >> /tmp/fichier_tp51.txt"
    ansible web1 -m shell -a "wc -l /tmp/fichier_tp51.txt"

    echo "--- Étape 6 : Ciblage fin ---"
    ansible 'web:!web2' -m ping
    ansible 'lab:&web' -m ping
    ansible all -m ping --limit db1

    echo "--- Défi TP 5.1 : Noyau, suppression stagiaire, alias ll idempotent ---"
    ansible all -m setup -a "filter=ansible_kernel"
    ansible all -b -m user -a "name=stagiaire state=absent remove=yes"
    ansible all -m lineinfile -a "path=/home/ansible/.bashrc line=\"alias ll='ls -alF'\""
    ansible all -m lineinfile -a "path=/home/ansible/.bashrc line=\"alias ll='ls -alF'\""
}

run_tp5_2() {
    echo ""
    echo "=============================================================================="
    echo " TP 5.2 : PREMIER PLAYBOOK NGINX, TEMPLATES, HANDLERS, DIFF, DÉRIVE & DÉFI"
    echo "=============================================================================="
    ensure_lab_up
    cd "$LAB_DIR"

    ansible-playbook nginx.yml --syntax-check
    ansible-playbook nginx.yml --list-tasks
    ansible-playbook nginx.yml --check || true

    echo "--- 1er passage (installation + configuration + Défi status port 8090) ---"
    ansible-playbook nginx.yml

    echo "--- 2e passage (idempotence : changed=0 attendu) ---"
    ansible-playbook nginx.yml

    echo "--- Vérification HTTP des pages web1 (:8001) et web2 (:8002) ---"
    curl -s http://127.0.0.1:8001 | grep -E "<h1>|Serveur :"
    curl -s http://127.0.0.1:8002 | grep -E "<h1>|Serveur :"

    echo "--- Étape 6 : Dérive de configuration (PIRATE) et correction automatique ---"
    ansible web1 -b -m shell -a "echo PIRATE > /var/www/html/index.html"
    echo "Contenu altéré sur web1 : $(curl -s http://127.0.0.1:8001)"
    ansible-playbook nginx.yml --diff
    curl -s http://127.0.0.1:8001 | grep "<h1>"
}

run_tp5_3() {
    echo ""
    echo "=============================================================================="
    echo " TP 5.3 : VARIABLES, FACTS, BOUCLES, CONDITIONS, TAGS, BLOCK/RESCUE & DÉFI"
    echo "=============================================================================="
    ensure_lab_up
    cd "$LAB_DIR"

    ansible-inventory --host web1 | grep -A2 page_title
    ansible-inventory --host web2 | grep -A2 page_title

    ansible-playbook variables.yml

    echo "--- Étape 3 : Surcharge -e en ligne de commande ---"
    ansible-playbook variables.yml -e "page_title='Maintenance ce soir'" --limit web
    curl -s http://127.0.0.1:8001 | grep "<h1>"
    ansible-playbook variables.yml --limit web

    echo "--- Étape 4 : Variables magiques & facts ---"
    ansible web1 -m debug -a "var=group_names"
    ansible web1 -m debug -a "var=hostvars['db1']['ansible_port']"

    echo "--- Étape 5 : Exécution sélective par tags ---"
    ansible-playbook variables.yml --list-tags
    ansible-playbook variables.yml --tags utilisateurs

    echo "--- Vérification nginx absent sur db1 ---"
    if ansible db1 -m command -a "which nginx" 2>/dev/null; then
        echo "❌ ERREUR : nginx ne devrait pas être installé sur db1"
        exit 1
    else
        echo "✅ OK : nginx n'est pas installé sur db1"
    fi

    echo "--- Défi TP 5.3 : Playbook utilisateurs.yml (groupes, clés SSH, sudoers sur db) ---"
    ansible-playbook utilisateurs.yml
    ansible lab -m command -a "id dev1"
    ansible db1 -b -m command -a "cat /etc/sudoers.d/ops1"
    ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i keys/id_ansible -p 2223 ops1@127.0.0.1 "sudo whoami"
}

run_tp5_4() {
    echo ""
    echo "=============================================================================="
    echo " TP 5.4 : RÔLES REUTILISABLES (docker & webapp), VARIABILISATION & DÉFI"
    echo "=============================================================================="
    ensure_lab_up
    cd "$LAB_DIR"

    echo "--- Étape 7 : Installation de geerlingguy.docker via requirements.yml ---"
    ansible-galaxy install -r requirements.yml
    ansible-galaxy role list

    echo "--- Préparation Docker dans les nœuds web1/web2 & chargement des images locales ---"
    if ! docker image inspect legeni-webapp:1.0.0 >/dev/null 2>&1; then
        docker build --build-arg APP_VERSION=1.0.0 -t legeni-webapp:1.0.0 "$APP_DIR"
    fi
    if ! docker image inspect legeni-webapp:2.0.0 >/dev/null 2>&1; then
        docker build --build-arg APP_VERSION=2.0.0 -t legeni-webapp:2.0.0 "$APP_DIR"
    fi

    ansible-playbook docker.yml
    docker save legeni-webapp:1.0.0 legeni-webapp:2.0.0 | docker compose exec -T web1 docker load
    docker save legeni-webapp:1.0.0 legeni-webapp:2.0.0 | docker compose exec -T web2 docker load

    echo "--- Étape 4 & 5 : Déploiement via site.yml (1er passage) ---"
    ansible-playbook site.yml

    echo "--- Preuve d'idempotence site.yml (2e passage : changed=0 attendu) ---"
    ansible-playbook site.yml

    echo "web1 (:8101) : $(curl -sf http://127.0.0.1:8101/api/info)"
    echo "web2 (:8102) : $(curl -sf http://127.0.0.1:8102/api/info)"

    echo "--- Étape 6 : Mise à jour ciblée web1=2.0.0 et test version inexistante 9.9.9 ---"
    ansible-playbook site.yml -e webapp_version=2.0.0 --limit web1
    set +e
    ansible-playbook site.yml -e webapp_version=9.9.9 --limit web1
    RC_999=$?
    set -e
    echo "Code retour version inexistante 9.9.9 (échec attendu != 0) : $RC_999"
    echo "Vérification que web1 répond toujours sans coupure : $(curl -sf http://127.0.0.1:8101/api/info)"
    ansible-playbook site.yml --limit web1

    echo "--- Défi TP 5.4 : Test du rôle (tests/test_webapp.yml) et webapp_state=absent ---"
    ansible-playbook tests/test_webapp.yml
    ansible-playbook site.yml -e webapp_state=absent
    ansible web -b -m command -a "docker volume ls -f name=legeni_redis"
    ansible-playbook site.yml -e webapp_state=present
}

run_tp5_5() {
    echo ""
    echo "=============================================================================="
    echo " TP 5.5 : ANSIBLE VAULT, WORDPRESS + MARIADB & DÉFI SAUVEGARDE"
    echo "=============================================================================="
    ensure_lab_up
    ensure_vault_ready
    cd "$LAB_DIR"

    head -n 1 vars/wordpress_secrets.yml

    echo "--- Test de rejet d'un mot de passe < 12 caractères ---"
    set +e
    ansible-playbook wordpress.yml --vault-password-file "$VAULT_PASS_TMP" -e mysql_password=court
    RC_WEAK=$?
    set -e
    echo "Code retour mot de passe faible (rejet attendu != 0) : $RC_WEAK"

    echo "--- 1er déploiement WordPress sur db1 (:8103) ---"
    ansible-playbook wordpress.yml --vault-password-file "$VAULT_PASS_TMP"

    echo "Code HTTP WordPress (:8103/wp-admin/install.php) : $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8103/wp-admin/install.php)"
    ansible db1 -b -m command -a "stat -c '%a %U' /opt/wordpress/docker-compose.yml"
    docker compose exec -T db1 docker inspect wordpress-db-1 --format '{{.Created}}'

    echo "--- 2e déploiement : déclenchement de la sauvegarde mariadb-dump (Défi TP 5.5) ---"
    ansible-playbook wordpress.yml --vault-password-file "$VAULT_PASS_TMP"
    ansible db1 -b -m command -a "ls -lh /opt/wordpress/backups/"
    docker compose exec -T db1 docker inspect wordpress-db-1 --format '{{.Created}}'
}

run_tp5_6() {
    echo ""
    echo "=============================================================================="
    echo " TP 5.6 : ANSIBLE + KUBERNETES (ROLLBACK AUTO & WORDPRESS PLAYBOOK)"
    echo "=============================================================================="
    ensure_vault_ready
    cd "$LAB_DIR"

    if ! minikube status >/dev/null 2>&1; then
        minikube start --driver=docker --preload=false --cpus=2 --memory=4096
        minikube addons enable metrics-server || true
        minikube addons enable ingress || true
    fi

    if ! docker image inspect legeni-webapp:1.0.0 >/dev/null 2>&1; then
        docker build --build-arg APP_VERSION=1.0.0 -t legeni-webapp:1.0.0 "$APP_DIR"
    fi
    if ! docker image inspect legeni-webapp:2.0.0 >/dev/null 2>&1; then
        docker build --build-arg APP_VERSION=2.0.0 -t legeni-webapp:2.0.0 "$APP_DIR"
    fi
    minikube image load legeni-webapp:1.0.0
    minikube image load legeni-webapp:2.0.0

    export REDIS_PASSWORD
    REDIS_PASSWORD=$(openssl rand -hex 16)

    echo "--- Nettoyage préalable de legeni-staging / legeni-prod pour garantir un Secret Redis neuf ---"
    kubectl delete namespace legeni-staging legeni-prod --timeout=120s 2>/dev/null || true
    kubectl wait --for=delete namespace/legeni-staging --timeout=120s 2>/dev/null || true
    kubectl wait --for=delete namespace/legeni-prod --timeout=120s 2>/dev/null || true

    echo "--- Étape 3 : Déploiement staging (1.0.0) ---"
    ansible-playbook k8s_deploy.yml -e target_env=staging -e webapp_image=legeni-webapp -e app_version=1.0.0

    echo "--- Étape 4 : Déploiement prod (1.0.0 -> 2.0.0) ---"
    ansible-playbook k8s_deploy.yml -e target_env=prod -e webapp_image=legeni-webapp -e app_version=1.0.0
    ansible-playbook k8s_deploy.yml -e target_env=prod -e webapp_image=legeni-webapp -e app_version=2.0.0
    kubectl rollout history deployment/webapp -n legeni-prod

    echo "--- Étape 5 : Déploiement raté 9.9.9 -> Rollback automatique vers 2.0.0 ---"
    set +e
    ansible-playbook k8s_deploy.yml -e target_env=prod -e webapp_image=legeni-webapp -e app_version=9.9.9
    RC_ROLLBACK=$?
    set -e
    echo "Code retour attendu (échec détecté et rollback effectué) : $RC_ROLLBACK"
    kubectl get deploy webapp -n legeni-prod -o wide

    echo "--- Étape 6 : Vérification d'idempotence prod (2.0.0) ---"
    ansible-playbook k8s_deploy.yml -e target_env=prod -e webapp_image=legeni-webapp -e app_version=2.0.0

    echo "--- Étape 7 : Déploiement WordPress sur K8s (wordpress-playbook.yaml, namespace blog) ---"
    kubectl delete namespace blog --timeout=60s 2>/dev/null || true
    ansible-playbook wordpress-playbook.yaml --vault-password-file "$VAULT_PASS_TMP"
    kubectl get all,pvc,secret -n blog
    kubectl delete namespace blog legeni-staging legeni-prod --timeout=180s
}

case "$TARGET_TP" in
    5.1) run_tp5_1 ;;
    5.2) run_tp5_2 ;;
    5.3) run_tp5_3 ;;
    5.4) run_tp5_4 ;;
    5.5) run_tp5_5 ;;
    5.6) run_tp5_6 ;;
    all)
        run_tp5_1
        run_tp5_2
        run_tp5_3
        run_tp5_4
        run_tp5_5
        run_tp5_6
        ;;
    *)
        echo "Usage: $0 [all|5.1|5.2|5.3|5.4|5.5|5.6]"
        exit 1
        ;;
esac

echo ""
echo "=============================================================================="
echo " TOUS LES TPs ANSIBLE (5.1 À 5.6) SONT VALIDÉS AVEC SUCCÈS !"
echo " Traces : $LOG_FILE"
echo " Compte-rendu : $SCRIPT_DIR/COMPTE_RENDU_TP_ANSIBLE.md"
echo "=============================================================================="
