---
title: "When the SIEM goes blind without a single error"
slug: "silent-failures"
date: 2026-09-14
weight: 2
summary: "Three silent failures in two days, none raised by the SIEM itself. Tracing them to one root cause, then building a watchdog that would have caught all three."
tags: ["Wazuh", "Decoders", "Monitoring", "Root cause"]
stack: ["Wazuh", "syslog-ng", "pfSense", "Python", "cron"]
---

## The problem nobody alerts on

In two days, three parts of the pipeline stopped working. Each time the SIEM kept running, without an error, still producing alerts — only fewer, or wrong ones.

| Failure | How it was found | Time blind |
|---|---|---|
| Suricata traffic dropped after moving the syslog stream to TLS (the tunnel allowed the wrong source address) | by me, during a manual review | a few hours |
| pfSense alerts carried port numbers and TTL values in their source/destination IP fields | by chance, while building GeoIP enrichment | three days or more |
| DHCP events were received but never decoded | by the watchdog described below, while it was being built | three days or more |

This is the worst failure mode for a SOC. A dashboard with fewer alerts looks like a quiet day. And it makes any coverage measurement meaningless: a missed detection cannot be told apart from a broken collector.

## One root cause behind two of them

The firewall logs arrive through syslog-ng, which wraps each message in its own envelope (octet count, structured-data metadata, a nested syslog header). The original decoders were anchored at the **start of the line**:

```
<prematch>^dhcpd \d+ - - </prematch>
```

With the new envelope, `dhcpd` sat around character 170. The decoder never matched, and the events fell through as undecoded lines: present in the archives (177 a day), absent from the alerts. The broken source/destination IPs had the same cause: a regular expression anchored on the envelope captured the wrong groups once the envelope changed, so TTL and IP-ID values landed in the address fields.

The fix was to anchor on what is specific to pfSense, not on the transport:

```
<prematch type="pcre2">\sdhcpd\s+\d+\s+-\s+-\s+</prematch>
```

Checked offline against the archived lines before deploying: **177/177** matched (0/177 before). The hourly share of valid source IPs tells the rest of the story:

```
03h..12h  valid srcip = 0.0 %     <- dead decoder, no alert anywhere
13h       valid srcip = 92.4 %    <- fix deployed during that hour
14h       valid srcip = 100.0 %
```

## The watchdog

The fix closed these bugs. The real question was how to know about the next one. A small probe now runs every 30 minutes:

- it reads the alert log **incrementally** (stored offset, rotation detected by inode, only complete lines), so it never rescans a 400 MB file;
- for each source it computes the event rate, the share of parsable IP addresses and the age of the last event;
- it writes **one JSON line** with a verdict: `ok`, `degraded`, `critical`, or `bootstrap` (first run or rotation, which never alerts).

All the decision logic lives in the script, which can be tested offline. The Wazuh rules only match the verdict text, so there are no numeric comparisons hidden in XML.

Thresholds come from measured baselines and sit about three times below the quietest night-time hour:

| Check | degraded | critical |
|---|---|---|
| pfSense rate | < 50/min | < 10/min |
| Suricata rate | < 15/min | < 3/min |
| Parsable IPs (each source) | < 98 % | < 50 % |
| Last DHCP event | > 24 h | — |

Three rules turn the verdict into alerts: level 3 for `ok` (deliberately, to keep a health time series for the dashboard), 7 for `degraded`, 12 for `critical`, with the reason in the description. The rule group is `soc_health`, never `suricata`: a level-12 health alert must not be able to trigger the automatic IP ban.

## Proof

Eight offline scenarios, including the three failures I had actually lived through, all return the expected verdict (**8/8**). In production, the first run reported `ok` with 100 % parsable addresses, and forged `degraded`/`critical` lines produced the level-7 and level-12 alerts.

## Limits, stated plainly

- The probe speaks through Wazuh. If the manager stops completely, it goes silent too. A separate heartbeat in n8n now raises an alert when no alert at all has arrived for three hours.
- Rate thresholds catch collapses, not a slow 20–30 % decline. Comparing with the same hour on previous days would.

## What I took from it

“No error” is not “working”. A SIEM needs to measure its own inputs, with thresholds taken from data, and the check has to be testable away from production.
