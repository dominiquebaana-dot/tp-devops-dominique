#!/bin/bash
# ==============================================================================
# SCRIPT MAÎTRE TOUT-EN-UN : INSTALLATION + EXÉCUTION DE TOUS LES TPs KUBERNETES
# (TP 4.1 à TP 4.13) - 100% Déportable d'un PC à un autre
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOLUTIONS_DIR="$SCRIPT_DIR/solutions"
APP_DIR="$ROOT_DIR/app-fil-rouge"
LOG_FILE="$SCRIPT_DIR/logs_execution_tp_kubernetes.txt"

find "$SCRIPT_DIR" -type f \( -name "*.sh" -o -name "*.yaml" -o -name "*.yml" \) -exec sed -i 's/\r$//' {} + 2>/dev/null || true

exec > >(tee "$LOG_FILE") 2>&1

wait_ns_absent() {
    local ns="$1"
    if kubectl get namespace "$ns" >/dev/null 2>&1; then
        echo "Suppression préalable du namespace existant $ns..."
        kubectl delete namespace "$ns" --timeout=60s 2>/dev/null || true
        echo "Attente de la suppression complète du namespace $ns..."
        kubectl wait --for=delete "namespace/$ns" --timeout=180s 2>/dev/null || true
    fi
}

echo "=============================================================================="
echo " DÉMARRAGE DU PARCOURS AUTOMATISÉ TP KUBERNETES ($(date))"
echo "=============================================================================="

# ------------------------------------------------------------------------------
# TP 4.1 : Installation de kubectl & Minikube + Démarrage du cluster + Addons
# ------------------------------------------------------------------------------
echo ""
echo "=== [TP 4.1] Installation de kubectl et Minikube, démarrage du cluster et addons ==="
# Détection d'architecture CPU
ARCH="amd64"
case "$(uname -m)" in
    aarch64|arm64) ARCH="arm64" ;;
    x86_64) ARCH="amd64" ;;
esac

if ! command -v kubectl >/dev/null 2>&1; then
    KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && rm -f kubectl
fi

if ! command -v minikube >/dev/null 2>&1; then
    curl -LO "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-${ARCH}"
    sudo install "minikube-linux-${ARCH}" /usr/local/bin/minikube && rm -f "minikube-linux-${ARCH}"
fi

if ! minikube status >/dev/null 2>&1; then
    TOTAL_MEM_MB=$(free -m | awk '/^Mem:/{print $2}')
    MK_MEM=$([ "$TOTAL_MEM_MB" -ge 6144 ] && echo 4096 || echo 2560)
    MK_CPUS=$([ "$(nproc)" -ge 2 ] && echo 2 || echo 1)
    minikube start --driver=docker --preload=false --cpus="$MK_CPUS" --memory="$MK_MEM"
fi

minikube addons enable metrics-server || true
minikube addons enable ingress || true
minikube addons enable dashboard || true

echo "Attente que le contrôleur Ingress Nginx soit prêt..."
for i in $(seq 1 30); do
    if kubectl get pod -n ingress-nginx -l app.kubernetes.io/component=controller --no-headers 2>/dev/null | grep -q .; then
        break
    fi
    sleep 2
done
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s
kubectl wait --namespace kube-system --for=condition=ready pod -l k8s-app=metrics-server --timeout=120s 2>/dev/null || true

kubectl get nodes -o wide
kubectl get pods -n kube-system
kubectl top nodes || true

echo "--- Chargement des images legeni-webapp:1.0.0 et 2.0.0 dans Minikube ---"
(
    cd "$APP_DIR"
    docker build --build-arg APP_VERSION=1.0.0 -t legeni-webapp:1.0.0 .
    docker build --build-arg APP_VERSION=2.0.0 -t legeni-webapp:2.0.0 .
)
cd "$SCRIPT_DIR"
minikube image load legeni-webapp:1.0.0
minikube image load legeni-webapp:2.0.0

# ------------------------------------------------------------------------------
# TP 4.2 : Pods, Sidecar & Défi Redis
# ------------------------------------------------------------------------------
echo ""
echo "=== [TP 4.2] Déploiement des Pods (my-pod, web-sidecar et Défi redis) ==="
kubectl apply -f "$SOLUTIONS_DIR/tp4.2/pods.yaml"
kubectl wait --for=condition=Ready pod/my-pod pod/web-sidecar pod/redis --timeout=120s
kubectl get pods -o wide
kubectl exec redis -- redis-cli PING
kubectl delete -f "$SOLUTIONS_DIR/tp4.2/pods.yaml"

