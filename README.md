# RimWorld Multiplayer

Script d'installation de RimWorld Multiplayer sur un serveur ProxMox.

## Prérequis sur les machines de jeu qui se connecteront au serveur

Installez les mods suivants sur les machines de jeu :
- [Prepatcher — Zetrith](https://github.com/Zetrith/Prepatcher)
- [Multiplayer — Zetrith](https://github.com/Zetrith/Multiplayer)

## Installation du serveur sur le ProxMox

Exécutez les commandes suivantes dans votre terminal :

```bash
export COMMUNITY_SCRIPTS_URL=https://raw.githubusercontent.com/Kromagnsss/Rimworld-multiplayer/main
bash -c "$(curl -fsSL "$COMMUNITY_SCRIPTS_URL/ct/rimworldmultiplayer.sh")"
```
