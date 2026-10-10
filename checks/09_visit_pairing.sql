-- name: Every check-in is followed by a check-out at the same branch
-- severity: warn
-- max_rows: 1500
-- why: Rule 3 - a visit runs from check_in to check_out. Missing or mismatched halves distort visit length and pairing-based reports.
-- Edge cases: duplicates collapsed per source_ref first; event_type compared case-insensitively;
-- a small number of missing check-outs is normal (people leave behind someone), hence max_rows.
WITH ev AS (
  SELECT DISTINCT ON (source_ref) member_id, branch_id, event_ts, event_id, lower(event_type) AS et
  FROM events
  WHERE lower(event_type) IN ('check_in', 'check_out')
  ORDER BY source_ref, event_ts, event_id
), seq AS (
  SELECT ev.*,
         lead(et)        OVER w AS next_et,
         lead(branch_id) OVER w AS next_branch,
         lag(et)         OVER w AS prev_et
  FROM ev
  WINDOW w AS (PARTITION BY member_id ORDER BY event_ts, event_id)
)
SELECT member_id, branch_id, event_ts, et,
       CASE
         WHEN et = 'check_in'  AND next_et = 'check_in'       THEN 'check_in without check_out'
         WHEN et = 'check_in'  AND next_branch <> branch_id   THEN 'check_out at another branch'
         WHEN et = 'check_out' AND (prev_et IS NULL OR prev_et = 'check_out') THEN 'check_out without check_in'
       END AS problem
FROM seq
WHERE (et = 'check_in'  AND (next_et = 'check_in' OR (next_et = 'check_out' AND next_branch <> branch_id)))
   OR (et = 'check_out' AND (prev_et IS NULL OR prev_et = 'check_out'));
