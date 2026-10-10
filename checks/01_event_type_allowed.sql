-- name: Event types are one of the 7 documented values (exact spelling)
-- severity: blocker
-- why: Reports filter on exact event_type; 'CHECK_IN' is silently missed by event_type = 'check_in'.
SELECT event_type, count(*) AS rows
FROM events
WHERE event_type NOT IN ('membership_started', 'membership_reactivated', 'membership_cancelled',
                         'tier_changed', 'check_in', 'check_out', 'friend_visit')
GROUP BY event_type;
