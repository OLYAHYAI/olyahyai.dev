---
title: "Automatic IP blocking without giving the SIEM the keys to the firewall"
slug: "automatic-ip-blocking"
date: 2026-09-13
weight: 4
summary: "A critical IDS alert bans the attacker at the firewall within seconds, for ten minutes. The interesting part is what the SIEM is not allowed to do, and two bugs that only a real end-to-end test revealed."
tags: ["Active Response", "pfSense", "Suricata", "Least privilege"]
stack: ["Wazuh", "pfSense", "Suricata", "SSH", "Bash", "Telegram"]
---

## The goal

When Suricata raises a critical alert, the source address should be blocked at the firewall without waiting for me, then released automatically. The SIEM must be able to do exactly that, and nothing else.

## Design: a table, an account, three commands

pfSense has no official REST API, and I did not want to install an unofficial package with admin rights on the firewall. The design relies only on built-in features:

- a **pf table alias** used by a block rule placed above all other rules, including the pfBlockerNG ones. Banning an address means adding it to the table: no rule change, no reload. The alias holds a placeholder from the documentation range (TEST-NET), so it is never empty and the rule never disappears;
- a **dedicated, unprivileged account** on the firewall, reachable only with its own SSH key, whose sudo rights cover **exactly three** `pfctl` commands: add to the table, delete from the table, list the table;
- a **Wazuh Active Response** script on the manager that reads the alert, calls SSH and logs every action.

| Setting | Value | Why |
|---|---|---|
| Trigger | rule group `suricata`, level ≥ 10 | only critical IDS alerts |
| Duration | 600 s, then automatic removal | a mistake costs ten minutes, not a lockout |
| Notification | Telegram, on ban only | no noise on removal |

If the SIEM is compromised, the only root-level action it can take on the firewall is adding or removing addresses in that one table. It cannot change rules, install packages or run anything else as root.

## Two bugs found before going live

1. **The SSH key was refused.** Permissions, sshd and PAM were all correct. The cause: the public key pasted into the firewall's web UI differed from the private key by two characters (`Z` read as `2`, `1` read as `l`). `cmp -l` between the installed key and the one derived with `ssh-keygen -y` showed the exact bytes, which were then patched one by one rather than retyped.
2. **The escalation rule could never match.** The rule that raises critical Suricata alerts to level 10 already existed, but it had been placed *inside* the pfSense rule block. It inherited the wrong groups and never carried `suricata`, so the response would never have fired, whatever the traffic.

## Testing it for real

Forging an alert only tests half the chain. A temporary Suricata rule matched a harmless magic string, and a `curl` run from the firewall itself carried it out through the monitored interface: real traffic, real IDS alert, real decoding, real response.

Result: alert → ban → Telegram message, then removal ten minutes later, visible in the firewall table.

## Lessons

- The first live trigger came late: the manager had been validated and reloaded after the configuration changes, but not fully restarted. Before any live test, I now do a **full restart**.
- Before removing an entry from the block table by hand, check the response log: the documentation placeholder looks just like a banned address in a quick listing.
- The Telegram message is built with `jq`, not string concatenation: an alert field containing quotes must not break, or inject into, the JSON.

## What I took from it

An automated response is safe when its worst case is small and known in advance. Here, the worst case fits in one sentence and lasts ten minutes.
