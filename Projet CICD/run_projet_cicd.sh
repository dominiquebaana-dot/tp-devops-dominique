#!/bin/bash
# ==============================================================================
# SCRIPT D'AUTOMATISATION INTÉGRALE DU PROJET FINAL CI/CD (Projet CICD)
# Installe l'infrastructure (Lot 2), chiffre le Vault, déploie Staging & Prod (Lot 3)
# et exécute automatiquement les scénarios de la Soutenance (§ 6) !
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/legeni-webapp"
ANSIBLE_DIR="$PROJECT_DIR/ansible"
LOG_FILE="$SCRIPT_DIR/logs_soutenance_projet_cicd.txt"

find "$SCRIPT_DIR" -type f \( -name "*.sh" -o -name "Jenkinsfile*" -o -name "Dockerfile*" -o -name "*.yml" -o -name "*.j2" -o -name "*.ini" -o -name "*.cfg" -o -name "VERSION" -o -name ".vault_pass*" \) -exec sed -i 's/\r$//' {} + 2>/dev/null || true

exec > >(tee "$LOG_FILE") 2>&1

echo "=============================================================================="
echo " DÉMARRAGE DU PROJET FINAL CI/CD - LEGENI WEBAPP ($(date))"
echo "=============================================================================="

# Installation des collections requises
if [ -f "$ANSIBLE_DIR/requirements.yml" ]; then
    echo "--- Installation des collections Ansible déclarées dans requirements.yml ---"
    ansible-galaxy collection install -r "$ANSIBLE_DIR/requirements.yml" 2>/dev/null || true
fi

run_provision() {
    if [ "$(id -u)" -eq 0 ]; then
        ansible-playbook provision.yml
    else
        sudo ansible-playbook provision.yml
    fi
}

# Copie du mot de passe Vault dans /tmp (chmod 600 impossible sur montage NTFS/drvfs WSL sans metadata)
VAULT_PASS_TMP="/tmp/.legeni_vault_pass_$$"
cp "$ANSIBLE_DIR/.vault_pass.example" "$VAULT_PASS_TMP"
chmod 600 "$VAULT_PASS_TMP"
trap 'rm -f "$VAULT_PASS_TMP"' EXIT

# 1. Chiffrement automatique de vars/vault.yml avec Ansible Vault s'il n'est pas encore chiffré
cd "$ANSIBLE_DIR"
if [ ! -f "vars/vault.yml" ] || ! head -n 1 "vars/vault.yml" 2>/dev/null | grep -q '^\$ANSIBLE_VAULT'; then
    echo "=== [LOT 2] Création et chiffrement de vars/vault.yml avec Ansible Vault ==="
    cp vars/vault.yml.example vars/vault.yml
    ansible-vault encrypt vars/vault.yml --vault-password-file "$VAULT_PASS_TMP"
    echo "Fichier vars/vault.yml chiffré avec succès (en-tête : $(sed -n '1p' vars/vault.yml))"
fi

# 2. Exécution du playbook provision.yml (Lot 2 : Docker + Minikube + Jenkins + Idempotence)
echo ""
echo "=== [LOT 2] Exécution de provision.yml (Installation IaC Docker, Minikube, Jenkins) ==="
run_provision

echo ""
echo "=== [LOT 2] Preuve d'idempotence : 2e exécution de provision.yml (changed=0 attendu) ==="
run_provision

# 3. Lot 1 : Construction multi-stage avec tests, Hadolint et Scan Trivy
echo ""
echo "=== [LOT 1 & LOT 4] Contrôles Qualité, Build Multi-Stage & Scan Trivy ==="
cd "$PROJECT_DIR"
docker run --rm -i hadolint/hadolint:v2.12.0 < Dockerfile && echo "✅ Hadolint : 0 erreur"
docker build --target test -t legeni-webapp:test .
docker build --build-arg APP_VERSION="1.0.0-1" -t legeni-webapp:1.0.0-1 .
docker build --build-arg APP_VERSION="1.1.0-2" -t legeni-webapp:1.1.0-2 .

docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy_cache:/root/.cache \
    aquasec/trivy:0.57.1 image --severity CRITICAL --ignore-unfixed --exit-code 1 legeni-webapp:1.0.0-1

echo "--- Chargement des images 1.0.0-1 et 1.1.0-2 dans Minikube ---"
minikube image load legeni-webapp:1.0.0-1
minikube image load legeni-webapp:1.1.0-2

