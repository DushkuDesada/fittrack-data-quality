# FitTrack data quality report

**Data:** the provided `fittrack` dump (156,040 events, 1,122 members, 8 branches, 24 devices).

**Verdict:** **not safe to publish without the handling in the report queries.** 5 blocker
checks fail and 12 warnings fire. Every issue has an identified cause, and the four report
queries in `reports/` handle all of them. Without that handling:

- 2024 member visits are overstated by **~1,900 (2.7%)**;
- 20 March and 20 October show **4–6×** their real traffic;
- the latest month's active members are overstated until cancellations arrive, **17 days later
  on median**.

How to reproduce every number below:

- `python run_checks.py` runs all 20 checks (see README).
- `exploration/profiling.sql` holds the investigation queries.
- `checks/NN_*.sql` holds the automated checks (referenced as `checks/NN`).

## Severity scale

| Severity | Meaning |
|---|---|
| **Blocker** | Changes a published number unless handled; the suite fails the load |
| **High** | Changes a number in a specific report or slice; must be handled in that query |
| **Medium** | Breaks a business rule or a secondary metric; report it, don't block |
| **Low** | Profile or hygiene issue; no effect on the reports in scope |

## Summary by root cause

Fourteen root causes explain every symptom found. Where one cause produces several symptoms,
they are grouped under it.

| # | Root cause | Severity | Symptoms | Effect if not handled |
|---|---|---|---|---|
| 1 | Devices replay buffered events stamped with the **send** time | Blocker | Duplicate `source_ref` with different times; night-time events; daily spikes | visits **+1,451**; daily visits on 20 Mar / 20 Oct **4–6×**; friend visits +137 |
| 2 | Retries not de-duplicated at ingestion | Blocker | Exact duplicate rows | visits **+330** |
| 3 | D04-IN sent upper-case event types for one week | Blocker | `CHECK_IN` instead of `check_in` | visits **−180** at Riverwalk if matched exactly |
| 4 | D07-IN clock 3 h fast for two months | Blocker | Event before ingestion; after-hours visits; broken pairing; 1,175 "visits" over 12 h | 72 visits on the wrong day; visit duration wrong at branch 7 |
| 5 | Test or staff cards in production data | Blocker | Unknown member ids; check-ins at two branches minutes apart | visits **+406** |
| 6 | CRM `members` snapshot drifts from events | High | Status, tier and casing disagree with events | active members Dec **777 vs 756** if read from `members` |
| 7 | **Cancellations reach the database 1.5–32 days late** | High | All 420 cancellations late; 416 land in a later month | latest month's active members overstated at report time |
| 8 | Missing CRM history for 2 members | Medium | Active members with visits and no membership events | not counted as active; no tier, so excluded from allowance |
| 9 | Device D02-OUT lost 27 events | Medium | Gap in the device sequence | unpaired visits at Harbor Point, 13–14 Aug |
| 10 | Friend allowance not enforced at the desk | Medium | 71 member-months over the limit | allowance usage +0.4–1.1 pts per month if not capped |
| 11 | Turnstiles admit members whose membership has ended | Medium | Check-ins while not active | counted by decision (418) |
| 12 | Desk records friends without the member's check-in | Medium | Orphan friend visits | friend visits up to +195 |
| 13 | Pre-sale members stored with a temporary branch id | Low | `home_branch_id = 9`; sign-ups before Pearl District opened | none on these reports |
| 14 | Turnstile misses, wrong `tier_changed.from`, profile errors | Low | See section 14 | none on these reports |

### Effect on each report

| Report | Raw counting would be off by | Main causes |
|---|---|---|
| `visits_per_branch` | **+1,926 visits (+2.7%)**; Riverwalk −180 if case-sensitive | 1, 2, 3, 5 |
| `daily_visits` | 20 Mar: **782 vs 197**; 20 Oct: **1,049 vs 174**; +72 visits shifted a day in Jun–Aug | 1, 2, 4 |
| `active_members_monthly` | Dec **+21** from `members.status`; any month run before cancellations arrive is too high | 6, 7, 8 |
| `friend_allowance_monthly` | **+0.4 to +1.1 pts** per month without the cap; ±0.3 pts using `members` tiers | 6, 8, 10 |

---

## 1. Device replays stamped with the send time (Blocker)

**What:** On **2024-03-20** and **2024-10-20**, devices at every branch re-sent events they
had already delivered. The copies keep the original `source_ref` but carry the time they were
re-sent (00:00–03:00 local), not the time the event happened.

