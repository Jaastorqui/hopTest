# What each pipeline does, and what it cannot do

Target is **Melvis on MariaDB**, schema taken verbatim from `apps/melvis/dbSchema.md`.
Source is the acquired company's MS SQL. One `.hpl` per target table, run in filename
order by `bin/hop-migrate.sh` with no arguments.

## Melvis conventions the pipelines have to honour

- **No foreign keys.** Nothing in the database stops a bad reference, so every check that
  would have been a constraint is a Filter rows step with a reject path.
- **`mi_id` is a master id**, not a table id, and `customer_master_id_lookup` is where the
  merge happens.
- **No Oferta id is ever stored in Melvis.** Every Melvis key is auto_increment and Melvis
  mints it. Where a pipeline needs a parent's Melvis id it re-reads the *origin* for the
  natural key and looks the Melvis row up by that:

  | child needs | natural key | verified |
  |---|---|---|
  | master id of a company | `org_number` ↔ `mi_org_nr` | unique both sides |
  | a person | `email` ↔ `us_email` | `unique_email` in Melvis |
  | `pr_id` of a product | `company + sku` ↔ `pr_slug` | 6000 / 6000 distinct |
  | `or_id` of an order | `(master id, placed_at)` ↔ `(mi_id, or_timestamp)` | 8000 / 8000 distinct |

  The cost is a lookup per row instead of arithmetic, and a hard dependency on those keys
  staying unique — if two of their orders ever share a company and a second, 06 attaches
  lines to the wrong one. The gain is that their numbering can change without touching us.
- **`(mi_id, mi_rel_type)`** only appears on four tables, all Econ: `econ_order`,
  `econ_invoice`, `econ_payments`, `econ_payment_details`. It is not a universal pattern.
- **`mi_rel_type` is a Constantine const.** The pipelines never write the number. They
  write the *name* and resolve it through the `constantine` table, so a renumbered const
  cannot silently repoint a row.
- **`meta*` on every table**, and `metaregtime`/`metauptime` are unix **seconds** in an
  `int(10)`. `0`, not NULL, is the empty value throughout.


## Per pipeline

| # | Target | Transforms worth looking at | Limitation |
|---|--------|------------------------------|------------|
| 00 | `constantine` | CSV input, truncate-on-load | Reference data from `hop/datasets/constantine.csv` — 420 consts copied out of Constantine.php and committed, so the project needs no melvis checkout. Truncate-on-load, so it is idempotent. The copy will drift from the PHP; the PHP header says never to change an existing const, which is what makes a copy safe enough. 14 of the 420 consts are declared in the PHP but missing from `ConstantineMapping`, so they resolve to a name and nothing else. |
| 01 | `customer_master_id_lookup` | **Merge join LEFT OUTER**, Filter rows | The merge. Matches on org number only — a company that changed org number, or is registered in another country, reads as new. A company Melvis already has gets nothing written at all - its master id exists and its data is ours, and an acquisition does not get to rewrite that. |
| 02 | `customer_companies` | two Database lookups, Filter rows | Inserts only the 170 companies Melvis has never seen. For the other 80 their data is discarded entirely — no field-level merge, no "fill in what we are missing". That is a deliberate choice and probably the first thing a real migration would revisit. |
| 03 | `customer_users` | **Merge join FULL OUTER**, Coalesce, Database lookup | Their `users` + `company_users` collapse to one human on email, then anyone Melvis already knows is skipped. Same caveat: we keep ours, theirs is dropped, including their password hash. |
| 04 | `econ_product` | Calculator, **String operations** | `pr_slug` is `company-sku` because their sku is only unique within a company. Melvis columns with no source equivalent (`tp_id`, `pr_unit`, `pr_vat`) are written as explicit constants rather than left to DDL defaults. |
| 05 | `econ_order` | Constant + **Database lookup on the const name** | `or_id` auto-generated. `mi_rel_type` resolved from Constantine by name. The owning company is the seller on the order's first line — their `orders` table has no company at all, which is the kind of gap only a rehearsal finds. An order whose company has no master id is rejected, not written with `mi_id = 0`. |
| 06 | `econ_order_line` | three Database lookups, two Filter rows | Both parent and product found by natural key, re-read from the origin. A line whose product did not migrate is rejected rather than orphaned. |

Not yet migrated: `econ_payments`, `econ_payment_details`, `econ_invoice` — the other
three `mi_rel_type` tables.

## Re-runs are NOT safe from 04 onward

01, 02 and 03 check before they write, so running them twice changes nothing. **04, 05 and
06 do not.** Melvis has no unique constraint on `econ_product.pr_slug`, `econ_order` or
`econ_order_line`, so a second run silently doubles all three — 6000 products become
12000, and every natural-key lookup afterwards then matches two rows.

Always `bin/reset-melvis.sh` before `bin/hop-migrate.sh`. Making them idempotent means a
lookup-then-filter in each, the same shape 02 and 03 already use; worth doing before this
runs anywhere that matters.

## Traps found the hard way

- **Hop parses date strings in the JVM default zone.** The field-level "date format
  timezone" only affects rendering back out, so setting it to UTC moves times the wrong
  way. `bin/hop-migrate.sh` sets `-Duser.timezone=UTC`; run the GUI with the same flag.
- **`Calculator`'s `COPY_OF_FIELD` creates the field and leaves it null.** To copy a
  field use `String operations` with a different output name.
- **`Select values` refuses to emit one field twice.** Same fix.
- **`Switch / case` does not expand `${...}`** in case values. Route on a looked-up name
  instead; it is the better design anyway.
- **`Get system info` replaces the incoming row** rather than adding to it. Not usable
  mid-stream.
- **`Table output`'s returned auto-increment key replaces the row**, so you cannot carry
  other fields past it into a mapping step.
- **`bin/reset-target.sh` is wrong for this target.** It truncates, which deletes the
  pre-existing Melvis data too, and then every merge branch looks like an insert. Use
  `bin/reset-melvis.sh`, which rebuilds from `init.sql` and restores the seed.
