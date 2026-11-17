#!/bin/bash
# ==============================================================================
# SCRIPT D'EXÉCUTION AUTOMATISÉE : TP 2.1 - GIT EN ÉQUIPE (GITHUB FLOW)
# Reproduit l'intégralité du TP 2.1 (Étapes 1 à 9 + Défi) avec 2 binômes
# (Étudiant A et Étudiant B) et un dépôt distant nu (origin.git).
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOLUTIONS_DIR="$SCRIPT_DIR/solutions"
APP_DIR="$ROOT_DIR/app-fil-rouge"
LOG_FILE="$SCRIPT_DIR/logs_execution_tp_git.txt"
WORK_DIR="/tmp/tp_git_demo"

find "$SCRIPT_DIR" -type f \( -name "*.sh" -o -name "pre-*" -o -name "*.md" \) -exec sed -i 's/\r$//' {} + 2>/dev/null || true
chmod +x "$SOLUTIONS_DIR/pre-commit" "$SOLUTIONS_DIR/pre-receive.protected-main" 2>/dev/null || true

exec > >(tee "$LOG_FILE") 2>&1

echo "=============================================================================="
echo " DÉMARRAGE DU PARCOURS AUTOMATISÉ TP 2.1 : GIT EN ÉQUIPE ($(date))"
echo "=============================================================================="

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

# ------------------------------------------------------------------------------
# ÉTAPE 1 : Configuration Git globale (avec alias lg et Défi git undo)
# ------------------------------------------------------------------------------
echo ""
echo "=== [ÉTAPE 1] Configuration Git globale et alias (lg + Défi undo) ==="
git config --global user.name "Dominique DevOps"
git config --global user.email "dominique@legeni.local"
git config --global init.defaultBranch main
git config --global pull.rebase true
git config --global alias.lg "log --oneline --graph --all --decorate"
git config --global alias.undo "reset --soft HEAD~1"
git config --list | grep -E 'user\.|init\.|pull\.|alias\.'

# ------------------------------------------------------------------------------
# ÉTAPE 2 : Initialisation du dépôt legeni-webapp (Étudiant A) + Hook pre-commit
# ------------------------------------------------------------------------------
echo ""
echo "=== [ÉTAPE 2] Initialisation du dépôt (Étudiant A) et dépôt distant origin.git ==="
git init --bare "$WORK_DIR/origin.git"

cp -r "$APP_DIR" "$WORK_DIR/etudiantA"
cd "$WORK_DIR/etudiantA"
git init
cp "$SOLUTIONS_DIR/.gitignore" .gitignore
git status -s

# Installation du hook pre-commit (Défi TP 2.1 : flake8 dans Docker)
cp "$SOLUTIONS_DIR/pre-commit" .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

git add .
git commit -m "Application fil rouge : version initiale"
git remote add origin "$WORK_DIR/origin.git"
git push -u origin main

# ------------------------------------------------------------------------------
# ÉTAPE 3 & 4 : Clone par Étudiant B + branche feature/titre + PR merge
# ------------------------------------------------------------------------------
echo ""
echo "=== [ÉTAPE 3 & 4] Clone (Étudiant B) et branche feature/titre ==="
git clone "$WORK_DIR/origin.git" "$WORK_DIR/etudiantB"
cd "$WORK_DIR/etudiantB"
git config user.name "Etudiant B"
git config user.email "etudiantB@legeni.local"
cp "$SOLUTIONS_DIR/pre-commit" .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

git switch -c feature/titre
sed -i 's/<h1>Legeni WebApp<\/h1>/<h1>Legeni WebApp – B3<\/h1>/' app.py
git diff app.py
git add app.py
git commit -m "Ajoute la promotion dans le titre"
git push -u origin feature/titre

echo "=== [ÉTAPE 5] Revue & Merge de la PR feature/titre sur main ==="
cd "$WORK_DIR/etudiantA"
git fetch origin
git pull origin main
git merge --no-ff origin/feature/titre -m "Merge pull request #1: feature/titre (approuvée par Étudiant A)"
git push origin main
git push origin --delete feature/titre

# ------------------------------------------------------------------------------
# ÉTAPE 6 : Conflit simultané sur app.py et résolution via rebase + --force-with-lease
# ------------------------------------------------------------------------------
echo ""
echo "=== [ÉTAPE 6] Création et résolution d'un conflit (feature/couleur-verte vs feature/couleur-violette) ==="
cd "$WORK_DIR/etudiantA"
git switch main && git pull
git switch -c feature/couleur-verte
sed -i 's/os.getenv("APP_COLOR", "#1f6feb")/os.getenv("APP_COLOR", "#2da44e")/' app.py
git add app.py
git commit -m "Passe la couleur par défaut au vert (#2da44e)"
git push -u origin feature/couleur-verte