**Evidence**

- `checks/02`: 3,736 `source_ref`s appear more than once. **3,036** of them have different
  timestamps.
- Profiling Q3.3: in every one of those groups, the first copy is a normal daytime event. Every
  later copy falls between 00:00 and 03:00 local on one of the two dates.
- `checks/08`: those days run at 4–4.6× the usual volume per branch (1,635 device events on
  20 March against ~450 on a normal day).
- Replayed copies by type: 1,468 `check_in`, 1,451 `check_out`, 137 `friend_visit`.

```sql
-- When does each copy of a repeated source_ref happen?
WITH d AS (SELECT source_ref FROM events GROUP BY 1 HAVING count(DISTINCT event_ts) > 1)
SELECT row_number() OVER (PARTITION BY e.source_ref ORDER BY e.event_ts) AS copy_no,
       (e.event_ts AT TIME ZONE b.timezone)::date AS local_day, count(*)
FROM events e JOIN branches b USING (branch_id) JOIN d USING (source_ref)
GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 5;
```

**Impact**

- `visits_per_branch`: +1,451 visits (+2.0%).
- `daily_visits`: 20 March would show 782 member visits instead of 197, and 20 October 1,049
  instead of 174.
- Friend visits: +137.
- `active_members_monthly`: none (CRM events have no replays).

**Handling:** every report keeps the **earliest** row per `source_ref`, which carries the real
time.

**Likely cause:** devices buffer events while offline and re-stamp `event_ts` with the current
time when they flush the buffer. Ingestion does not enforce a unique `source_ref`.

## 2. Retries not de-duplicated (Blocker)

**What:** 700 `source_ref`s have identical copies (same timestamp), ingested seconds to
5 minutes apart.

**Evidence:** `checks/02` (rows with `distinct_event_ts = 1`).

**Impact:** +330 visits (+0.5%), spread over all branches.

**Handling:** the same earliest-per-`source_ref` rule.

**Likely cause:** the sender retries when an acknowledgement times out, and there is no unique
constraint on `source_ref`.

## 3. Upper-case event types from D04-IN (Blocker)

**What:** All 181 `CHECK_IN` rows come from **D04-IN** (Riverwalk entrance), between
**2024-04-08 and 2024-04-15**. That week the device sent 181 upper-case and 25 lower-case
check-ins.

**Evidence:** `checks/01`.

```sql
SELECT device_id, min(event_ts)::date, max(event_ts)::date, count(*)
FROM events WHERE event_type = 'CHECK_IN' GROUP BY 1;
```

**Impact:** a report using `event_type = 'check_in'` loses 180 Riverwalk visits (−1.9% for the
branch, nearly all of that week).

**Handling:** compare with `lower(event_type)`.

**Likely cause:** a firmware or configuration change on one turnstile, rolled back a week
later.

## 4. D07-IN clock 3 hours fast (Blocker)

**What:** From **2024-06-06 to 2024-08-06**, the Mission Bay entrance (San Francisco) reported
times 2 h 55 m to 3 h 00 m ahead of the database clock. Three hours is the gap between
Pacific and Eastern time.

**Evidence and symptoms (one cause)**

- `checks/05`: 1,542 events stamped after they were ingested, all from D07-IN, all in that
  period.
- `checks/07`: outside the two replay nights, branch 7 is the only branch with after-hours
  events.
- `checks/09`: branch 7 has 421 check-ins without a check-out, against ~120 at other branches.
  The shifted check-in lands after the member's real check-out.
- **1,175 check-in → check-out pairs longer than 12 hours. All are at branch 7 in this
  period**, so they're the same pairing break, not real long visits.

**Impact**

- `visits_per_branch`: none (still 2024, same branch).
- `daily_visits`: 72 check-ins land on the next day.
- Visit duration and hourly reports: wrong for branch 7 in that period.

**Likely cause:** the device's time zone was set to Eastern time during maintenance in early
June and corrected in early August.

## 5. Test or staff cards (Blocker)

**What:** Member ids **990001** and **990002** have 828 access events and don't exist in
`members` (real ids are 1001–2122).

**Evidence**

- `checks/03`.
- `checks/20`: they account for **all 185** check-ins at two different branches within
  1–7 minutes. That is impossible for one person and typical of cards used for testing
  turnstiles.

**Impact:** +406 visits in `visits_per_branch` if not filtered.

**Handling:** all reports join to `members`.

**Likely cause:** test or staff cards not registered in the CRM.

