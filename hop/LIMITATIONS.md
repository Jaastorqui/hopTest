# What each pipeline does, and what it cannot do

One `.hpl` per target table, run in filename order (`bin/hop-migrate.sh` with no
arguments). The numbers are the FK order, not a preference.

## Cross-cutting

- **Target ids are derived, not allocated.** Every uuid is `md5('<namespace>:<key>')`
  shaped into a valid UUIDv3. A child pipeline computes its parent's id from the same
  source value rather than looking it up, so re-runs are stable and the pipelines do
  not have to run in one transaction. The cost: change a key (an email, say) and the
  row becomes a different row.
- **Full reload, not incremental.** Nothing reads a watermark. Re-running against a
  populated target fails on the primary key — truncate first (`bin/reset-target.sh`).
- **No conflict handling against rows we already have.** The target is assumed empty.
  Real pre-existing accounts on our side would need a match-and-merge step that does
  not exist yet.
- **Execution order is a dependency, not a preference.** 04 reads accounts that 02
  wrote; 08 writes children of rows 07 created.
- **Timezones live in two places.** Their MS SQL box runs UTC. Hop parses date strings
  using the **JVM default zone**, so `bin/hop-migrate.sh` sets `-Duser.timezone=UTC`;
  the field-level "date format timezone" only affects rendering back out and will not
  fix this. MariaDB runs `--default-time-zone=Europe/Oslo`, so stored instants display
  as Norwegian wall-clock and DST is the zone database's problem (verified: an August
  order shifts +2h, a November one +1h). Run the GUI with the same flag or its previews
  will disagree with the pipeline by an hour or two.
- **`metaunit = 111`** is stamped on every target row by an "Add constants" transform.

## Per pipeline

| # | Pipeline | Transforms worth looking at | Limitation |
|---|----------|------------------------------|------------|
| 01 | organisations | Value mapper, String operations | `status_label` is a fixed four-way mapping; an unknown source status silently becomes `Unknown` rather than failing. |
| 02 | accounts | **Merge join FULL OUTER**, Concat fields, Value mapper, Coalesce | The merge itself. 3000 buyers ⋈ 625 staff on email = 3565 humans, 60 of them matched on both sides. Buyer row wins every field it has; a staff row's phone is lost because their `company_users` has no phone column. Matching is exact-email only — same human, two addresses, stays two accounts. |
| 03 | logins | Append streams, Sort rows, **Unique rows** | Keeps one password hash per email and counts the duplicates in `source_rows`. The 60 merged humans lose their staff-side hash; they sign in with the buyer password or reset. Sort before unique is load-bearing: Unique rows only removes *adjacent* duplicates. |
| 04 | memberships | **Database lookup** | Reads back the accounts 02 wrote. A miss means 02 dropped someone, so the lookup doubles as the assertion — but it is not *enforced*: a miss writes a NULL `account_email`, it does not fail the run. |
| 05 | categories | Split fields, Coalesce, Calculator | `path_parts` is duplicated in the query because Hop's Calculator `COPY_OF_FIELD` creates the field but leaves it null. The splitter is fixed at three levels; a fourth-level category would lose its leaf. Their table has no date at all, so `created_at` is the run time. |
| 06 | listings | If null, **Number range**, Concat fields | Price bands are hardcoded øre boundaries (500 / 2000 / 10000 kr) — they are a display concern baked into storage, and repricing does not move a listing between bands until the next full load. |
| 07 | orders | **Switch / case** | Cancelled and refunded orders go to `orders_archive`, which keeps only 8 of the 13 columns — the JSON snapshots are dropped. That is deliberate, and it is also irreversible from the target alone. Only the first payment per order is kept. |
| 08 | order_lines | Filter rows, Calculator | Lines belonging to archived orders are **dropped**, not archived: 18 957 of 20 000. This is the direct consequence of 07's split, which is why the filter is in the graph and not hidden in the SQL. |
| 09 | reviews | String operations, **Filter rows** | Bodyless reviews go to `reviews_quarantine`, which has no foreign keys — it is a holding pen, so a quarantined review can reference a listing that no longer exists. |
| 10 | auth_events | Calculator, Sort rows, **Group by** | One stream feeds both the detail table and a per-account summary. IPv4 only — an IPv6 address in `login_events` makes `PARSENAME` return NULL and the row lands with a null IP. `provider` is hardcoded `'password'` because their source has no column for it. |

## Known rough edges

- `reviews_quarantine` catches nothing unless the source actually has bodyless reviews.
  `mssql/init.sql` now seeds some; an already-running source needs the one-line UPDATE.
- Hop's `Get system info` transform **replaces** the incoming row rather than adding to
  it. Do not put it mid-stream.
