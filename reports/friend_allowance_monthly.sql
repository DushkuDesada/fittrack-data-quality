-- =============================================================================
-- reports/friend_allowance_monthly.sql
-- One row per month of 2024 with the average share of their friend allowance
-- that members used.
-- Columns: month (YYYY-MM), avg_utilization_pct
--
-- Runs on its own (no views, temp tables or functions), read-only, Postgres 17.
--
-- DEFINITION (from the brief)
--   For every member who visited at least once in the month: friend visits
--   brought that month, capped at their allowance, divided by the allowance.
--   Average across those members, as a percentage with one decimal.
--   Allowance per month: basic 2, standard 3, premium 8.
--
-- DECISIONS
--
-- 1. "Visited" uses the same rule as visits_per_branch.sql: at least one
--    check-in at an entrance (case-insensitive, earliest copy per source_ref,
--    only members present in members). Members who brought friends but did not
--    check in that month are not in the base.
--
-- 2. Friend visits: friend_visit events from a front desk, earliest copy per
--    source_ref. All recorded friend visits count toward usage, including the
--    195 with no matching member check-in (the desk recorded them against the
--    member). Usage is capped at the allowance, as the brief says, so the 71
--    member-months over the limit count as 100%.
--
-- 3. Month = calendar month in the time zone of the branch where the event
--    happened (rule 5), for visits, friend visits and tier events alike.
--
-- 4. Tier in a month = the member's tier at the END of that month, from the
--    latest membership_started / membership_reactivated / tier_changed event
--    up to then (tier comes from events, rule 1, not from members). A member
--    who changes tier mid-month gets the allowance of the tier they finish on.
--
-- 5. Members with no tier at all in the events (members 1031 and 1132 have no
--    membership history) have no allowance and are left out of the average.
--    They are reported by checks/19.
--
-- 6. All 12 months are returned. A month with no visiting members would show
--    NULL rather than a misleading 0.
-- =============================================================================

WITH months AS (
    SELECT gs::date AS month_start
    FROM generate_series(DATE '2024-01-01', DATE '2024-12-01', INTERVAL '1 month') AS gs
),

events_local AS (
    -- One row per source_ref (earliest copy), with local time of its branch.
    SELECT DISTINCT ON (e.source_ref)
           e.event_id, e.member_id, e.event_ts, e.branch_id, e.device_id, e.details,
           lower(e.event_type)                                          AS event_type,
           e.event_ts AT TIME ZONE coalesce(b.timezone, 'UTC')          AS local_ts
    FROM events e
    JOIN members m       ON m.member_id = e.member_id
    LEFT JOIN branches b ON b.branch_id = e.branch_id
    ORDER BY e.source_ref, e.event_ts, e.event_id
),

access AS (
    -- Check-ins from an entrance and friend visits from a front desk (decisions 1, 2).
    SELECT el.member_id, el.event_type,
           date_trunc('month', el.local_ts)::date AS month_start
    FROM events_local el
    JOIN devices d ON d.device_id = el.device_id
                  AND d.branch_id = el.branch_id
    WHERE (el.event_type = 'check_in'     AND d.kind = 'entrance')
       OR (el.event_type = 'friend_visit' AND d.kind = 'front_desk')
),

member_months AS MATERIALIZED (
    -- Members who visited in the month, with the friend visits they brought.
    SELECT member_id, month_start,
           count(*) FILTER (WHERE event_type = 'friend_visit') AS friend_visits
    FROM access
    GROUP BY member_id, month_start
    HAVING count(*) FILTER (WHERE event_type = 'check_in') > 0
),

tier_events AS MATERIALIZED (
    SELECT member_id, event_id, event_ts, local_ts,
           coalesce(details->>'to', details->>'tier') AS tier
    FROM events_local
    WHERE event_type IN ('membership_started', 'membership_reactivated', 'tier_changed')
),

with_tier AS (
    -- Decision 4: tier at the end of the month = latest tier event before the next month starts.
    SELECT DISTINCT ON (mm.member_id, mm.month_start)
           mm.member_id, mm.month_start, mm.friend_visits, t.tier
    FROM member_months mm
    LEFT JOIN tier_events t
           ON t.member_id = mm.member_id
          AND t.local_ts < mm.month_start + INTERVAL '1 month'
    ORDER BY mm.member_id, mm.month_start, t.event_ts DESC NULLS LAST, t.event_id DESC NULLS LAST
),

utilization AS (
    SELECT month_start,
           least(friend_visits, allowance)::numeric / allowance AS used_share
    FROM (
        SELECT month_start, friend_visits,
               CASE tier WHEN 'basic' THEN 2 WHEN 'standard' THEN 3 WHEN 'premium' THEN 8 END AS allowance
        FROM with_tier
    ) a
    WHERE allowance IS NOT NULL                                          -- decision 5
)

SELECT to_char(mo.month_start, 'YYYY-MM')       AS month,
       round(100 * avg(u.used_share), 1)       AS avg_utilization_pct
FROM months mo
LEFT JOIN utilization u ON u.month_start = mo.month_start
GROUP BY mo.month_start
ORDER BY mo.month_start;
