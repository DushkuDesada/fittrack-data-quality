-- =============================================================================
-- reports/active_members_monthly.sql
-- One row per month of 2024 with the number of active members at month end.
-- Columns: month (YYYY-MM), active_members
--
-- Runs on its own (no views, temp tables or functions), read-only, Postgres 17.
--
-- DECISIONS
--
-- 1. Membership state comes from events, never from members.status (rule 1).
--    members.status disagrees with the event history for ~40 members.
--
-- 2. Active in a month = the member's latest membership event up to the END of
--    that month is membership_started or membership_reactivated (rule 2).
--    "Membership event" means started / reactivated / cancelled. tier_changed is
--    ignored: it changes the tier, not whether the member is active, and counting
--    it as "the latest event" would wrongly drop members who changed tier.
--
-- 3. "End of the month" is in the time zone of the branch where the event
--    happened (rule 5). A cancellation at 22:00 on 31 March in Los Angeles is
--    still a March event, even though it is already 1 April in UTC.
--
-- 4. event_type is compared case-insensitively, and each source_ref is counted
--    once (earliest copy), the same de-duplication as the visits report.
--
-- 5. Only members present in the members table are counted. If two events
--    have the same timestamp, the later event_id wins.
--
-- 6. All 12 months are returned, even a month with 0 active members.
-- =============================================================================

WITH months AS (
    SELECT gs::date AS month_start
    FROM generate_series(DATE '2024-01-01', DATE '2024-12-01', INTERVAL '1 month') AS gs
),

membership_events AS (
    -- Decisions 2, 4: lifecycle events only, one row per source_ref.
    SELECT DISTINCT ON (e.source_ref)
           e.member_id,
           e.event_id,
           e.event_ts,
           lower(e.event_type)                                   AS event_type,
           e.event_ts AT TIME ZONE coalesce(b.timezone, 'UTC')   AS local_ts   -- decision 3
    FROM events e
    JOIN members m       ON m.member_id = e.member_id                          -- decision 5
    LEFT JOIN branches b ON b.branch_id = e.branch_id
    WHERE lower(e.event_type) IN ('membership_started',
                                  'membership_reactivated',
                                  'membership_cancelled')
    ORDER BY e.source_ref, e.event_ts, e.event_id
),

state_at_month_end AS (
    -- For each month and member: the latest lifecycle event before the next month starts.
    SELECT DISTINCT ON (mo.month_start, me.member_id)
           mo.month_start,
           me.member_id,
           me.event_type
    FROM months mo
    JOIN membership_events me
      ON me.local_ts < (mo.month_start + INTERVAL '1 month')
    ORDER BY mo.month_start, me.member_id, me.event_ts DESC, me.event_id DESC
)

SELECT to_char(mo.month_start, 'YYYY-MM') AS month,
       count(s.member_id)::integer       AS active_members                     -- decision 6
FROM months mo
LEFT JOIN state_at_month_end s
       ON s.month_start = mo.month_start
      AND s.event_type IN ('membership_started', 'membership_reactivated')
GROUP BY mo.month_start
ORDER BY mo.month_start;