## 6. CRM snapshot drifts from the event history (High)

**What:** `members.status` and `members.membership_tier` disagree with the latest events:

- 34 `active` members whose last event is a cancellation;
- 6 `cancelled` members who were started or reactivated;
- 5 rows say `Active` with a capital A;
- 8 tier mismatches;
- 2 members with no events (section 8).

**Evidence:** `checks/13` (62 members).

**Impact:** `active_members_monthly` would report **777** active members at the end of December
from `members.status`, against **756** from events (+2.8%).

**Handling:** state and tier always come from `events` (rule 1).

**Likely cause:** the snapshot is refreshed by a job that misses some changes. Root cause 7
(late cancellations) explains part of it.

## 7. Cancellations arrive 1.5–32 days late (High)

**What:** **Every one** of the 420 `membership_cancelled` events reached the database between
1 day 11 h and 32 days after it happened, with a median of **17 days**. 416 of them landed in a
later calendar month. All other CRM events (starts, reactivations, tier changes) arrive within
90 seconds.

**Evidence:** `checks/18`.

```sql
SELECT lower(event_type), count(*),
       percentile_cont(0.5) WITHIN GROUP (ORDER BY ingested_at - event_ts) AS median_delay,
       max(ingested_at - event_ts)
FROM events WHERE source_ref LIKE 'crm:%' GROUP BY 1;
```

**Impact:** on this complete dump, none. In production, `active_members_monthly` run soon after
a month ends overstates that month, because its cancellations haven't arrived yet. The
number goes down over the following weeks, so a published figure later changes.

**Handling:** the query is correct on complete data. Operationally, either publish the monthly
figure only after a settling period (~5 weeks covers the observed maximum), or mark the latest
month as provisional.

**Likely cause:** cancellations go through a separate, batched process in the CRM (approval,
end of the billing period, or a manual step) before they are emitted.

## 8. Missing CRM history for 2 members (Medium)

**What:** Members **1031** and **1132** are `active` in `members` and use the gym (15 and 113
check-ins, 7 and 80 friend visits), but have **no membership events at all**.

**Evidence:** `checks/19`.

**Impact:**

- they are not counted in `active_members_monthly`;
- they have no tier, so `friend_allowance_monthly` leaves them out;
- `checks/16` can't test their allowance. Member 1132 brings 4–8 friends a month, which is
  only allowed for premium.

**Likely cause:** their membership events were never exported, for example members migrated
from an older system.

## 9. D02-OUT lost 27 events (Medium)

**What:** The Harbor Point exit's sequence jumps from **5962 to 5990**. Events 5963–5989 never
arrived. The gap falls between 2024-08-13 02:12 and 2024-08-14 09:47 UTC.

**Evidence:** `checks/17`. No other device has a gap, and CRM numbering 1–1691 is complete.

**Impact:** 27 check-outs missing, so those visits have no end (`checks/09`). Visit counts are
unaffected because they're based on check-ins.

**Likely cause:** a network or device outage where buffered events were lost, not replayed.

## 10. Friend allowance not enforced (Medium)

**What:** In **71 member-months**, members brought more friends than their tier allows:

- basic: 3–5 (limit 2);
- standard: 4–6 (limit 3);
- premium: 9–11 (limit 8).

That's **137 friend visits over the limit**.

**Evidence:** `checks/16`.

**Impact:** `friend_allowance_monthly` caps usage at 100%, as the brief requires. Without the
cap, monthly averages would be 0.4–1.1 points higher.

**Likely cause:** the front-desk tablet does not check the allowance before registering a
friend.

## 11. Lapsed members admitted (Medium)

**What:** 418 check-ins by members whose latest membership event at the time was a
cancellation, or who had no membership.

**Evidence:** `checks/15`.

**Impact:** counted in `visits_per_branch` by decision, because the visit happened. "Visits by
paying members" would be 418 lower. Part of this may be root cause 7: the turnstile didn't
know about the cancellation yet.

**Likely cause:** the access-control system gets membership status from the CRM late, or
doesn't block cancelled cards.

## 12. Friend visits without the member (Medium)

**What:** 195 friend visits have no check-in by the member at the same branch within
10 minutes.

**Evidence:** `checks/10`.

- Median gap between the member's check-in and the friend: **130 seconds**.
- 6,855 of 7,050 friend visits are within 10 minutes. **Widening to 30 minutes adds none**, so
  the 195 are clear orphans, not slow desk entries.

