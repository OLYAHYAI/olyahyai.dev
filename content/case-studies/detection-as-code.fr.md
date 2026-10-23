---
title: "Detection as code : versionner le jeu de règles d'un SIEM en production"
slug: "detection-as-code"
date: 2026-09-14
weight: 3
summary: "Mettre le jeu de règles Wazuh sous Git sans étape de synchronisation susceptible de dériver, et une suite de non-régression construite à partir de vraies lignes de log, prouvée par un contrôle négatif qui fait revenir un ancien bug."
tags: ["Wazuh", "Git", "Tests", "Gestion des changements"]
stack: ["Wazuh", "Git", "Bash", "Python"]
---

## Pourquoi

Les décodeurs et règles sur mesure sont du code. Jusque-là, ils étaient modifiés directement sur le manager : pas d'historique, pas de relecture, et aucun moyen de savoir si un changement cassait quelque chose qui marchait. L'étude de cas précédente montre ce que ça coûte : [un décodeur mort en silence pendant trois jours]({{< relref "case-studies/silent-failures" >}}).

## Git là où vivent les fichiers

La pratique habituelle : un dépôt séparé, plus un script qui copie les fichiers dans le répertoire de configuration du SIEM. Je l'ai écartée : une étape de synchronisation est une chose de plus qui peut se désaligner sans bruit de ce qui tourne réellement.

À la place, le dépôt **est** le répertoire de configuration. Les fichiers qui doivent vivre ailleurs (le script d'active response, le watchdog) y sont reliés par lien symbolique, si bien qu'un seul `git log` couvre tout ce qui façonne la détection.

Comme ce répertoire contient aussi des clés et des secrets d'agents, le `.gitignore` fonctionne à l'envers : **tout refuser**, puis autoriser explicitement les fichiers de règles, de décodeurs et de listes. Un audit des secrets du premier commit a confirmé que rien de sensible n'était suivi.

## Une suite de tests issue du trafic réel

Chaque test est une vraie ligne de log, plus les champs que le décodeur doit extraire (nom du décodeur, IP source et destination, ports, action, ID de règle, niveau).

Deux détails ont fait la différence :

- **Le corpus vient du JSON archivé (`full_log`), pas de l'archive texte.** L'archive texte ajoute son propre préfixe : un test construit à partir d'elle vérifie une ligne que le décodeur ne voit jamais.
- **Les valeurs attendues viennent d'un parseur indépendant,** pas de la sortie du décodeur lui-même. Sinon le test prouve seulement que le décodeur est d'accord avec lui-même.

L'outil de log-test de Wazuh cachait aussi deux pièges : il écrit ses résultats sur stderr, et il ne recharge pas le jeu de règles. Après un changement, il faut redémarrer le manager puis attendre 60 à 90 secondes avant de tester, sinon la suite teste les anciennes règles.

## Le contrôle négatif

Une suite de tests qui n'a jamais échoué ne prouve rien. J'ai donc volontairement remis l'ancien décodeur cassé et lancé la suite :

```
ancien décodeur   2/11 PASS   srcip = "64"   (le TTL)
                              dstip = "53770"  (l'IP-ID)
décodeur corrigé 11/11 PASS
```

La suite a attrapé exactement le bug passé inaperçu pendant trois jours, avec les mêmes valeurs fausses. Elle est passée depuis à **20/20**, en plus des huit scénarios hors ligne du watchdog.

## La procédure de changement

Chaque modification du jeu de règles suit les cinq mêmes étapes, écrites pour que je les suive aussi un soir de fatigue :

1. créer une branche ;
2. vérifier la syntaxe avec `wazuh-analysisd -t` ;
3. redémarrer le manager et attendre ;
4. lancer la suite : tout vert, ou retour arrière ;
5. committer avec un message qui dit *pourquoi*.

## Ce que j'en retiens

Versionner ne fait que la moitié du travail. Un test ne prouve quelque chose qu'une fois qu'on l'a vu échouer pour la bonne raison.
