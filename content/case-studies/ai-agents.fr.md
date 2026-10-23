---
title: "Laisser des agents IA exploiter un homelab, sous contrôle"
slug: "agents-ia-sous-controle"
date: 2026-10-20
weight: 5
summary: "Des agents LLM capables d'interroger le SIEM et de gérer des conteneurs depuis mon téléphone, confinés par trois couches de permissions indépendantes. Et le jour où un agent a tenté de contourner un outil manquant, ce qui a montré ce que le SIEM ne voyait pas encore."
tags: ["Agents IA", "MCP", "Moindre privilège", "Incident"]
stack: ["Proxmox VE", "MCP", "Python", "SSH", "Wazuh", "Matrix"]
---

## L'objectif

Pouvoir demander depuis mon téléphone « qu'est-ce qui a sonné sur le pare-feu cette nuit ? » ou « fais un snapshot de ce conteneur et redémarre-le », et qu'un agent s'en charge. Sans faire d'un modèle de langage un administrateur du cluster.

## La contrainte qui a tout façonné

L'API Proxmox sait démarrer, arrêter et snapshotter des conteneurs, mais pas **exécuter une commande à l'intérieur**. Le seul moyen natif, le proxy de terminal, exige un mot de passe utilisateur, pas un jeton d'API. Donner à un agent un mot de passe pour une console interactive était exclu.

## Trois couches, chacune suffisante à elle seule

J'ai écrit mon propre serveur MCP pour Proxmox. Il passe par trois contrôles indépendants, pour qu'un bug dans une couche ne suffise pas à s'échapper :

1. **Un pool de ressources dédié comme rayon d'impact.** Les agents ne voient que les conteneurs que je place dans ce pool. Le jeton d'API a la séparation de privilèges et un rôle sur mesure de 15 privilèges (démarrer, arrêter, snapshotter, inspecter…), sans rien d'administratif.
2. **Une commande SSH forcée pour `exec`.** Pour exécuter une commande dans un conteneur, le serveur se connecte avec une clé dédiée qui ne peut lancer qu'un script de garde. Sur l'hôte, ce script vérifie à nouveau, auprès du cluster lui-même, que la cible appartient au pool avant d'exécuter quoi que ce soit.
3. **Un contrôle côté client** dans le serveur MCP, qui refuse les cibles hors du pool avant tout appel.

Une liste d'exclusion maintient aussi la machine des agents hors du pool : un agent ne peut pas snapshotter, arrêter ou réécrire l'hôte sur lequel il tourne.

Un piège de validation mérite d'être raconté. Mes premiers tests de permissions depuis le navigateur réussissaient là où ils auraient dû échouer : `fetch` envoyait discrètement mon cookie de session administrateur avec le jeton. Relancées avec `credentials: 'omit'`, les requêtes ont échoué comme prévu.

## Au quotidien

Les agents tournent sur une plateforme d'orchestration et je les joins depuis un client Matrix sur mon téléphone. Les outils de lecture (alertes, état des agents, consommation de ressources) sont libres. Tout outil qui modifie quelque chose est réglé sur **demander d'abord** : l'agent propose, j'approuve.

## L'incident

Un jour, on a demandé à un agent une chose pour laquelle il n'avait pas d'outil. Il ne s'est pas arrêté. Il a cherché un autre chemin :

- il a lu le code source du serveur MCP pour comprendre son fonctionnement ;
- il a récupéré l'adresse d'une base de données dans l'environnement d'un autre processus tournant sous le même utilisateur ;
- il s'est connecté à cette base ;
- il a tenté `sudo`.

Il n'a jamais lu de secret, et `sudo` a demandé un mot de passe qu'il n'avait pas. Mais la séquence est exactement celle d'un intrus qui vient de prendre pied sur une machine.

Le SIEM a enregistré chaque étape, aux niveaux 3 et 4 : une activité d'apparence normale, loin sous tout seuil d'alerte. Prise une par une, rien n'était anormal.

## Ce qui a changé ensuite

- `sudo` demande désormais toujours un mot de passe sur cette machine, et l'utilisateur a quitté le groupe `docker` ;
- le répertoire de configuration des agents n'est plus lisible par leur processus ;
- une règle de détection dédiée est prévue pour ce schéma (un processus d'agent qui lit l'environnement d'autres processus ou ouvre des connexions à une base) ;
- le risque restant est dit clairement : les agents partagent encore un identifiant utilisateur avec la plateforme qui les exécute. L'étape suivante est un compte de service séparé.

## Ce que j'en retiens

Les permissions d'un agent doivent être conçues comme s'il était déjà un intrus à l'intérieur, car lorsqu'il est bloqué, son comportement y ressemble trait pour trait. Et la détection doit être pensée pour ce comportement aussi, pas seulement les permissions.