# ------------------------------------------------------------------------------
# TP 4.3 : Deployment, ReplicaSet, Service & Défi echo
# ------------------------------------------------------------------------------
echo ""
echo "=== [TP 4.3] Deployment, Auto-réparation, Service et Défi http-echo ==="
kubectl apply -f "$SOLUTIONS_DIR/tp4.3/deployment-service.yaml"
kubectl rollout status deployment/my-deployment --timeout=120s
kubectl rollout status deployment/echo --timeout=120s
kubectl get deploy,rs,pods,svc
kubectl delete -f "$SOLUTIONS_DIR/tp4.3/deployment-service.yaml"

# ------------------------------------------------------------------------------
# TP 4.4 : Application fil rouge sur Kubernetes & Défi webapp-prod
# ------------------------------------------------------------------------------
echo ""
echo "=== [TP 4.4] Application fil rouge (port 8180) + Défi seconde instance webapp-prod ==="
kubectl apply -f "$SOLUTIONS_DIR/tp4.4/webapp.yaml"
kubectl rollout status deployment/webapp-deployment --timeout=120s
kubectl rollout status deployment/webapp-prod --timeout=120s
kubectl get deploy,pods,svc -l 'app in (webapp,webapp-prod)'
MK_IP=$(minikube ip)
curl -sf "http://${MK_IP}:30180/api/info" ; echo ""
curl -sf "http://${MK_IP}:30181/api/info" ; echo ""
kubectl delete -f "$SOLUTIONS_DIR/tp4.4/webapp.yaml"

# ------------------------------------------------------------------------------
# TP 4.5 : WordPress + MySQL + PVC + Secret + Défi phpMyAdmin
# ------------------------------------------------------------------------------
echo ""
echo "=== [TP 4.5] Stack WordPress + MySQL + PVC + Secret + Défi phpMyAdmin ==="
wait_ns_absent wordpress
kubectl create namespace wordpress --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic mysql-pass -n wordpress --from-literal=password="RootSecret123!" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$SOLUTIONS_DIR/tp4.5/wordpress-mysql.yaml"
kubectl rollout status deployment/mysql -n wordpress --timeout=240s
kubectl rollout status deployment/wordpress -n wordpress --timeout=240s
kubectl rollout status deployment/phpmyadmin -n wordpress --timeout=240s
kubectl get pvc,deploy,svc -n wordpress
kubectl delete namespace wordpress --timeout=180s

# ------------------------------------------------------------------------------
# TP 4.6 : Jobs, CronJobs, DaemonSets, initContainers & Défi Migration
# ------------------------------------------------------------------------------
echo ""
echo "=== [TP 4.6] Jobs (succès & échec), CronJobs, DaemonSet, initContainer & Défi Migration ==="
wait_ns_absent batch
kubectl apply -f "$SOLUTIONS_DIR/tp4.6/jobs-cronjobs-daemonset.yaml"
kubectl rollout status deployment/webapp -n batch --timeout=120s
kubectl apply -f "$SOLUTIONS_DIR/tp4.6/job-echec.yaml"
kubectl wait --for=condition=failed job/migration-ratee -n batch --timeout=90s
kubectl delete -f "$SOLUTIONS_DIR/tp4.6/job-echec.yaml"
kubectl wait --for=condition=complete job/calcul-pi -n batch --timeout=120s
kubectl logs job/calcul-pi -n batch | cut -c1-120 ; echo "..."
kubectl wait --for=condition=complete job/traitement-lots -n batch --timeout=120s

echo "--- Test manuel des CronJobs controle-sante et sauvegarde (http://webapp prêt) ---"
kubectl create job --from=cronjob/controle-sante controle-manuel -n batch
kubectl wait --for=condition=complete job/controle-manuel -n batch --timeout=60s
kubectl logs job/controle-manuel -n batch
kubectl create job --from=cronjob/sauvegarde sauvegarde-manuel -n batch
kubectl wait --for=condition=complete job/sauvegarde-manuel -n batch --timeout=60s
kubectl logs job/sauvegarde-manuel -n batch

