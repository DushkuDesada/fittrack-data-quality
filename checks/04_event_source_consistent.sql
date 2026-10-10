-- name: Each event comes from the right sender (CRM vs the right device at the right branch)
-- severity: blocker
-- why: Reports attribute visits to branches through device and branch; a mismatch moves visits between branches.
SELECT e.event_id, e.source_ref, e.event_type, e.branch_id, e.device_id,
       d.branch_id AS device_branch, d.kind AS device_kind,
       CASE
         WHEN e.branch_id IS NULL OR b.branch_id IS NULL                     THEN 'unknown branch'
         WHEN e.source_ref LIKE 'crm:%' AND e.device_id IS NOT NULL         THEN 'CRM event with a device'
         WHEN e.source_ref NOT LIKE 'crm:%' AND e.device_id IS NULL         THEN 'device event without device'
         WHEN e.device_id IS NOT NULL AND d.device_id IS NULL               THEN 'unknown device'
         WHEN d.branch_id <> e.branch_id                                    THEN 'device belongs to another branch'
         WHEN split_part(e.source_ref, ':', 1) <> e.device_id               THEN 'source_ref prefix is not the device'
         WHEN lower(e.event_type) = 'check_in'     AND d.kind <> 'entrance'   THEN 'check_in not from an entrance'
         WHEN lower(e.event_type) = 'check_out'    AND d.kind <> 'exit'       THEN 'check_out not from an exit'
         WHEN lower(e.event_type) = 'friend_visit' AND d.kind <> 'front_desk' THEN 'friend_visit not from the desk'
         WHEN e.device_id IS NULL AND lower(e.event_type) IN ('check_in', 'check_out', 'friend_visit')
                                                                            THEN 'access event from the CRM'
         WHEN e.device_id IS NOT NULL AND (lower(e.event_type) LIKE 'membership%' OR lower(e.event_type) = 'tier_changed') THEN 'CRM event type from a device'
       END AS problem
FROM events e
LEFT JOIN branches b ON b.branch_id = e.branch_id
LEFT JOIN devices  d ON d.device_id = e.device_id
WHERE e.branch_id IS NULL OR b.branch_id IS NULL
   OR (e.source_ref LIKE 'crm:%') <> (e.device_id IS NULL)
   OR (e.device_id IS NOT NULL AND (
          d.device_id IS NULL
       OR d.branch_id <> e.branch_id
       OR split_part(e.source_ref, ':', 1) <> e.device_id
       OR (lower(e.event_type) = 'check_in'     AND d.kind <> 'entrance')
       OR (lower(e.event_type) = 'check_out'    AND d.kind <> 'exit')
       OR (lower(e.event_type) = 'friend_visit' AND d.kind <> 'front_desk')
       OR lower(e.event_type) LIKE 'membership%'
       OR lower(e.event_type) = 'tier_changed'))
   OR (e.device_id IS NULL AND lower(e.event_type) IN ('check_in', 'check_out', 'friend_visit'));