cd "$WORK_DIR/etudiantB"
git switch main && git pull
git switch -c feature/couleur-violette
sed -i 's/os.getenv("APP_COLOR", "#1f6feb")/os.getenv("APP_COLOR", "#8250df")/' app.py
git add app.py
git commit -m "Passe la couleur par défaut au violet (#8250df)"
git push -u origin feature/couleur-violette

# Étudiant A merge sa PR en premier
cd "$WORK_DIR/etudiantA"
git switch main
git merge --no-ff feature/couleur-verte -m "Merge pull request #2: feature/couleur-verte"
git push origin main
git push origin --delete feature/couleur-verte

# Étudiant B rebase sur main -> conflit attendu !
cd "$WORK_DIR/etudiantB"
set +e
git pull origin main
CONFLICT_RC=$?
set -e
echo "Code retour rebase (conflit attendu != 0) : $CONFLICT_RC"
git status -s
echo "--- Marqueurs de conflit observés dans app.py ---"
grep -n -C 3 -E '<<<<<<<|=======|>>>>>>>' app.py || true

# Résolution du conflit en conservant #2da44e et suppression des marqueurs
python3 - <<'PY'
from pathlib import Path
import re
p = Path("app.py")
txt = p.read_text(encoding="utf-8")
txt = re.sub(
    r'<<<<<<< .*?\n(.*?)=======\n(.*?)>>>>>>> .*?\n',
    r'\1',
    txt,
    flags=re.S,
)
p.write_text(txt, encoding="utf-8")
PY

git add app.py
GIT_EDITOR=true git rebase --continue
echo "--- Validation Docker --target test après résolution du conflit ---"
docker build --target test -t legeni-webapp:tp21-test .
git push --force-with-lease

# Merge de la PR résolue sur main
cd "$WORK_DIR/etudiantA"
git switch main && git fetch origin && git pull
git merge --no-ff origin/feature/couleur-violette -m "Merge pull request #3: couleur harmonisée après rebase"
git push origin main
git push origin --delete feature/couleur-violette

# ------------------------------------------------------------------------------
# ÉTAPE 7 : Annuler proprement un commit partagé avec git revert
# ------------------------------------------------------------------------------
echo ""
echo "=== [ÉTAPE 7] Annulation propre d'un commit partagé (git revert) ==="
cd "$WORK_DIR/etudiantA"
git switch main && git pull
echo "# erreur volontaire" >> requirements.txt
git commit -am "Erreur volontaire"
git push origin main
git revert HEAD --no-edit
git push origin main

# ------------------------------------------------------------------------------
# ÉTAPE 8 : Marquer la version (tag annoté v1.0.0)
# ------------------------------------------------------------------------------
echo ""
echo "=== [ÉTAPE 8] Création et push du tag annoté v1.0.0 ==="
git tag -a v1.0.0 -m "Première version livrable"
git push origin v1.0.0

# ------------------------------------------------------------------------------
# ÉTAPE 9 : Protection de main + Tests des Défis (pre-commit flake8 + git undo)
# ------------------------------------------------------------------------------
echo ""
echo "=== [ÉTAPE 9] Test de protection de la branche main ==="
cp "$SOLUTIONS_DIR/pre-receive.protected-main" "$WORK_DIR/origin.git/hooks/pre-receive"
chmod +x "$WORK_DIR/origin.git/hooks/pre-receive"

set +e
echo "# push direct interdit" >> README_TEMP.txt
git add README_TEMP.txt
git commit -m "Test push direct sur main protégée"
git push origin main
PUSH_MAIN_RC=$?
set -e
echo "Code retour push direct sur main (refus attendu != 0) : $PUSH_MAIN_RC"

echo ""
echo "=== [DÉFI 1] Test de l'alias 'git undo' (annule le commit local non poussé) ==="
git undo
git status -s
rm -f README_TEMP.txt

echo ""
echo "=== [DÉFI 2] Test du hook pre-commit flake8 (rejet d'une erreur E501 / syntaxe) ==="
python3 -c "print('x = ' + 'a' * 130)" >> app.py
set +e
git add app.py
git commit -m "Test code non conforme flake8"
HOOK_RC=$?
set -e
echo "Code retour commit invalide (refus attendu != 0) : $HOOK_RC"
git checkout -- app.py

echo ""
echo "=== [VÉRIFICATION FINALE TP 2.1] ==="
echo "Nombre de commits sur main : $(git rev-list --count main)"
echo "Tags présents : $(git tag -l)"
git lg

echo ""
echo "=============================================================================="
echo " TP 2.1 (GIT EN ÉQUIPE) EXÉCUTÉ ET VALIDÉ AVEC SUCCÈS !"
echo " Traces : $LOG_FILE"
echo "=============================================================================="
