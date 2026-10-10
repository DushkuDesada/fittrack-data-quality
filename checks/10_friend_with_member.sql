-- name: A friend visit happens together with the member's check-in
-- severity: warn
-- why: Rule 4 - a friend can only come in with the member. Orphan friend visits inflate friend counts and allowance usage.
-- Edge case: the desk records the friend ~2 minutes after the member's check-in, so a 10-minute window is used.
SELECT f.event_id, f.member_id, f.branch_id, f.event_ts
FROM events f
WHERE lower(f.event_type) = 'friend_visit'
  AND NOT EXISTS (
    SELECT 1
    FROM events c
    WHERE c.member_id = f.member_id
      AND c.branch_id = f.branch_id
      AND lower(c.event_type) = 'check_in'
      AND c.event_ts BETWEEN f.event_ts - interval '10 minutes' AND f.event_ts + interval '10 minutes');
