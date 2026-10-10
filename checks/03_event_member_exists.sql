-- name: Every event belongs to a known member
-- severity: blocker
-- why: Events for ids missing from members (test or staff cards) end up in visit counts.
SELECT e.member_id, count(*) AS events
FROM events e
LEFT JOIN members m ON m.member_id = e.member_id
WHERE m.member_id IS NULL
GROUP BY e.member_id;
