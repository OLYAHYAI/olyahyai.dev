---
title: "Blocage automatique d'IP sans donner au SIEM les clés du pare-feu"
slug: "blocage-ip-automatique"
date: 2026-09-13
weight: 4
summary: "Une alerte IDS critique bannit l'attaquant au pare-feu en quelques secondes, pour dix minutes. Le plus intéressant est ce que le SIEM n'a pas le droit de faire, et deux bugs que seul un vrai test de bout en bout a révélés."
tags: ["Active Response", "pfSense", "Suricata", "Moindre privilège"]
stack: ["Wazuh", "pfSense", "Suricata", "SSH", "Bash", "Telegram"]
---

## L'objectif

Quand Suricata lève une alerte critique, l'adresse source doit être bloquée au pare-feu sans m'attendre, puis libérée automatiquement. Le SIEM doit pouvoir faire exactement cela, et rien d'autre.

## Conception : une table, un compte, trois commandes

pfSense n'a pas d'API REST officielle, et je ne voulais pas installer un paquet non officiel avec des droits d'administration sur le pare-feu. La conception repose uniquement sur des fonctions natives :

- un **alias de type table pf**, utilisé par une règle de blocage placée au-dessus de toutes les autres, y compris celles de pfBlockerNG. Bannir une adresse revient à l'ajouter à la table : aucune modification de règle, aucun rechargement. L'alias contient une adresse de la plage de documentation (TEST-NET), pour ne jamais être vide et que la règle ne disparaisse jamais ;
- un **compte dédié et non privilégié** sur le pare-feu, joignable uniquement avec sa propre clé SSH, dont les droits sudo couvrent **exactement trois** commandes `pfctl` : ajouter à la table, retirer de la table, lister la table ;
- un script d'**Active Response Wazuh** sur le manager, qui lit l'alerte, appelle SSH et journalise chaque action.

| Paramètre | Valeur | Pourquoi |
|---|---|---|
| Déclencheur | groupe de règles `suricata`, niveau ≥ 10 | uniquement les alertes IDS critiques |
| Durée | 600 s, puis retrait automatique | une erreur coûte dix minutes, pas un verrouillage |
| Notification | Telegram, au bannissement uniquement | pas de bruit au retrait |

Si le SIEM est compromis, la seule action root qu'il peut mener sur le pare-feu est d'ajouter ou de retirer des adresses dans cette table. Il ne peut ni modifier les règles, ni installer de paquets, ni exécuter quoi que ce soit d'autre en root.

## Deux bugs trouvés avant la mise en service

1. **La clé SSH était refusée.** Permissions, sshd et PAM étaient corrects. La cause : la clé publique collée dans l'interface web du pare-feu différait de la clé privée de deux caractères (`Z` lu comme `2`, `1` lu comme `l`). `cmp -l` entre la clé installée et celle dérivée par `ssh-keygen -y` a montré les octets exacts, corrigés un par un plutôt que retapés.
2. **La règle d'escalade ne pouvait jamais correspondre.** La règle qui élève les alertes Suricata critiques au niveau 10 existait déjà, mais elle avait été placée *à l'intérieur* du bloc de règles pfSense. Elle héritait des mauvais groupes et ne portait jamais `suricata` : la réponse ne se serait jamais déclenchée, quel que soit le trafic.

## Le tester pour de vrai

Forger une alerte ne teste que la moitié de la chaîne. Une règle Suricata temporaire reconnaissait une chaîne magique inoffensive, et un `curl` lancé depuis le pare-feu lui-même la faisait sortir par l'interface surveillée : vrai trafic, vraie alerte IDS, vrai décodage, vraie réponse.

Résultat : alerte → bannissement → message Telegram, puis retrait dix minutes plus tard, visible dans la table du pare-feu.

## Leçons

- Le premier déclenchement réel est arrivé en retard : le manager avait été validé et rechargé après les changements de configuration, mais pas complètement redémarré. Avant tout test réel, je fais désormais un **redémarrage complet**.
- Avant de retirer une entrée de la table à la main, vérifier le journal de réponse : l'adresse de documentation ressemble à une adresse bannie dans un simple listing.
- Le message Telegram est construit avec `jq`, pas par concaténation de chaînes : un champ d'alerte contenant des guillemets ne doit ni casser le JSON, ni s'y injecter.

## Ce que j'en retiens

Une réponse automatisée est sûre quand son pire cas est petit et connu d'avance. Ici, le pire cas tient en une phrase et dure dix minutes.
