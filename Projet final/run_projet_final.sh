#!/bin/bash
# ==============================================================================
# RUNNER DU PROJET FINAL IC GROUP (Legeni Academy + Odoo + pgAdmin)
# Supporte à la fois le déploiement Kubernetes et le provisionnement Ansible
# Usage : ./run_projet_final.sh [all|k8s|ansible]
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOLUTION_DIR="$SCRIPT_DIR/solution"
TARGET="${1:-all}"
LOG_FILE="$SCRIPT_DIR/logs_execution_projet_final.txt"

# Nettoyage des fins de ligne résiduelles
find "$SCRIPT_DIR" -type f \( -name "*.sh" -o -name "Jenkinsfile*" -o -name "Dockerfile*" -o -name "*.yml" -o -name "*.yaml" -o -name "*.j2" -o -name "*.ini" -o -name "*.cfg" -o -name "*.txt" \) -exec sed -i 's/\r$//' {} + 2>/dev/null || true

exec > >(tee "$LOG_FILE") 2>&1

run_ansible_check() {
    echo ""
    echo "=============================================================================="
    echo " 1. VALIDATION ET SYNTAXE DU PROVISIONNEMENT ANSIBLE (deploy_icgroup.yml)"
    echo "=============================================================================="
    cd "$SOLUTION_DIR/ansible"
    ansible-playbook --syntax-check deploy_icgroup.yml
    echo "✅ Syntaxe Ansible deploy_icgroup.yml validée."
}

run_k8s_deploy() {
    echo ""
    echo "=============================================================================="
    echo " 2. DÉPLOIEMENT DU PROJET FINAL IC GROUP SUR KUBERNETES (MINIKUBE)"
    echo "=============================================================================="
    if ! minikube status >/dev/null 2>&1; then
        echo "Démarrage de Minikube..."
        TOTAL_MEM_MB=$(free -m | awk '/^Mem:/{print $2}')
        MK_MEM=$([ "$TOTAL_MEM_MB" -ge 6144 ] && echo 4096 || echo 2560)
        MK_CPUS=$([ "$(nproc)" -ge 2 ] && echo 2 || echo 1)
        minikube start --driver=docker --preload=false --cpus="$MK_CPUS" --memory="$MK_MEM"
    fi

    cd "$SOLUTION_DIR"
    echo "Construction de l'image legeni-academy:1.0..."
    docker build -t legeni-academy:1.0 .
    minikube image load legeni-academy:1.0

    echo "Application du namespace et des secrets icgroup..."
    kubectl create namespace icgroup --dry-run=client -o yaml | kubectl apply -f -
    kubectl label namespace icgroup env=prod --overwrite

    if [ -f "k8s/icgroup-secrets.yaml" ]; then
        kubectl apply -f k8s/icgroup-secrets.yaml
    else
        kubectl create secret generic icgroup-secrets -n icgroup \
            --from-literal=postgres-user=odoo \
            --from-literal=postgres-password=OdooProdSecret2026! \
            --from-literal=pgadmin-email=admin@icgroup.com \
            --from-literal=pgadmin-password=PgAdminSecret2026! \
            --dry-run=client -o yaml | kubectl apply -f -
    fi
    kubectl label secret icgroup-secrets -n icgroup env=prod --overwrite

    echo "Application des manifests Kubernetes IC GROUP..."
    kubectl apply -f k8s/icgroup-manifests.yaml

    echo "Attente du rollout des déploiements..."
    kubectl rollout status deployment/postgres-deployment -n icgroup --timeout=300s
    kubectl rollout status deployment/odoo-deployment -n icgroup --timeout=600s
    kubectl rollout status deployment/pgadmin-deployment -n icgroup --timeout=300s
    kubectl rollout status deployment/legeni-academy-deployment -n icgroup --timeout=180s

    echo "Ressources déployées dans le namespace icgroup :"
    kubectl get all,pvc,cm,secret -n icgroup -l env=prod

    echo "Vérification HTTP du portail Legeni Academy (NodePort 30085) :"
    docker exec minikube curl -fsS http://127.0.0.1:30085 | grep -iE "Legeni Academy|Odoo|pgAdmin" | head -n 5 || true
    echo "✅ Déploiement Kubernetes IC GROUP terminé avec succès !"
}

case "$TARGET" in
    ansible)
        run_ansible_check
        ;;
    k8s)
        run_k8s_deploy
        ;;
    all)
        run_ansible_check
        run_k8s_deploy
        ;;
    *)
        echo "Cible inconnue : $TARGET (valeurs autorisées : all, k8s, ansible)"
        exit 1
        ;;
esac
