-- =============================================================================
-- reports/visits_per_branch.sql
-- One row per branch with the number of member visits in 2024.
-- Columns: branch_id, branch_name, member_visits
--
-- Runs on its own (no views, temp tables or functions), read-only, Postgres 17.
--
-- DECISIONS (what counts as a visit, and why)
--
-- 1. A visit = one check-in at the branch's entrance turnstile.
--    Business rule 3 says a visit starts with a check_in. I count the start,
--    and do NOT require a matching check_out: about 70 check-outs a month are
--    missing in normal months (people leave through the door behind someone),
--    and the member still visited.
--
-- 2. event_type is compared case-insensitively.
--    181 rows arrive as 'CHECK_IN'. They are real check-ins from entrance
--    turnstiles and have no duplicate, so they count.
--
-- 3. Each device event is counted once per source_ref, keeping the EARLIEST.
--    source_ref = <device_id>:<sequence> and should be unique, but repeats:
--      a) exact retries: same event_ts, re-sent within minutes;
--      b) replays: on 2024-03-20 and 2024-10-20 every repeated event was
--         re-sent between 00:00 and 03:00 local time, stamped with the time
--         it was sent. The earliest copy carries the real time.
--    Keeping the earliest row handles both and puts the visit on the right day.
--
-- 4. The event must come from an entrance device that belongs to the branch.
--    Joining devices on both device_id and branch_id drops check-ins with an
--    unknown device or a device from another branch (0 today, but the second
--    database may have them).
--
-- 5. Only people who exist in members are counted ("members' visits").
--    Member ids 990001 and 990002 are not in members (likely test or staff
--    cards) and are excluded.
--
-- 6. Membership status at the time of the visit is NOT checked.
--    About 400 check-ins belong to members whose membership had ended. The
--    turnstile let them in, so the visit happened; whether it should have is
--    an access-control question, reported in DATA_QUALITY.md.
--
-- 7. "2024" means the calendar year in the branch's own time zone (rule 5).
--    Filtering on event_ts in UTC would move New Year's Eve visits on the
--    West Coast into 2025.
--
-- 8. The D07-IN clock ran 3 hours fast from 6 June to 6 August 2024. Those
--    visits are still in 2024, so the count is not affected and I do not try
--    to correct the timestamps here.
--
-- 9. Every branch appears, including one with 0 visits (LEFT JOIN).
-- =============================================================================

WITH device_events AS (
    -- Decision 3: one row per source_ref, the earliest copy.
    SELECT DISTINCT ON (e.source_ref)
           e.source_ref,
           e.member_id,
           e.event_type,
           e.event_ts,
           e.branch_id,
           e.device_id
    FROM events e
    WHERE e.device_id IS NOT NULL
    ORDER BY e.source_ref, e.event_ts, e.event_id
),

member_visits AS (
    SELECT d.branch_id
    FROM device_events ev
    JOIN devices  d ON d.device_id = ev.device_id      -- decision 4
                   AND d.branch_id = ev.branch_id
                   AND d.kind      = 'entrance'
    JOIN branches b ON b.branch_id = d.branch_id
    JOIN members  m ON m.member_id = ev.member_id      -- decision 5
    WHERE lower(ev.event_type) = 'check_in'            -- decisions 1, 2
      AND (ev.event_ts AT TIME ZONE b.timezone) >= TIMESTAMP '2024-01-01'  -- decision 7
      AND (ev.event_ts AT TIME ZONE b.timezone) <  TIMESTAMP '2025-01-01'
)

SELECT b.branch_id,
       b.name                      AS branch_name,
       count(v.branch_id)::integer AS member_visits     -- decision 9: 0 when none
FROM branches b
LEFT JOIN member_visits v ON v.branch_id = b.branch_id
GROUP BY b.branch_id, b.name
ORDER BY b.branch_id;
