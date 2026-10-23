---
title: "Detection as code: versioning a live SIEM ruleset"
slug: "detection-as-code"
date: 2026-09-14
weight: 3
summary: "Putting the Wazuh ruleset under Git without a sync step that can drift, and a non-regression suite built from real log lines — proven by a negative control that brings an old bug back."
tags: ["Wazuh", "Git", "Testing", "Change management"]
stack: ["Wazuh", "Git", "Bash", "Python"]
---

## Why

Custom decoders and rules are code. Until then they were edited in place on the manager: no history, no review, and no way to tell whether a change broke something that used to work. The previous case study shows what that costs: [a decoder died silently for three days]({{< relref "case-studies/silent-failures" >}}).

## Git where the files live

The usual setup is a separate repository plus a script that copies files into the SIEM's configuration directory. I rejected it: a sync step is one more thing that can silently fall out of step with what is actually running.

Instead, the repository **is** the configuration directory. Files that must live elsewhere (the active-response script, the watchdog) are symlinked into it, so one `git log` covers everything that shapes detection.

Since that directory also holds keys and agent secrets, the `.gitignore` works the other way round: **deny everything**, then explicitly allow the rule, decoder and list files. A secrets audit of the first commit confirmed nothing sensitive was tracked.

## A test suite built from real traffic

Each test is a real log line plus the fields the decoder must extract (decoder name, source and destination IP, ports, action, rule ID, level).

Two details made the difference:

- **The corpus comes from the archived JSON (`full_log`), not the plain-text archive.** The text archive adds its own prefix, so a test built from it checks a line the decoder never actually sees.
- **The expected values come from an independent parser,** not from the decoder's own output. Otherwise the test only proves the decoder agrees with itself.

The Wazuh log-test tool also had two traps: it writes its results to stderr, and it does not reload the ruleset. After a change the manager must be restarted, then given 60 to 90 seconds before testing, or the suite tests the old rules.

## The negative control

A test suite that has never failed proves nothing. So I deliberately restored the old, broken decoder and ran the suite:

```
old decoder   2/11 PASS   srcip = "64"   (the TTL)
                          dstip = "53770"  (the IP-ID)
fixed decoder 11/11 PASS
```

The suite caught exactly the bug that had gone unnoticed for three days, with the same wrong values. It has since grown to **20/20**, alongside the eight offline scenarios of the watchdog.

## The change procedure

Every ruleset change follows the same five steps, written down so that I follow them on a tired evening too:

1. create a branch;
2. check syntax with `wazuh-analysisd -t`;
3. restart the manager and wait;
4. run the suite: all green, or roll back;
5. commit with a message that says *why*.

## What I took from it

Versioning is only half the job. A test only proves something once you have seen it fail for the right reason.
