# FitTrack data quality

Data-quality test suite, report queries and findings for the FitTrack assignment.
The original brief is in [`ASSIGNMENT.md`](ASSIGNMENT.md).

| What | Where |
|---|---|
| Data-quality test suite | `run_checks.py` + `checks/*.sql` |
| Findings report | [`DATA_QUALITY.md`](DATA_QUALITY.md) |
| Required report | `reports/visits_per_branch.sql` |
| Bonus reports | `reports/active_members_monthly.sql`, `reports/daily_visits.sql`, `reports/friend_allowance_monthly.sql` |
| Investigation queries | `exploration/profiling.sql` |
| How I used AI | [`AI_USAGE.md`](AI_USAGE.md) |

## 1. Start the database

Requires Docker.

```bash
docker compose up -d --wait        # first start loads the data
```

`docker compose down -v` deletes the data; the next `up` reloads it.

## 2. Run the test suite

Requires Python 3.9+.

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

export PGHOST=localhost PGPORT=5432 PGDATABASE=fittrack PGUSER=fittrack PGPASSWORD=fittrack
python run_checks.py
```

The suite reads the connection **only** from the standard Postgres variables (`PGHOST`,
`PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`), so it runs against any database with the
same schema. It opens a read-only session and never changes data.

| Exit code | Meaning |
|---|---|
| `0` | No blocker failed. Reports can go out (warnings are printed for review) |
| `1` | At least one **blocker** failed. Do not publish reports from this load |
| `2` | The suite could not run (connection error or a broken check) |

Options:

```bash
python run_checks.py -k source_ref     # only checks whose file name contains "source_ref"
python run_checks.py --samples 10      # print up to 10 bad rows per failing check
```

**On the provided data the suite exits with `1`** (20 checks: 3 pass, 12 warn, 5 blockers fail, about 15 seconds). That is the expected result: the data
contains real blocker issues (duplicates, a wrong device clock, unknown members, casing).
They are explained in `DATA_QUALITY.md`, and the report queries handle them.

## 3. Add a check

Create a new file in `checks/`, for example `checks/21_my_rule.sql`. It holds a query that
returns **the rows that break the rule**, with a short header:

```sql
-- name: Every check-out has a branch
-- severity: blocker            -- or: warn
-- max_rows: 0                  -- optional: bad rows tolerated before failing
-- why: One line on which report it protects
SELECT event_id FROM events WHERE lower(event_type) = 'check_out' AND branch_id IS NULL;
```

No Python changes are needed; the runner picks up every `.sql` file in `checks/` in name order.

## 4. Run the reports

Each report is a single standalone query: it uses only the four source tables, creates
nothing, and runs in a read-only session.

```bash
psql -f reports/visits_per_branch.sql
psql -f reports/daily_visits.sql
psql -f reports/active_members_monthly.sql
psql -f reports/friend_allowance_monthly.sql
```

Without a local `psql`, run them through the database container:

```bash
docker compose exec -T db psql -U fittrack -d fittrack < reports/visits_per_branch.sql
```

The counting decisions (what is a visit, de-duplication, time zones, unknown members, tier
per month) are documented as comments at the top of each query. All four reports use the same
visit rules, so the daily member visits add up to the same total as `visits_per_branch`
(71,899 on the provided data).

## 5. CI

`.github/workflows/data-quality.yml` starts the database from `db/init`, runs both reports,
then runs the suite on every push. On the provided data the run is **red by design**, because
the blocker checks fail. A load without blockers turns it green.

## Checks at a glance

| # | Check | Severity |
|---|---|---|
| 01 | Event types are one of the 7 documented values | blocker |
| 02 | `source_ref` identifies exactly one event | blocker |
| 03 | Every event belongs to a known member | blocker |
| 04 | Each event comes from the right sender, device and branch | blocker |
| 05 | No event reaches the database before it happened | blocker |
| 06 | No events dated in the future | blocker |
| 07 | Access events happen within opening hours (local time) | warn |
| 08 | No day has more than double the usual access volume | warn |
| 09 | Every check-in is followed by a check-out at the same branch | warn |
| 10 | Friend visits happen together with the member's check-in | warn |
| 11 | Membership events follow a valid lifecycle | blocker |
| 12 | `details` JSON has the documented keys and values | blocker |
| 13 | `members` status and tier agree with the event history | warn |
| 14 | Member profiles are complete and plausible | warn |
| 15 | Members only check in while their membership is active | warn |
| 16 | Members bring no more friends per month than their tier allows | warn |
| 17 | No device events are missing (no gaps in device sequence numbers) | warn |
| 18 | CRM events arrive within a day of happening | warn |
| 19 | Every member has a membership history in the events | warn |
| 20 | No member checks in at two different branches within 30 minutes | warn |

## Time spent

About **5 hours** in one working session, plus environment setup (Docker, Git) and a first
look at the data the evening before.

| Part | Time |
|---|---|
| Data exploration and profiling (`exploration/profiling.sql`) | ~1.5 h |
| Required report `visits_per_branch` | ~0.25 h |
| Test suite: runner and 20 checks, validated with planted bad rows | ~1.5 h |
| Bonus reports: `daily_visits`, `active_members_monthly`, `friend_allowance_monthly` | ~0.5 h |
| `DATA_QUALITY.md`, `README.md`, `AI_USAGE.md`, CI workflow | ~1 h |
| Final check on a fresh database | ~0.25 h |

<!-- Update these figures to your real times before the final commit. -->
