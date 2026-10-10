-- name: Every member has a membership history in the events
-- severity: warn
-- why: Rule 1 - membership state and tier come from events. A member with access events but no membership events cannot be counted as active and has no tier for the friend allowance.
SELECT m.member_id, m.status, m.membership_tier,
       count(e.event_id) FILTER (WHERE lower(e.event_type) = 'check_in')     AS check_ins,
       count(e.event_id) FILTER (WHERE lower(e.event_type) = 'friend_visit') AS friend_visits
FROM members m
LEFT JOIN events e ON e.member_id = m.member_id
GROUP BY m.member_id, m.status, m.membership_tier
HAVING count(e.event_id) FILTER (WHERE lower(e.event_type) = 'membership_started') = 0;
