#!/bin/bash
# ==============================================================================
# SCRIPT GÉNÉRAL « LA TOTALE » - 100 % DÉPORTABLE SUR VOTRE AUTRE PC (UBUNTU/WSL2)
# Installe tous les outils depuis zéro, configure Docker + Jenkins + Minikube + Ansible,
# et exécute les TPs Docker, Jenkins, Kubernetes ainsi que le Projet Final !
# ==============================================================================
# Usage :
#   bash setup_and_run_everything.sh           # Installe TOUT et exécute TOUT de A à Z
#   bash setup_and_run_everything.sh install   # Installe et configure uniquement les outils
#   bash setup_and_run_everything.sh git       # Lance uniquement le TP Git (TP 2.1)
#   bash setup_and_run_everything.sh docker    # Lance uniquement tous les TPs Docker (2.2 -> 2.10)
#   bash setup_and_run_everything.sh jenkins   # Lance uniquement tous les TPs Jenkins (3.1 -> 3.8)
#   bash setup_and_run_everything.sh k8s       # Lance uniquement tous les TPs Kubernetes (4.1 -> 4.13)
#   bash setup_and_run_everything.sh ansible   # Lance uniquement tous les TPs Ansible (5.1 -> 5.6)
#   bash setup_and_run_everything.sh final     # Lance le Projet Final CI/CD (Lots 0 à 5 + Soutenance)
#   bash setup_and_run_everything.sh icgroup   # Lance l'ancien Projet Final IC GROUP (Odoo + pgAdmin)
#   bash setup_and_run_everything.sh clean     # Nettoie conteneurs, réseaux, minikube et caches locaux
# ==============================================================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-all}"

if [ "${_PREREQS_DONE:-0}" = "0" ]; then
    echo "=============================================================================="
    echo " PRÉPARATION DU DÉPÔT (Correction automatique des fins de ligne Windows CRLF)"
    echo "=============================================================================="
    find "$ROOT_DIR" -type f \( -name "*.sh" -o -name "Jenkinsfile*" -o -name "Dockerfile*" -o -name "*.yml" -o -name "*.yaml" -o -name "*.j2" -o -name "*.env*" -o -name "*.conf" -o -name "*.txt" -o -name "VERSION" -o -name "*.ini" -o -name "*.cfg" -o -name "*.py" -o -name "*.json" -o -name "*.md" \) -exec sed -i 's/\r$//' {} + 2>/dev/null || true
    find "$ROOT_DIR" -type f -name "*.sh" -exec chmod +x {} + 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 1. INSTALLATION & CONFIGURATION COMPLÈTE DE LA MACHINE DEPUIS ZÉRO
# ------------------------------------------------------------------------------
install_all_prerequisites() {
    if [ "${_PREREQS_DONE:-0}" = "1" ]; then
        return 0
    fi

    echo ""
    echo "=============================================================================="
    echo " ÉTAPE 1 : INSTALLATION AUTOMATIQUE DES OUTILS (Docker, Kubectl, Minikube, Ansible)"
    echo "=============================================================================="

    sudo apt-get update
    sudo apt-get install -y \
        ca-certificates curl gnupg lsb-release git jq tree openssh-client openssl \
        python3 python3-pip python3-venv python3-kubernetes python3-docker ansible

    # Détection dynamique de l'architecture CPU
    ARCH="amd64"
    case "$(uname -m)" in
        aarch64|arm64) ARCH="arm64" ;;
        x86_64) ARCH="amd64" ;;
    esac

    # Environnement Python isolé pour Ansible Kubernetes (évite tout conflit PEP 668 / apt sur Ubuntu 24.04)
    if ! /opt/k8s-python/bin/python -c "import kubernetes" 2>/dev/null; then
        echo ">>> Création de l'environnement Python dédié pour Ansible Kubernetes (/opt/k8s-python)..."
        sudo python3 -m venv /opt/k8s-python
        sudo /opt/k8s-python/bin/pip install -q --no-cache-dir "kubernetes==31.*"
    fi

    # 1.1 Docker Engine + Docker Compose v2 (même clé /etc/apt/keyrings/docker.asc que Ansible)
    # Note : sous WSL2, Docker Desktop peut laisser un lien symbolique stub si l'intégration est désactivée ;
    # on vérifie donc aussi que `docker --version` fonctionne réellement.
    if ! command -v docker >/dev/null 2>&1 || ! docker --version >/dev/null 2>&1; then
        echo ">>> Installation de Docker Engine et Docker Compose v2..."
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL "https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg" | sudo tee /etc/apt/keyrings/docker.asc > /dev/null
        sudo chmod 0644 /etc/apt/keyrings/docker.asc
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
          | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi

    sudo systemctl enable --now docker 2>/dev/null || sudo service docker start 2>/dev/null || true
    sudo usermod -aG docker "$USER" || true

    # Attente active que le démon Docker et son socket soient prêts
    for i in $(seq 1 10); do
        docker info >/dev/null 2>&1 && break
        sleep 1
    done

    # 1.2 kubectl
    if ! command -v kubectl >/dev/null 2>&1; then
        echo ">>> Installation de kubectl..."
        KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
        curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl"
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && rm -f kubectl
    fi

    # 1.3 Minikube
    if ! command -v minikube >/dev/null 2>&1; then
        echo ">>> Installation de Minikube..."
        curl -LO "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-${ARCH}"
        sudo install "minikube-linux-${ARCH}" /usr/local/bin/minikube && rm -f "minikube-linux-${ARCH}"
    fi

    # 1.4 Collections Ansible globales (accessibles en root ET utilisateur normal)
    echo ">>> Installation des collections Ansible (community.docker, kubernetes.core & ansible.posix)..."
    sudo mkdir -p /usr/share/ansible/collections
    sudo ansible-galaxy collection install -p /usr/share/ansible/collections community.docker kubernetes.core ansible.posix

    # Recharger immédiatement le groupe docker dans cette session si nécessaire
    for i in $(seq 1 10); do
        docker info >/dev/null 2>&1 && break
        sleep 1
    done
    if [ "$(id -u)" -ne 0 ] && ! docker info >/dev/null 2>&1; then
        if getent group docker | grep -qw "$USER" && [ "${_DOCKER_SG_REEXEC:-0}" = "0" ]; then
            echo ">>> Activation immédiate du groupe 'docker' dans la session courante..."
            export _PREREQS_DONE=1
            export _DOCKER_SG_REEXEC=1
            exec sg docker -c "bash \"$0\" \"$MODE\""
        fi
    fi

    echo ""
    echo "✅ Outils installés :"
    docker --version
    docker compose version
    kubectl version --client
    minikube version | sed -n '1p'
    ansible --version | sed -n '1p'
}