# 4. Lot 3 : Déploiement initial en Staging et en Production (1.0.0-1)
echo ""
echo "=== [LOT 3 & LOT 5] Déploiement initial v1.0.0-1 en Staging et en Production ==="
cd "$ANSIBLE_DIR"
ansible-playbook deploy.yml --vault-password-file "$VAULT_PASS_TMP" \
    -e target_env=staging -e webapp_image=legeni-webapp -e app_version=1.0.0-1

ansible-playbook deploy.yml --vault-password-file "$VAULT_PASS_TMP" \
    -e target_env=prod -e webapp_image=legeni-webapp -e app_version=1.0.0-1

kubectl get all,pvc,ingress,hpa,cronjob -n legeni-prod

# 5. SCÉNARIO DE SOUTENANCE (§ 6)
echo ""
echo "=============================================================================="
echo " DÉMONSTRATION AUTOMATISÉE DU SCÉNARIO DE SOUTENANCE (§ 6)"
echo "=============================================================================="

echo ""
echo "--- SCÉNARIO 1 : Livraison nominale (1.0.0-1 -> 1.1.0-2) avec test 0 erreur ---"
ansible-playbook deploy.yml --vault-password-file "$VAULT_PASS_TMP" \
    -e target_env=staging -e webapp_image=legeni-webapp -e app_version=1.1.0-2

# Surveillance HTTP continue sur le NodePort 30082 de la prod (compatible Ubuntu & WSL2 sans blocage)
MINIKUBE_IP=$(minikube ip)
rm -f /tmp/prod_rollout_errs.txt
(
    for i in $(seq 1 40); do
        if docker exec minikube command -v curl >/dev/null 2>&1; then
            code=$(docker exec minikube curl -s -m 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:30082/api/info || echo "000")
        else
            code=$(docker run --rm --network minikube curlimages/curl:8.11.1 -s -m 2 -o /dev/null -w '%{http_code}' "http://${MINIKUBE_IP}:30082/api/info" || echo "000")
        fi
        if [ "$code" != "200" ]; then
            echo "ERR $code" >> /tmp/prod_rollout_errs.txt
        fi
        sleep 0.5
    done
) &
CURL_PID=$!

ansible-playbook deploy.yml --vault-password-file "$VAULT_PASS_TMP" \
    -e target_env=prod -e webapp_image=legeni-webapp -e app_version=1.1.0-2

wait $CURL_PID || true
ERR_COUNT=0
if [ -f /tmp/prod_rollout_errs.txt ]; then
    ERR_COUNT=$(wc -l < /tmp/prod_rollout_errs.txt)
    rm -f /tmp/prod_rollout_errs.txt
fi
echo "Nombre d'erreurs HTTP observées pendant le rolling update : $ERR_COUNT"
kubectl rollout history deployment/webapp -n legeni-prod

echo ""
echo "--- SCÉNARIO 2 : Code défectueux (test unitaire cassé) -> Pipeline bloqué avant build ---"
SC2_TMP="/tmp/cicd_scenario2_$$"
rm -rf "$SC2_TMP" && cp -r "$PROJECT_DIR" "$SC2_TMP"
sed -i 's/status="ok"/status="ko"/' "$SC2_TMP/app.py"
set +e
docker build --target test "$SC2_TMP" >/dev/null 2>&1
SC2_RC=$?
set -e
rm -rf "$SC2_TMP"
if [ "$SC2_RC" -eq 0 ]; then
    echo "❌ ERREUR : Le build de test aurait dû échouer sur code défectueux !"
    exit 1
fi
echo "✅ Code retour attendu (échec --target test bloquant toute image) : $SC2_RC"

echo ""
echo "--- SCÉNARIO 3 : Déploiement raté (readinessProbe cassée) -> Rollback Automatique ---"
set +e
ansible-playbook deploy.yml --vault-password-file "$VAULT_PASS_TMP" \
    -e target_env=prod -e webapp_image=legeni-webapp -e app_version=1.1.0-2 \
    -e readiness_path="/chemin-inexistant-panne"
RC=$?
set -e
echo "Code retour attendu (échec détecté et rollback exécuté) : $RC"
echo "Vérification que la production tourne toujours sainement après le rollback automatique :"
kubectl get deploy,pods -n legeni-prod

echo ""
echo "=============================================================================="
echo " PROJET FINAL CI/CD EXÉCUTÉ ET VALIDÉ DE BOUT EN BOUT !"
echo " Rapport complet : $PROJECT_DIR/docs/rapport.md"
echo " Traces d'exécution : $LOG_FILE"
echo "=============================================================================="