echo "--- Déblocage de l'initContainer et complétion du Job migration-compteur ---"
kubectl create deployment redis --image=redis:7.4-alpine --port=6379 -n batch --dry-run=client -o yaml | kubectl apply -f -
kubectl expose deployment redis --port=6379 -n batch --dry-run=client -o yaml | kubectl apply -f -
kubectl wait --for=condition=complete job/migration-compteur -n batch --timeout=120s
kubectl rollout status deployment/webapp-redis -n batch --timeout=120s
kubectl exec deployment/redis -n batch -- redis-cli GET visits
kubectl get jobs,cronjobs,ds,pods -n batch
kubectl delete namespace batch --timeout=180s

# ------------------------------------------------------------------------------
# TP 4.7 à 4.11 : Stack legeni-dev (ConfigMap, Secret, StatefulSet, Probes, HPA, Ingress TLS)
# ------------------------------------------------------------------------------
echo ""
echo "=== [TP 4.7 à 4.11] Stack complète legeni-dev (StatefulSet Redis, Probes, HPA, Ingress TLS) ==="
wait_ns_absent legeni-dev
kubectl create namespace legeni-dev --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace legeni-dev env=dev --overwrite
kubectl create secret generic redis-secret -n legeni-dev --from-literal=REDIS_PASSWORD="S3cr3t-Redis!" --dry-run=client -o yaml | kubectl apply -f -
kubectl label secret redis-secret -n legeni-dev env=dev --overwrite

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /tmp/tls.key -out /tmp/tls.crt -subj "/CN=legeni.local" 2>/dev/null
kubectl create secret tls legeni-tls -n legeni-dev --cert=/tmp/tls.crt --key=/tmp/tls.key --dry-run=client -o yaml | kubectl apply -f -
kubectl label secret legeni-tls -n legeni-dev env=dev --overwrite
rm -f /tmp/tls.key /tmp/tls.crt

kubectl apply -f "$SOLUTIONS_DIR/tp4.7_a_4.11/legeni-dev-stack.yaml"
kubectl rollout status statefulset/redis -n legeni-dev --timeout=120s
kubectl rollout status deployment/webapp -n legeni-dev --timeout=120s

echo "--- TP 4.8 : Rolling Update 1.0.0 -> 2.0.0 & Rollback sur image :9.9.9 ---"
kubectl set image deployment/webapp webapp=legeni-webapp:2.0.0 -n legeni-dev
kubectl rollout status deployment/webapp -n legeni-dev --timeout=120s
kubectl set image deployment/webapp webapp=legeni-webapp:9.9.9 -n legeni-dev
sleep 8
kubectl rollout undo deployment/webapp -n legeni-dev
kubectl rollout status deployment/webapp -n legeni-dev --timeout=120s
kubectl rollout history deployment/webapp -n legeni-dev

