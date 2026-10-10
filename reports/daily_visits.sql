-- =============================================================================
-- reports/daily_visits.sql
-- One row per day of 2024 (all branches combined) with member and friend visits.
-- Columns: date (YYYY-MM-DD), member_visits, friend_visits
--
-- Runs on its own (no views, temp tables or functions), read-only, Postgres 17.
--
-- DECISIONS (same counting rules as reports/visits_per_branch.sql, so the
-- daily member_visits add up to the same yearly total)
--
-- 1. A member visit = one check-in at an entrance of that branch; a check-out is
--    not required. A friend visit = one friend_visit from that branch's front desk.
--
-- 2. event_type is compared case-insensitively (181 rows arrive as 'CHECK_IN').
--
-- 3. Each device event is counted once per source_ref, keeping the EARLIEST
--    copy. This removes exact retries and the replays of 2024-03-20 and
--    2024-10-20, which were re-sent at night with the send time. Without it,
--    those two days would show 3-4x their real traffic.
--
-- 4. Only people in members are counted (test/staff cards 990001, 990002 are
--    excluded). Membership status at the time of the visit is not checked.
--
-- 5. "Day" is the calendar day in the time zone of the branch where the visit
--    happened (rule 5), then summed over all branches. A visit at 22:00 on
--    31 December in Los Angeles is a 2024-12-31 visit.
--
-- 6. Known limitation: D07-IN's clock ran 3 hours fast from 6 June to 6 August;
--    72 Mission Bay check-ins land on the next day. They are not corrected here
--    (see DATA_QUALITY.md, root cause 4).
--
-- 7. Days with no visits at all are left out (allowed by the brief); a day with
--    friend visits but no member visits would still appear.
-- =============================================================================

WITH device_events AS (
    SELECT DISTINCT ON (e.source_ref)                          -- decision 3
           e.member_id, e.event_type, e.event_ts, e.branch_id, e.device_id
    FROM events e
    WHERE e.device_id IS NOT NULL
    ORDER BY e.source_ref, e.event_ts, e.event_id
),

visits AS (
    SELECT (ev.event_ts AT TIME ZONE b.timezone)::date AS local_date,   -- decision 5
           lower(ev.event_type)                       AS event_type
    FROM device_events ev
    JOIN devices  d ON d.device_id = ev.device_id
                   AND d.branch_id = ev.branch_id
    JOIN branches b ON b.branch_id = d.branch_id
    JOIN members  m ON m.member_id = ev.member_id           -- decision 4
    WHERE (lower(ev.event_type) = 'check_in'     AND d.kind = 'entrance')     -- decisions 1, 2
       OR (lower(ev.event_type) = 'friend_visit' AND d.kind = 'front_desk')
)

SELECT to_char(local_date, 'YYYY-MM-DD')                          AS date,
       count(*) FILTER (WHERE event_type = 'check_in')::integer     AS member_visits,
       count(*) FILTER (WHERE event_type = 'friend_visit')::integer AS friend_visits
FROM visits
WHERE local_date >= DATE '2024-01-01'
  AND local_date <  DATE '2025-01-01'
GROUP BY local_date
ORDER BY local_date;
