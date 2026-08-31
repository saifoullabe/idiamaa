#!/usr/bin/env bash
# Prépare le dossier « site/ » que Vercel publie.
#
# À lancer depuis la racine du projet, après toute modification du code :
#   bash outils/preparer_site.sh
#
# Ensuite : git add -A && git commit -m "..." && git push
# Vercel republie tout seul dans la minute qui suit.

set -e
cd "$(dirname "$0")/.."

echo "→ Compilation de la version web…"
flutter build web --release

echo "→ Recopie dans site/"
rm -rf site
mkdir -p site
cp -r build/web/. site/

# Ces fichiers ne servent qu'à déchiffrer les traces d'erreur dans la
# console du navigateur. 8 Mo inutiles en ligne : on les enlève.
find site -name "*.symbols" -delete
rm -f site/.last_build_id

echo "→ Terminé. Poids du site :"
du -sh site
