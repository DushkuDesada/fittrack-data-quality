-- name: Access events happen while the branch is open (local time)
-- severity: warn
-- why: Visits at 2 am point to clock errors or replayed events stamped with the wrong time.
-- Edge cases: uses each branch's own time zone (rule 5); duplicates of the same source_ref are
-- collapsed to the earliest copy so a replay is reported once, by check 02, not twice.
WITH ev AS (
  SELECT DISTINCT ON (source_ref) *
  FROM events
  WHERE device_id IS NOT NULL
  ORDER BY source_ref, event_ts, event_id
)
SELECT b.branch_id,
       (ev.event_ts AT TIME ZONE b.timezone)::date AS local_day,
       count(*)                                    AS events,
       min((ev.event_ts AT TIME ZONE b.timezone)::time) AS earliest,
       max((ev.event_ts AT TIME ZONE b.timezone)::time) AS latest
FROM ev
JOIN branches b ON b.branch_id = ev.branch_id
WHERE (ev.event_ts AT TIME ZONE b.timezone)::time <  b.opens_at
   OR (ev.event_ts AT TIME ZONE b.timezone)::time >= b.closes_at
GROUP BY 1, 2;
