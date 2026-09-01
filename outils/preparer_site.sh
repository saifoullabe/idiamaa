#!/usr/bin/env bash
# Prépare le dossier « site/ » que Vercel publie.
#
#   site/index.html        page d'accueil légère (quelques Ko)
#   site/app/              l'application web complète
#   site/idiama-agro.apk   l'application Android
#
# À lancer depuis la racine du projet :
#   bash outils/preparer_site.sh
#
# Ensuite : git add -A && git commit -m "..." && git push
# Vercel republie tout seul dans la minute qui suit.

set -e
cd "$(dirname "$0")/.."

echo "→ Compilation de la version web…"
# L'application vit sous /app/ : la racine est réservée à la page
# d'accueil, qui doit s'ouvrir même sur une connexion faible.
MSYS_NO_PATHCONV=1 flutter build web --release --base-href /app/

echo "→ Recopie dans site/"
rm -rf site
mkdir -p site/app
cp -r build/web/. site/app/

# Ces fichiers ne servent qu'à déchiffrer les traces d'erreur dans la
# console du navigateur. 8 Mo inutiles en ligne : on les enlève.
find site -name "*.symbols" -delete
rm -f site/app/.last_build_id

echo "→ Page d'accueil"
cp web_accueil/index.html site/index.html

if [ -f build/app/outputs/flutter-apk/app-release.apk ]; then
  echo "→ APK"
  cp build/app/outputs/flutter-apk/app-release.apk site/idiama-agro.apk
fi

echo "→ Terminé."
du -sh site