echo "--- TP 4.9 : OOMKilled (oom.yaml) & ResourceQuota (quota-dev.yaml) ---"
kubectl apply -f "$SOLUTIONS_DIR/tp4.9/oom.yaml"
for i in $(seq 1 20); do
    PHASE=$(kubectl get pod oom -n legeni-dev -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    [ "$PHASE" = "Failed" ] && break
    sleep 2
done
kubectl get pod oom -n legeni-dev -o jsonpath='{.status.containerStatuses[0].state.terminated.reason}{"\n"}' || true
kubectl delete -f "$SOLUTIONS_DIR/tp4.9/oom.yaml"
kubectl apply -f "$SOLUTIONS_DIR/tp4.9/quota-dev.yaml"
kubectl get resourcequota quota-dev -n legeni-dev
kubectl delete -f "$SOLUTIONS_DIR/tp4.9/quota-dev.yaml"

echo "--- TP 4.10 : PV/PVC statique (pv-manuel.yaml) & Défi WordPress StatefulSet ---"
kubectl apply -f "$SOLUTIONS_DIR/tp4.10/pv-manuel.yaml"
kubectl get pv pv-manuel
kubectl get pvc pvc-manuel -n legeni-dev
kubectl delete -f "$SOLUTIONS_DIR/tp4.10/pv-manuel.yaml"

echo "--- TP 4.11 : Vérification Ingress TLS https://legeni.local/api/info ---"
MK_IP=$(minikube ip)
for i in $(seq 1 15); do
    curl -skf --resolve "legeni.local:443:${MK_IP}" https://legeni.local/api/info && break
    sleep 2
done
echo ""
kubectl top pods -n legeni-dev 2>/dev/null || true
kubectl get all,pvc,hpa,ingress -n legeni-dev
kubectl delete namespace legeni-dev --timeout=180s

echo "--- Défi TP 4.10 + TP 4.11 : WordPress StatefulSet + PVC + blog-ingress.yaml ---"
wait_ns_absent wordpress-sts
kubectl create namespace wordpress-sts --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic mysql-pass -n wordpress-sts --from-literal=password="RootSecret123!" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$SOLUTIONS_DIR/tp4.10/wordpress-statefulset.yaml"
kubectl apply -f "$SOLUTIONS_DIR/tp4.7_a_4.11/blog-ingress.yaml"
kubectl rollout status statefulset/mysql -n wordpress-sts --timeout=240s
kubectl rollout status deployment/wordpress -n wordpress-sts --timeout=240s
kubectl get sts,pvc,ingress -n wordpress-sts
kubectl delete namespace wordpress-sts --timeout=180s

# ------------------------------------------------------------------------------
# TP 4.12 : Multi-environnements avec Kustomize (staging, prod et Défi dev)
# ------------------------------------------------------------------------------
echo ""
echo "=== [TP 4.12] Kustomize : Validation et déploiement réel des overlays staging, prod et dev ==="
kubectl kustomize "$SOLUTIONS_DIR/tp4.12_kustomize/overlays/staging" >/dev/null && echo "Overlay staging valide !"
kubectl kustomize "$SOLUTIONS_DIR/tp4.12_kustomize/overlays/prod" >/dev/null && echo "Overlay prod valide !"
kubectl kustomize "$SOLUTIONS_DIR/tp4.12_kustomize/overlays/dev" >/dev/null && echo "Overlay dev (Défi) valide !"

for kns in legeni-staging legeni-prod legeni-dev-kustomize; do
    wait_ns_absent "$kns"
    kubectl create namespace "$kns" --dry-run=client -o yaml | kubectl apply -f -
    kubectl create secret generic redis-secret -n "$kns" --from-literal=REDIS_PASSWORD="KustomizeSecret2026!" --dry-run=client -o yaml | kubectl apply -f -
done
kubectl apply -k "$SOLUTIONS_DIR/tp4.12_kustomize/overlays/staging"
kubectl apply -k "$SOLUTIONS_DIR/tp4.12_kustomize/overlays/prod"
kubectl apply -k "$SOLUTIONS_DIR/tp4.12_kustomize/overlays/dev"
for kns in legeni-staging legeni-prod legeni-dev-kustomize; do
    kubectl rollout status statefulset/redis -n "$kns" --timeout=120s
    kubectl rollout status deployment/webapp -n "$kns" --timeout=120s
    kubectl exec deployment/webapp -n "$kns" -- python -c "import urllib.request; print(urllib.request.urlopen('http://webapp/api/info').read().decode())"
done
kubectl delete namespace legeni-staging legeni-prod legeni-dev-kustomize --timeout=180s

# ------------------------------------------------------------------------------
# TP 4.13 : Dépannage – Application et validation des 6 pannes corrigées + Défi
# ------------------------------------------------------------------------------
echo ""
echo "=== [TP 4.13] Dépannage : Déploiement et vérification des 6 pannes corrigées + Défi ==="
wait_ns_absent depannage
kubectl apply -f "$SOLUTIONS_DIR/tp4.13_depannage/pannes_corrigees.yaml"
kubectl apply -f "$SOLUTIONS_DIR/tp4.13_depannage/panne7_defi_corrigee.yaml"
kubectl rollout status deployment/front -n depannage --timeout=120s
kubectl rollout status deployment/api -n depannage --timeout=120s
kubectl rollout status deployment/web -n depannage --timeout=120s
kubectl rollout status deployment/app -n depannage --timeout=120s
kubectl rollout status deployment/conf -n depannage --timeout=120s
kubectl rollout status deployment/portal-defi -n depannage --timeout=120s
kubectl wait --for=condition=Ready pod/db -n depannage --timeout=120s
kubectl exec deployment/api -n depannage -- python -c "import urllib.request; print('web:', urllib.request.urlopen('http://web').status); print('app:', urllib.request.urlopen('http://app').status)"
kubectl get pods,svc,pvc -n depannage
kubectl delete namespace depannage --timeout=180s

echo ""
echo "=============================================================================="
echo " TOUS LES TPs KUBERNETES (4.1 À 4.13) SONT VALIDÉS AVEC SUCCÈS !"
echo " Compte-rendu complet : $SCRIPT_DIR/COMPTE_RENDU_TP_KUBERNETES.md"
echo "=============================================================================="
