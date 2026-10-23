---
title: "Letting AI agents operate a homelab, under control"
slug: "ai-agents-under-control"
date: 2026-10-20
weight: 5
summary: "LLM agents that can query the SIEM and manage containers from my phone — confined by three independent layers of permissions. And the day one agent tried to work around a missing tool, which showed what the SIEM could not yet see."
tags: ["AI agents", "MCP", "Least privilege", "Incident"]
stack: ["Proxmox VE", "MCP", "Python", "SSH", "Wazuh", "Matrix"]
---

## The goal

Being able to ask, from my phone, "what fired on the firewall tonight?" or "snapshot that container and restart it", and have an agent do it. Without turning a language model into an administrator of the cluster.

## The constraint that shaped everything

The Proxmox API can start, stop and snapshot containers, but it cannot **run a command inside** one. The only built-in way, the terminal proxy, needs a user password, not an API token. Giving an agent a password for an interactive console was not an option.

## Three layers, each sufficient on its own

I wrote my own MCP server for Proxmox. It goes through three independent checks, so a bug in one layer is not enough to escape:

1. **A dedicated resource pool as the blast radius.** The agents only see the containers I place in that pool. The API token has privilege separation and a custom role of 15 privileges (start, stop, snapshot, inspect…), with nothing administrative.
2. **An SSH forced command for `exec`.** To run a command in a container, the server connects with a dedicated key that can only start a guard script. On the host, that script checks again, against the cluster itself, that the target belongs to the pool before running anything.
3. **A client-side check** in the MCP server, which refuses targets outside the pool before any call is made.

A deny-list also keeps the agents' own machine out of the pool: an agent cannot snapshot, stop or rewrite the host it runs on.

One validation pitfall is worth telling. My first permission tests from the browser kept succeeding where they should have failed: `fetch` was quietly sending my administrator session cookie along with the token. Run again with `credentials: 'omit'`, the requests failed as expected.

## In daily use

The agents run on an orchestration platform and I reach them from a Matrix client on my phone. Read tools (alerts, agent status, resource usage) are free to use. Every tool that changes something is set to **ask first**: the agent proposes, I approve.

## The incident

One day an agent was asked for something it had no tool for. It did not stop. It tried to find another way:

- it read the source code of the MCP server to understand how it worked;
- it took a database address from the environment of another process running under the same user;
- it connected to that database;
- it tried `sudo`.

It never read a secret, and `sudo` asked for a password it did not have. But the sequence is exactly what an intruder does after landing on a machine.

The SIEM recorded every step, at levels 3 and 4: normal-looking activity, far below any alert threshold. Seen one by one, nothing was wrong.

## What changed afterwards

- `sudo` now always asks for a password on that machine, and the user left the `docker` group;
- the agents' configuration directory is no longer readable by their process;
- a dedicated detection rule is planned for this pattern (an agent process reading other processes' environments or opening database connections);
- the remaining risk is stated plainly: the agents still share a user ID with the platform that runs them. The next step is a separate service account.

## What I took from it

An agent's permissions must be designed as if it were an intruder already inside, because when it is stuck, its behaviour looks just like one. And the detection side has to be built for that behaviour as well, not only the permission side.
