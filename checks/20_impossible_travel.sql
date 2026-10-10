-- name: No member checks in at two different branches within 30 minutes
-- severity: warn
-- why: A card used at two branches minutes apart is shared, cloned or a test card; those visits are not one member's real visits.
-- Edge case: duplicates collapsed per source_ref first, so a replayed check-in is not counted as travel.
WITH ev AS (
  SELECT DISTINCT ON (source_ref) member_id, branch_id, event_ts, event_id
  FROM events
  WHERE lower(event_type) = 'check_in'
  ORDER BY source_ref, event_ts, event_id
), seq AS (
  SELECT member_id, branch_id, event_ts,
         lead(branch_id) OVER w AS next_branch,
         lead(event_ts)  OVER w AS next_event_ts
  FROM ev
  WINDOW w AS (PARTITION BY member_id ORDER BY event_ts, event_id)
)
SELECT member_id, branch_id, event_ts, next_branch, next_event_ts,
       next_event_ts - event_ts AS gap
FROM seq
WHERE next_branch <> branch_id
  AND next_event_ts - event_ts < interval '30 minutes';
