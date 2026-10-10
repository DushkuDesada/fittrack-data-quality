-- name: details JSON has the documented keys and valid values for each event type
-- severity: blocker
-- why: Tier and allowance reports read the tier from details; a missing or unknown tier breaks them.
SELECT event_id, event_type, details
FROM events
WHERE CASE lower(event_type)
        WHEN 'membership_started'     THEN NOT coalesce(details->>'tier' IN ('basic','standard','premium'), false)
        WHEN 'membership_reactivated' THEN NOT coalesce(details->>'tier' IN ('basic','standard','premium'), false)
        WHEN 'tier_changed'           THEN NOT coalesce(details->>'from' IN ('basic','standard','premium')
                                                    AND details->>'to' IN ('basic','standard','premium'), false)
        WHEN 'membership_cancelled'   THEN coalesce(details->>'reason', '') = ''
        WHEN 'friend_visit'           THEN coalesce(trim(details->>'friend_name'), '') = ''
        ELSE false
      END;