**Impact:** friend counts and allowance usage are overstated by up to 195 visits.

**Likely cause:** the member's own check-in was missed (tailgating), or the desk picked the
wrong member.

## 13. Pre-sale members of Pearl District (Low)

**What:** The 5 members with `home_branch_id = 9` (no such branch) are the same 5 who signed up
at Pearl District (branch 8) in April 2024, before it opened on 2024-05-01.

**Evidence:** `checks/14`.

**Impact:** none on these reports. A report by home branch would show an unknown branch.

**Likely cause:** a temporary branch id used during pre-sales and never remapped.

## 14. Lower-severity issues

| Issue | Evidence | Count | Effect |
|---|---|---|---|
| Unpaired visits outside the D07-IN and D02-OUT problems | `checks/09` | ~70 per month | Visit duration only |
| `tier_changed.from` is not the previous tier | `checks/11` | 3 | Tier history for 3 members |
| `joined_on` mixes conventions: 241 match the UTC date of the first sign-up, 141 the local date | profiling | 382 | Any report by join date is off by a day for some members |
| Duplicate or invalid emails | `checks/14` | 5 duplicated, 4 invalid | Member contact |
| Birth dates before 1920 | `checks/14` | 3 | None |

---

## Checks that passed

- Every device event comes from a known device of the right kind at the event's own branch, and
  its `source_ref` prefix matches the device (`checks/04`).
- The `details` JSON has the documented keys and valid tiers (`checks/12`).
- No future-dated events (`checks/06`).
- No access events before a branch opened or outside 2024 in local time.
- No visits before the member's first sign-up.
- Branch configuration is valid: real IANA time zones, opening before closing.
- No nulls in key event columns.
- No events on 2024-12-25 at any branch. That's consistent with the gyms being closed on
  Christmas Day, but worth confirming.

## Questions for the teams

**Access-control team**

1. Do devices buffer events while offline? When they flush, which timestamp do they send?
   What happened on the nights of 2024-03-20 and 2024-10-20? (Root cause 1.)
2. Was D04-IN updated around 8 and 15 April, and D07-IN serviced around 6 June and 6 August?
   Which time zone is D07-IN set to now? (Root causes 3, 4.)
3. What happened to D02-OUT on 13–14 August? Were buffered events discarded? (Root cause 9.)
4. Who uses cards 990001 and 990002? Can test cards be flagged or kept out of the feed?
5. Does the front desk see a member's remaining friend allowance? Is it supposed to block over
   the limit? (Root cause 10.)
6. Do turnstiles check membership status in real time? (Root cause 11.)
7. Were all branches closed on 25 December?

**CRM team**

1. Why are cancellations emitted 1.5–32 days after their effective date? Is the event time the
   request date or the effective date? (Root cause 7.)
2. How is the `members` snapshot refreshed? (Root cause 6.)
3. Why do members 1031 and 1132 have no membership events? (Root cause 8.)
4. Is branch id 9 a pre-sale placeholder that should now be 8? (Root cause 13.)
5. Is `joined_on` meant to be the local date or the UTC date?

**Data platform**

1. Can ingestion reject or merge duplicate `source_ref`s, and keep the earliest copy?
2. Can we add constraints: foreign keys from `events` to `members`, `branches` and `devices`,
   and allowed values for `event_type`, tier and status?

## What to monitor from now on

| Metric | Alert when | Catches | Check |
|---|---|---|---|
| Duplicate `source_ref` per load | > 0 | Retries, replays | 02 |
| `event_ts − ingested_at` per device | event > 1 min ahead | Clock and time zone errors | 05 |
| Device sequence continuity | any gap | Lost events | 17 |
| CRM delay per event type | > 1 day, or median growing | Late cancellations | 18 |
| Device events per branch per day vs the 7 days around it | > 2× (or < 0.5×) | Replays, outages | 08 |
| Share of access events outside opening hours | > 0.5% per device | Clock errors | 07 |
| Distinct `event_type` values | not in the documented list | Format changes | 01 |
| Events for unknown members; impossible travel | > 0 | Test or shared cards | 03, 20 |
| `members` vs the latest event; members without history | any | Snapshot drift, missing exports | 13, 19 |
| Friend visits over allowance | trend up | Desk not enforcing | 16 |
| Check-ins by members who aren't active | trend up | Access-control sync | 15 |

For daily runs on new loads, these checks would get a filter on `ingested_at` for the latest
load, and the active-members figure for the most recent month would be marked provisional
until cancellations settle.
