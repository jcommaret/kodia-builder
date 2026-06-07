# Kodia Builder

This is a fork of VSCodium, which has a nice build pipeline that we're using for Kodia. Big thanks to the CodeStory team for inspiring this.

The purpose of this VSCodium fork is to run [Github Actions](https://github.com/kodia/kodia-builder/actions). These actions build all the Kodia assets (.dmg, .zip, etc), store these binaries on a release in [`kodia/binaries`](https://github.com/kodia/binaries/releases), and then set the latest version in a text file on [`kodia/versions`](https://github.com/kodia/versions) so Kodia knows how to update to the latest version.

The  `.patch` files from VSCodium get rid of telemetry in Kodia (the core purpose of VSCodium) and change VSCode's auto-update logic so updates are checked against `kodia` and not `vscode` (we just had to swap out a few URLs). These changes described by the `.patch` files are applied to `kodia/` during the workflow run, and they're almost entirely straight from VSCodium, minus a few renames to Kodia.

## Notes

- For an extensive list of all the places we edited inside of this VSCodium fork, search "Kodia" and "kodia". We also deleted some workflows we're not using in this VSCodium fork (insider-* and stable-spearhead).

- **Orchestrateur unique** : `.github/workflows/stable.yml` enchaîne un job `check`, un job `compile` (une seule compilation des sources), puis lance en parallèle les builds macOS, Linux (app), Windows et Linux REH. Évitez d’ajouter d’autres workflows avec les mêmes `on:` pour ne pas refaire `compile` trois fois sur chaque push.

- **Scripts shell** : points d’entrée à la racine (`ci_*.sh`, `build.sh`, …) ; bibliothèques et helpers dans [`scripts/`](scripts/) — voir [`docs/SCRIPTS.md`](docs/SCRIPTS.md).

- If you want to build and compile Kodia yourself, you just need to fork this repo and run the GitHub Workflows. If you want to handle auto updates too, just search for caps-sensitive "Kodia" and "kodia" and replace them with your own repo.

## Rebasing
- We often need to rebase `kodia` and `kodia-builder` onto `vscode` and `vscodium` to keep our build pipeline working when deprecations happen, but this is pretty easy. All the changes we made in `kodia/` are commented with the caps-sensitive word "Kodia" (except our images, which need to be done manually), so rebasing just involves copying the `vscode/` repo and searching "Kodia" to re-make all our changes. The same exact thing holds for copying the `vscodium/` repo onto this repo and searching "Kodia" and "kodia" to keep our changes. Just make sure the vscode and vscodium versions align.
