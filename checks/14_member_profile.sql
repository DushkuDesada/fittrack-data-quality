-- name: Member profiles are complete and plausible
-- severity: warn
-- why: Bad profile data (unknown home branch, duplicate or invalid email, impossible birth date) breaks member-level reporting and contact.
SELECT member_id, problem
FROM (
  SELECT m.member_id, 'home branch does not exist' AS problem
  FROM members m LEFT JOIN branches b ON b.branch_id = m.home_branch_id
  WHERE b.branch_id IS NULL
  UNION ALL
  SELECT member_id, 'email missing or invalid' FROM members
  WHERE email IS NULL OR email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
  UNION ALL
  SELECT member_id, 'email shared with another member' FROM members
  WHERE lower(email) IN (SELECT lower(email) FROM members GROUP BY 1 HAVING count(*) > 1)
  UNION ALL
  SELECT member_id, 'birth date implausible' FROM members
  WHERE date_of_birth IS NULL OR date_of_birth < DATE '1920-01-01'
     OR date_of_birth > joined_on - interval '14 years'
  UNION ALL
  SELECT member_id, 'name missing' FROM members
  WHERE coalesce(trim(first_name), '') = '' OR coalesce(trim(last_name), '') = ''
  UNION ALL
  SELECT member_id, 'tier or status not an allowed value' FROM members
  WHERE membership_tier NOT IN ('basic','standard','premium') OR status NOT IN ('active','cancelled')
     OR membership_tier IS NULL OR status IS NULL
) p;