# ------------------------------------------------------------------------------
# 2. EXÉCUTION DU PROJET ALTERNATIF IC GROUP (Odoo + pgAdmin + Legeni Academy)
# ------------------------------------------------------------------------------
run_icgroup_project() {
    bash "$ROOT_DIR/Projet final/run_projet_final.sh" all
}

# ------------------------------------------------------------------------------
# ORCHESTRATION SELON LE MODE CHOISI
# ------------------------------------------------------------------------------
case "$MODE" in
    install)
        install_all_prerequisites
        ;;
    git)
        install_all_prerequisites
        bash "$ROOT_DIR/TP git/run_all_tp_git.sh"
        ;;
    docker)
        install_all_prerequisites
        bash "$ROOT_DIR/TP docker/run_all_tp_docker.sh"
        ;;
    jenkins)
        install_all_prerequisites
        bash "$ROOT_DIR/TP_jenkins/run_all_tp_jenkins.sh"
        ;;
    k8s)
        install_all_prerequisites
        bash "$ROOT_DIR/TP kubernetes/run_all_tp_kubernetes.sh"
        ;;
    ansible)
        install_all_prerequisites
        bash "$ROOT_DIR/TP ansible/run_all_tp_ansible.sh"
        ;;
    final)
        install_all_prerequisites
        bash "$ROOT_DIR/Projet CICD/run_projet_cicd.sh"
        ;;
    icgroup)
        install_all_prerequisites
        run_icgroup_project
        ;;
    clean)
        echo "=== Nettoyage complet des conteneurs, images résiduelles et cluster Minikube ==="
        if [ -f "$ROOT_DIR/TP ansible/lab/docker-compose.yml" ]; then
            docker compose -f "$ROOT_DIR/TP ansible/lab/docker-compose.yml" down -v 2>/dev/null || true
        fi
        rm -rf /tmp/tp_git_demo 2>/dev/null || true
        docker rm -f $(docker ps -aq) 2>/dev/null || true
        docker network prune -f 2>/dev/null || true
        if command -v minikube >/dev/null 2>&1; then
            minikube delete 2>/dev/null || true
        fi
        find "$ROOT_DIR" -type d \( -name "__pycache__" -o -name ".pytest_cache" \) -exec rm -rf {} + 2>/dev/null || true
        find "$ROOT_DIR" -type f -name "*.pyc" -delete 2>/dev/null || true
        echo "✅ Environnement nettoyé avec succès."
        ;;
    all)
        install_all_prerequisites
        bash "$ROOT_DIR/TP git/run_all_tp_git.sh"
        bash "$ROOT_DIR/TP docker/run_all_tp_docker.sh"
        bash "$ROOT_DIR/TP_jenkins/run_all_tp_jenkins.sh"
        bash "$ROOT_DIR/TP kubernetes/run_all_tp_kubernetes.sh"
        bash "$ROOT_DIR/TP ansible/run_all_tp_ansible.sh"
        bash "$ROOT_DIR/Projet CICD/run_projet_cicd.sh"
        ;;
    *)
        echo "Usage: bash $0 [all|install|git|docker|jenkins|k8s|ansible|final|icgroup|clean]"
        exit 1
        ;;
esac

echo ""
echo "=============================================================================="
echo " 🎉 OPÉRATION TERMINÉE AVEC SUCCÈS !"
echo " - Compte-rendu Git        : TP git/COMPTE_RENDU_TP_GIT.md"
echo " - Compte-rendu Docker     : TP docker/COMPTE_RENDU_TP_DOCKER.md"
echo " - Compte-rendu Jenkins    : TP_jenkins/COMPTE_RENDU_TP_JENKINS.md"
echo " - Compte-rendu Kubernetes : TP kubernetes/COMPTE_RENDU_TP_KUBERNETES.md"
echo " - Compte-rendu Ansible    : TP ansible/COMPTE_RENDU_TP_ANSIBLE.md"
echo " - Rapport Projet CI/CD    : Projet CICD/legeni-webapp/docs/rapport.md"
echo " - Rapport Projet IC GROUP : Projet final/RAPPORT_PROJET_FINAL_ICGROUP.md"
echo "=============================================================================="
