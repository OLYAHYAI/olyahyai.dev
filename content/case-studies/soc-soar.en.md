---
title: "A self-hosted SOC/SOAR on a three-node homelab"
slug: "self-hosted-soc-soar"
date: 2026-10-23
weight: 1
summary: "The architecture of my Master's final-year project: what it collects, how it reacts, and the rules it is built on — no public exposure, every change versioned, every claim tested."
tags: ["Architecture", "Wazuh", "SOAR", "Proxmox"]
stack: ["Proxmox VE", "pfSense", "Suricata", "CrowdSec", "Zeek", "Wazuh", "n8n", "Velociraptor", "Tailscale"]
---

## The goal

Build a security operations centre that a jury can watch working: it collects, detects, enriches, reacts on its own, and can prove its coverage against MITRE ATT&CK. Everything runs on a three-node Proxmox cluster at home, next to the services it protects.

Three rules shaped every decision:

1. **No public exposure.** The SIEM, the automation platform and the admin interfaces are only reachable from the LAN or through Tailscale. Nothing listens on the internet.
2. **Fix the root cause, never the symptom.** A problem is closed when the logs explain it, not when it stops showing.
3. **Reproducible and versioned.** Detection rules, response scripts and infrastructure changes live in Git, with tests.

## What it collects

| Layer | Source | Notes |
|---|---|---|
| Perimeter | pfSense firewall logs, Suricata IDS (EVE JSON), CrowdSec, DHCP, DNS | Forwarded by syslog-ng over **TLS** (internal PKI) |
| Network | Zeek on a mirrored port | Connection, DNS, HTTP, TLS and SSH logs, plus home-made scan detection |
| Hosts | Wazuh agents on Linux, Windows (Sysmon) and Android | File integrity, package installs, authentication, CIS benchmark scans |
| Forensics | Velociraptor on about ten endpoints | Its own audit log goes back into Wazuh |

Wazuh (manager + indexer) is the SIEM. Custom decoders and rules turn raw lines into fields that can be searched, correlated and mapped to ATT&CK techniques. A GeoIP layer and a threat-map dashboard sit on top.

## How it reacts

- **Automatic IP blocking.** A critical Suricata alert triggers a Wazuh Active Response that adds the source address to a pfSense table, through a restricted SSH account allowed to run exactly three commands. The ban expires after ten minutes. [Case study →]({{< relref "case-studies/active-response" >}})
- **Enrichment and notification (n8n).** Alerts above a threshold go to an n8n workflow: categorisation, de-duplication, AbuseIPDB reputation for public addresses, correlation (same source on three different rules within 15 minutes), then a Telegram message. A daily digest and a 30-minute heartbeat run in the same workflow.
- **AI-assisted operations.** LLM agents can query Wazuh and the Proxmox cluster through MCP servers I wrote, from a chat room on my phone. Anything that changes the infrastructure waits for my approval. [Case study →]({{< relref "case-studies/ai-agents" >}})

## How I know it works

A SOC that can fail without noticing is worse than no SOC, because it gives false confidence. Two mechanisms answer the question *“how do you know it is still working?”*:

- **A health watchdog** measures, every 30 minutes, the event rate and the share of correctly parsed addresses per source, and raises its own alerts when the pipeline degrades. [Case study →]({{< relref "case-studies/silent-failures" >}})
- **A non-regression suite** replays real log lines against the ruleset before every change is committed. [Case study →]({{< relref "case-studies/detection-as-code" >}})

## Purple-team lab

An isolated network bridge hosts deliberately vulnerable targets (an Active Directory domain controller with Sysmon and Kerberos/DCSync auditing, DVWA, Metasploitable 3) and an attack VM. Atomic Red Team tests run there to measure which techniques are actually detected, and the gaps feed new rules.

## Where it stands

The detection, response and notification loops run in production in the homelab. The current work is measuring ATT&CK coverage on the lab, moving the deployment into Ansible, and an executive dashboard. This website is itself part of the platform: it is built from a self-hosted Forgejo instance that runs on the same cluster and is monitored by the same SIEM.
