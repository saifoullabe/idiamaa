# IDIAMA Agro

Gestion des fermes avicoles IDIAMA — production d'œufs, recettes, dépenses,
dépôts d'argent, stocks, signalements et pointage.

Trois espaces : **administrateur** (toutes les fermes), **gérant** (sa ferme),
**fermier** (ses saisies).

Un seul code source, deux façons d'y accéder :

| | |
|---|---|
| **Android** | `flutter build apk --release` puis `flutter build appbundle --release` |
| **Web** | `bash outils/preparer_site.sh`, puis `git push` — Vercel republie seul |

---

## Mise en route

1. **Base de données** — lancer `sql/01_idiama_base.sql` puis
   `sql/02_idiama_admin.sql` dans le SQL Editor de Supabase.
   Voir `GUIDE_INSTALLATION.txt` pour le détail.
2. **Brancher l'application** — renseigner l'adresse du projet et la clé
   publique dans `lib/core/config.dart`.
3. Compiler.

Première connexion : identifiant `admin`. Le mot de passe est tiré au
hasard par `02_idiama_admin.sql` et affiché une seule fois, à l'écran.
Aucun mot de passe n'est écrit dans ce dépôt.

---

## Comment c'est rangé

```
lib/
  core/        config, thème, formats (GNF, dates), constantes métier
  models/      les objets de la ferme tels qu'ils arrivent de la base
  data/        api.dart (tous les appels Supabase) · etat.dart (l'état vivant)
  widgets/     briques d'affichage, formulaires, graphiques
  screens/     un fichier par écran
sql/           les deux fichiers à passer dans Supabase
site/          la version web compilée — c'est ce dossier que Vercel publie
outils/        preparer_site.sh
```

## Les règles du métier, à ne pas réinventer

- **1 alvéole = 30 œufs.** La valeur d'une saisie = nombre d'alvéoles ×
  prix d'alvéole **du bâtiment** (hérité de la ferme, modifiable ferme par ferme).
- **Une saisie ne compte qu'une fois validée**, et elle n'est validée que par
  l'échelon juste au-dessus : celle d'un fermier par son gérant, celle d'un
  gérant par l'administrateur. Avant ça, elle n'entre dans aucun total.
- **Un fermier ne peut rien saisir tant qu'il n'a pas pointé son arrivée.**
- **Une seule ligne de production par bâtiment et par jour**, quel que soit
  celui qui l'a saisie — sinon le gérant qui repasse derrière son fermier
  ferait compter les mêmes œufs deux fois.
- La connexion se fait par **identifiant**, jamais par e-mail. L'application
  colle `@idiamaa.com` derrière en coulisses, parce que Supabase exige une
  adresse. Conséquence : dans Supabase, **« Confirm email » doit rester
  décoché**.
- Aucun `dart:io` dans le code : les photos et documents circulent en octets
  (`FichierChoisi`), sinon la version web ne compile pas.

## Ce qui ne doit jamais partir sur GitHub

`android/key.properties` (mots de passe de signature) et les fichiers `.jks`.
Ils sont dans `.gitignore`. La clé de signature elle-même vit hors du projet,
dans `C:\Users\bassi\cles\idiama-agro.jks` — **si elle est perdue, plus aucune
mise à jour ne peut s'installer par-dessus l'application déjà installée.**
