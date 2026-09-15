# Kodia Builder

Fork de VSCodium qui compile les binaires Kodia (`.dmg`, `.zip`, etc.) via
GitHub Actions, les publie sur [`kodia/binaries`](https://github.com/kodia/binaries/releases)
et met à jour [`kodia/versions`](https://github.com/kodia/versions).

## Installation / build local

Le chemin normal, c’est **GitHub Actions** (workflow `stable.yml`). Pour
rejouer en local :

```bash
git clone https://github.com/jcommaret/kodia-builder.git
cd kodia-builder
nvm install   # Node 22.22.3, voir .nvmrc
nvm use
```

Les scripts d’entrée sont à la racine (`ci_check.sh`, `build.sh`, …).
Détail : [`docs/SCRIPTS.md`](docs/SCRIPTS.md). Un build complet clone le
dépôt Kodia et applique les patches VSCodium : prévoir du disque et du temps.

Les fichiers `.patch` enlèvent la télémétrie et redirigent les mises à jour
vers Kodia plutôt que VS Code.

## Notes

- For an extensive list of all the places we edited inside of this VSCodium fork, search "Kodia" and "kodia". We also deleted some workflows we're not using in this VSCodium fork (insider-* and stable-spearhead).

- **Orchestrateur unique** : `.github/workflows/stable.yml` enchaîne un job `check`, un job `compile` (une seule compilation des sources), puis lance en parallèle les builds macOS, Linux (app), Windows et Linux REH. Évitez d’ajouter d’autres workflows avec les mêmes `on:` pour ne pas refaire `compile` trois fois sur chaque push.

- **Scripts shell** : points d’entrée à la racine (`ci_*.sh`, `build.sh`, …) ; bibliothèques et helpers dans [`scripts/`](scripts/) — voir [`docs/SCRIPTS.md`](docs/SCRIPTS.md).

- If you want to build and compile Kodia yourself, you just need to fork this repo and run the GitHub Workflows. If you want to handle auto updates too, just search for caps-sensitive "Kodia" and "kodia" and replace them with your own repo.

## Rebasing
- We often need to rebase `kodia` and `kodia-builder` onto `vscode` and `vscodium` to keep our build pipeline working when deprecations happen, but this is pretty easy. All the changes we made in `kodia/` are commented with the caps-sensitive word "Kodia" (except our images, which need to be done manually), so rebasing just involves copying the `vscode/` repo and searching "Kodia" to re-make all our changes. The same exact thing holds for copying the `vscodium/` repo onto this repo and searching "Kodia" and "kodia" to keep our changes. Just make sure the vscode and vscodium versions align.
