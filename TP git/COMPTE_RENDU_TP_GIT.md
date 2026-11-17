# Compte-Rendu Complet – TP 2.1 : Git en Équipe (GitHub Flow)

> **Module 2 – Partie A : Versioning avec Git**
> Ce document regroupe les réponses aux questions du [TP 2.1](file:///C:/Dominique/TPAFAIRE/TP%20git/TP2.1_Git.md), les solutions des défis et la validation automatisée via [`run_all_tp_git.sh`](run_all_tp_git.sh).

---

## 1. Réponses aux questions

### Question 1 : Quelle différence entre `git pull --rebase` et un `git pull` avec merge ?
* **`git pull` (mode merge par défaut)** récupère les commits distants et crée un **commit de fusion supplémentaire** (*merge commit*), produisant un historique en branches parallèles qui se rejoignent :
  ```text
  A --- B --- C (origin/main)
         \     \
          D --- M (main locale avec merge commit M)
  ```
* **`git pull --rebase`** met temporairement de côté vos commits locaux, avance la branche sur le dernier commit distant, puis **réapplique vos commits par-dessus**. L'historique reste **linéaire** et lisible :
  ```text
  A --- B --- C --- D' (main locale rebasée, historique linéaire)
  ```

### Question 2 : Pourquoi `--force-with-lease` est-il acceptable sur une branche personnelle et dangereux sur `main` ?
* Après un `git rebase`, l'historique local de votre branche personnelle a été réécrit (les hashes de commits ont changé) : un `git push` classique est refusé.
* **`git push --force-with-lease`** sur une **branche personnelle** (`feature/...`) vérifie d'abord que personne d'autre n'a poussé de nouveaux commits sur cette branche entre-temps (contrairement à `--force` qui écrase aveuglément) avant de mettre à jour la Pull Request.
* Sur **`main`** (branche partagée par toute l'équipe et la CI), réécrire l'historique casserait l'environnement local de tous les collègues et détruirait la traçabilité des versions livrées. C'est pourquoi la protection de `main` bloque les *force-pushes* et qu'on utilise **`git revert`** (qui ajoute un nouveau commit inverse sans réécrire le passé).

### Question 3 : Un mot de passe a été commité il y a 3 commits. Que faites-vous ?
1. **Révoquer et changer immédiatement le mot de passe** (ou la clé API / token) auprès du service concerné : dès qu'un secret a été poussé, même brièvement, il doit être considéré comme compromis (il reste dans les logs, clones ou caches distants).
2. **Ne jamais se contenter d'un simple commit de suppression** : le secret resterait accessible dans l'historique Git (`git log -p`).
3. **Purger l'historique si nécessaire** avec `git filter-repo` (puis `git push --force-with-lease` et resynchronisation des clones de l'équipe), et activer un contrôle préventif (hook `pre-commit` / scan `gitleaks` en CI).

---

## 2. Solutions des Défis

1. **Alias `git undo`** (annule le dernier commit local non poussé en gardant les modifications dans le répertoire de travail) :
   ```bash
   git config --global alias.undo "reset --soft HEAD~1"
   ```
2. **Hook `pre-commit` bloquant tout commit non conforme à `flake8`** ([`solutions/pre-commit`](solutions/pre-commit)) :
   ```sh
   #!/bin/sh
   docker run --rm -v "$PWD":/src -w /src python:3.12-slim \
     sh -c "pip install -q flake8==7.1.1 && flake8 ." || {
     echo "flake8 a trouvé des erreurs : commit refusé"; exit 1; }
   ```
3. **Protection de `main`** ([`solutions/pre-receive.protected-main`](solutions/pre-receive.protected-main)) : simule le refus d'un push direct et des force-pushes sur `refs/heads/main`.

---

## 3. Vérifications (exécutées via `run_all_tp_git.sh`)

- [x] Dépôt `legeni-webapp` initialisé avec `.gitignore` et ≥ 5 commits aux messages explicites
- [x] Pull Requests simulées (branches `feature/titre`, `feature/couleur-verte`, `feature/couleur-violette`) et fusionnées
- [x] Conflit sur `app.py` provoqué, marqueurs `<<<<<<<`/`=======`/`>>>>>>>` observés, résolu avec `git rebase --continue` et validé par `docker build --target test`
- [x] Commit d'erreur annulé proprement par `git revert HEAD --no-edit`
- [x] Tag annoté `v1.0.0` créé et poussé, protection de `main` vérifiée, alias `git undo` et hook `pre-commit` validés
