---
title: "Quand le SIEM devient aveugle sans la moindre erreur"
slug: "pannes-silencieuses"
date: 2026-09-14
weight: 2
summary: "Trois pannes silencieuses en deux jours, aucune signalée par le SIEM lui-même. Remonter à une cause racine commune, puis construire un watchdog qui les aurait détectées toutes les trois."
tags: ["Wazuh", "Décodeurs", "Supervision", "Cause racine"]
stack: ["Wazuh", "syslog-ng", "pfSense", "Python", "cron"]
---

## Le problème que personne n'alerte

En deux jours, trois parties de la chaîne ont cessé de fonctionner. À chaque fois, le SIEM a continué de tourner, sans erreur, en produisant toujours des alertes : simplement moins, ou fausses.

| Panne | Comment elle a été trouvée | Durée d'aveuglement |
|---|---|---|
| Le trafic Suricata coupé après le passage du flux syslog en TLS (le tunnel autorisait la mauvaise adresse source) | par moi, lors d'une revue manuelle | quelques heures |
| Les alertes pfSense portaient des numéros de port et des TTL dans leurs champs IP source/destination | par hasard, en construisant l'enrichissement GeoIP | trois jours ou plus |
| Les événements DHCP étaient reçus mais jamais décodés | par le watchdog décrit plus bas, pendant sa construction | trois jours ou plus |

C'est le pire mode de défaillance pour un SOC. Un tableau de bord avec moins d'alertes ressemble à une journée calme. Et cela rend toute mesure de couverture vide de sens : une détection manquée devient indiscernable d'un collecteur cassé.

## Une seule cause racine pour deux d'entre elles

Les logs du pare-feu arrivent via syslog-ng, qui enveloppe chaque message dans sa propre enveloppe (compteur d'octets, métadonnées structured-data, un en-tête syslog imbriqué). Les décodeurs d'origine étaient ancrés au **début de la ligne** :

```
<prematch>^dhcpd \d+ - - </prematch>
```

Avec la nouvelle enveloppe, `dhcpd` se trouvait vers le 170ᵉ caractère. Le décodeur ne correspondait jamais, et les événements tombaient en lignes non décodées : présents dans les archives (177 par jour), absents des alertes. Les IP source/destination fausses avaient la même origine : une expression régulière ancrée sur l'enveloppe capturait les mauvais groupes une fois l'enveloppe modifiée, si bien que TTL et IP-ID atterrissaient dans les champs d'adresse.

La correction a consisté à s'ancrer sur ce qui est propre à pfSense, pas sur le transport :

```
<prematch type="pcre2">\sdhcpd\s+\d+\s+-\s+-\s+</prematch>
```

Vérifiée hors ligne sur les lignes archivées avant déploiement : **177/177** reconnues (0/177 avant). La part horaire d'IP source valides raconte la suite :

```
03h..12h  srcip valide = 0,0 %     <- décodeur mort, aucune alerte nulle part
13h       srcip valide = 92,4 %    <- correctif déployé pendant cette heure
14h       srcip valide = 100,0 %
```

## Le watchdog

Le correctif fermait ces bugs. La vraie question était : comment être prévenu du prochain ? Une petite sonde tourne désormais toutes les 30 minutes :

- elle lit le journal d'alertes **de façon incrémentale** (offset mémorisé, rotation détectée par l'inode, lignes complètes uniquement), sans jamais relire un fichier de 400 Mo ;
- pour chaque source, elle calcule le débit d'événements, la part d'adresses IP valides et l'âge du dernier événement ;
- elle écrit **une ligne JSON** avec un verdict : `ok`, `degraded`, `critical` ou `bootstrap` (premier passage ou rotation, qui n'alerte jamais).

Toute la logique de décision est dans le script, testable hors ligne. Les règles Wazuh ne font que reconnaître le texte du verdict : pas de comparaisons numériques cachées dans du XML.

Les seuils viennent de bases mesurées et se situent environ trois fois sous l'heure nocturne la plus calme :

| Contrôle | degraded | critical |
|---|---|---|
| Débit pfSense | < 50/min | < 10/min |
| Débit Suricata | < 15/min | < 3/min |
| IP valides (par source) | < 98 % | < 50 % |
| Dernier événement DHCP | > 24 h | — |

Trois règles transforment le verdict en alertes : niveau 3 pour `ok` (volontairement, pour garder une série temporelle de santé dans le tableau de bord), 7 pour `degraded`, 12 pour `critical`, avec la raison dans la description. Le groupe de règles est `soc_health`, jamais `suricata` : une alerte de santé de niveau 12 ne doit pas pouvoir déclencher le bannissement automatique d'IP.

## Preuve

Huit scénarios hors ligne, dont les trois pannes réellement vécues, renvoient tous le verdict attendu (**8/8**). En production, le premier passage a rendu `ok` avec 100 % d'adresses valides, et des lignes `degraded`/`critical` forgées ont produit les alertes de niveau 7 et 12.

## Limites, dites clairement

- La sonde s'exprime à travers Wazuh. Si le manager s'arrête complètement, elle se tait aussi. Un heartbeat séparé dans n8n alerte désormais quand aucune alerte n'est arrivée depuis trois heures.
- Les seuils de débit détectent les effondrements, pas une baisse lente de 20 à 30 %. Une comparaison avec la même heure des jours précédents le ferait.

## Ce que j'en retiens

« Pas d'erreur » ne veut pas dire « ça marche ». Un SIEM doit mesurer ses propres entrées, avec des seuils tirés des données, et ce contrôle doit être testable hors de la production.
