---
title: "Un SOC/SOAR auto-hébergé sur un homelab à trois nœuds"
slug: "soc-soar-auto-heberge"
date: 2026-10-23
weight: 1
summary: "L'architecture de mon projet de fin d'études : ce qu'il collecte, comment il réagit et les règles sur lesquelles il repose. Aucune exposition publique, chaque changement versionné, chaque affirmation testée."
tags: ["Architecture", "Wazuh", "SOAR", "Proxmox"]
stack: ["Proxmox VE", "pfSense", "Suricata", "CrowdSec", "Zeek", "Wazuh", "n8n", "Velociraptor", "Tailscale"]
---

## L'objectif

Construire un centre opérationnel de sécurité qu'un jury peut voir fonctionner : il collecte, détecte, enrichit, réagit seul et peut prouver sa couverture MITRE ATT&CK. Tout tourne sur un cluster Proxmox de trois nœuds, chez moi, à côté des services qu'il protège.

Trois règles ont guidé chaque décision :

1. **Aucune exposition publique.** Le SIEM, la plateforme d'automatisation et les interfaces d'administration ne sont joignables que depuis le LAN ou via Tailscale. Rien n'écoute sur Internet.
2. **Corriger la cause racine, jamais le symptôme.** Un problème est clos quand les logs l'expliquent, pas quand il cesse de se voir.
3. **Reproductible et versionné.** Règles de détection, scripts de réponse et changements d'infrastructure vivent dans Git, avec des tests.

## Ce qu'il collecte

| Couche | Source | Notes |
|---|---|---|
| Périmètre | Logs du pare-feu pfSense, IDS Suricata (EVE JSON), CrowdSec, DHCP, DNS | Transmis par syslog-ng en **TLS** (PKI interne) |
| Réseau | Zeek sur un port miroir | Logs connexions, DNS, HTTP, TLS et SSH, plus une détection de scans maison |
| Hôtes | Agents Wazuh sous Linux, Windows (Sysmon) et Android | Intégrité des fichiers, installations de paquets, authentification, audits CIS |
| Forensique | Velociraptor sur une dizaine de postes | Son propre journal d'audit remonte dans Wazuh |

Wazuh (manager + indexer) sert de SIEM. Des décodeurs et règles sur mesure transforment les lignes brutes en champs consultables, corrélables et rattachés à des techniques ATT&CK. Une couche GeoIP et un tableau de bord « carte des menaces » complètent l'ensemble.

## Comment il réagit

- **Blocage automatique d'IP.** Une alerte Suricata critique déclenche une Active Response Wazuh qui ajoute l'adresse source à une table pfSense, via un compte SSH restreint à trois commandes exactement. Le bannissement expire au bout de dix minutes. [Étude de cas →]({{< relref "case-studies/active-response" >}})
- **Enrichissement et notification (n8n).** Les alertes au-dessus d'un seuil partent vers un workflow n8n : catégorisation, dédoublonnage, réputation AbuseIPDB pour les adresses publiques, corrélation (même source sur trois règles différentes en 15 minutes), puis message Telegram. Un résumé quotidien et un heartbeat toutes les 30 minutes tournent dans le même workflow.
- **Exploitation assistée par IA.** Des agents LLM peuvent interroger Wazuh et le cluster Proxmox via des serveurs MCP que j'ai écrits, depuis un salon de discussion sur mon téléphone. Tout ce qui modifie l'infrastructure attend mon accord. [Étude de cas →]({{< relref "case-studies/ai-agents" >}})

## Comment je sais qu'il fonctionne

Un SOC qui peut tomber en panne sans s'en rendre compte est pire que pas de SOC, car il donne une fausse confiance. Deux mécanismes répondent à la question *« comment savez-vous qu'il marche encore ? »* :

- **Un watchdog de santé** mesure toutes les 30 minutes le débit d'événements et la part d'adresses correctement décodées par source, et lève ses propres alertes quand la chaîne se dégrade. [Étude de cas →]({{< relref "case-studies/silent-failures" >}})
- **Une suite de non-régression** rejoue de vraies lignes de log contre le jeu de règles avant chaque commit. [Étude de cas →]({{< relref "case-studies/detection-as-code" >}})

## Laboratoire purple team

Un pont réseau isolé héberge des cibles volontairement vulnérables (un contrôleur de domaine Active Directory avec Sysmon et l'audit Kerberos/DCSync, DVWA, Metasploitable 3) et une VM d'attaque. Des tests Atomic Red Team y mesurent les techniques réellement détectées, et les manques alimentent de nouvelles règles.

## Où il en est

Les boucles de détection, de réponse et de notification tournent en production dans le homelab. Le travail en cours : mesurer la couverture ATT&CK sur le labo, passer le déploiement sous Ansible et construire un tableau de bord exécutif. Ce site fait lui-même partie de la plateforme : il est construit depuis une instance Forgejo auto-hébergée, sur le même cluster, surveillée par le même SIEM.
