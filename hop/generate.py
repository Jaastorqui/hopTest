#!/usr/bin/env python3
"""Generate one .hpl per target table from the specs below.

Design decision that shapes every pipeline: target UUIDs are DERIVED from the
source key (md5 of 'namespace:id'), not allocated. So a child pipeline computes
its parent's UUID with the same expression instead of looking it up, and a
re-run produces identical ids. See LIMITATIONS.md.
"""
from html import escape
from pathlib import Path

OUT = Path(__file__).parent / "pipelines"
SRC, DST = "mssql_source", "mariadb_target"


def _uuid_from(key_expr):
    """RFC-4122 UUIDv3 from an MD5 of key_expr.

    Raw MD5 hex is NOT a valid UUID: MariaDB's UUID type rejects anything whose
    variant nibble is outside 8-b. So force version=3 and variant=a, which is
    what a name-based UUID does anyway.
    """
    h = f"CONVERT(CHAR(32), HASHBYTES('MD5', {key_expr}), 2)"
    return (f"LOWER(SUBSTRING({h},1,8) + '-' + SUBSTRING({h},9,4) + '-3' + "
            f"SUBSTRING({h},14,3) + '-a' + SUBSTRING({h},18,3) + '-' + "
            f"SUBSTRING({h},21,12))")


def uid(ns, expr):
    """Deterministic UUID for an integer source key."""
    return _uuid_from(f"'{ns}:' + CAST({expr} AS VARCHAR(20))")


def uid_str(ns, expr):
    """Deterministic UUID for a string key (not truncated like uid())."""
    return _uuid_from(f"'{ns}:' + LOWER(LTRIM(RTRIM({expr})))")


def uid_email(expr):
    """Deterministic UUID for a person, keyed on normalised email."""
    return _uuid_from(f"'account:' + LOWER(LTRIM(RTRIM({expr})))")


# ---------------------------------------------------------------- xml pieces
def table_input(name, sql, x, y, copy_to_many):
    return f"""  <transform>
    <name>{escape(name)}</name>
    <type>TableInput</type>
    <connection>{SRC}</connection>
    <sql>{escape(sql)}</sql>
    <limit>0</limit>
    <execute_each_row>N</execute_each_row>
    <variables_active>N</variables_active>
    <lookup/>
    <sql_from_file/>
    <distribute>{'N' if copy_to_many else 'Y'}</distribute>
    <copies>1</copies>
    <GUI><xloc>{x}</xloc><yloc>{y}</yloc></GUI>
    <attributes/>
  </transform>
"""


def table_output(name, table, fields, x, y):
    rows = "".join(
        f"      <field><stream_name>{f}</stream_name>"
        f"<column_name>{f}</column_name></field>\n" for f in fields)
    return f"""  <transform>
    <name>{escape(name)}</name>
    <type>TableOutput</type>
    <connection>{DST}</connection>
    <schema/>
    <table>{table}</table>
    <commit>1000</commit>
    <truncate>N</truncate>
    <only_when_have_rows>N</only_when_have_rows>
    <ignore_errors>N</ignore_errors>
    <use_batch>Y</use_batch>
    <specify_fields>Y</specify_fields>
    <partitioning_enabled>N</partitioning_enabled>
    <partitioning_daily>N</partitioning_daily>
    <partitioning_monthly>Y</partitioning_monthly>
    <tablename_in_field>N</tablename_in_field>
    <tablename_field/>
    <tablename_in_table>Y</tablename_in_table>
    <return_keys>N</return_keys>
    <return_field/>
    <auto_update_table_structure>N</auto_update_table_structure>
    <always_drop_and_recreate>N</always_drop_and_recreate>
    <add_columns>N</add_columns>
    <drop_columns>N</drop_columns>
    <change_column_types>N</change_column_types>
    <fields>
{rows}    </fields>
    <distribute>Y</distribute>
    <copies>1</copies>
    <GUI><xloc>{x}</xloc><yloc>{y}</yloc></GUI>
    <attributes/>
  </transform>
"""


MAP_FIELDS = ["source_table", "source_id", "target_table", "target_id", "note"]


def build(spec):
    xml = ['<?xml version="1.0" encoding="UTF-8"?>\n<pipeline>\n  <info>\n'
           f'    <name>{spec["name"]}</name>\n'
           '    <name_sync_with_filename>Y</name_sync_with_filename>\n'
           '    <pipeline_type>Normal</pipeline_type>\n'
           '    <pipeline_status>-1</pipeline_status>\n    <parameters/>\n'
           f'    <description>{escape(spec["desc"])}</description>\n  </info>\n']
    hops, y = [], 96
    for branch in spec["branches"]:
        outs = branch["outputs"]
        xml.append(table_input(branch["input"], branch["sql"], 176, y, len(outs) > 1))
        for i, (oname, table, fields) in enumerate(outs):
            xml.append(table_output(oname, table, fields, 560, y + i * 96))
            hops.append((branch["input"], oname))
        y += max(len(outs), 1) * 96 + 64
    xml.append("  <order>\n")
    for a, b in hops:
        xml.append(f"    <hop><from>{escape(a)}</from><to>{escape(b)}</to>"
                   "<enabled>Y</enabled></hop>\n")
    xml.append("  </order>\n  <notepads/>\n  <attributes/>\n"
               "  <transform_error_handling/>\n</pipeline>\n")
    return "".join(xml)


def simple(name, desc, sql, table, fields, source_table=None, target_table=None):
    """One input, one target table, optionally also a migration_map row."""
    outputs = [(f"→ {table}", table, fields)]
    if source_table:
        outputs.append(("→ migration_map", "migration_map", MAP_FIELDS))
    return {"name": name, "desc": desc,
            "branches": [{"input": f"{source_table or table} (mssql)",
                          "sql": sql, "outputs": outputs}]}


# --------------------------------------------------------------------- specs
CAT_TREE = """WITH tree AS (
    SELECT c.id, c.parent_id, c.name, CAST(c.slug AS VARCHAR(255)) AS path, 0 AS depth
    FROM categories c WHERE c.parent_id IS NULL
    UNION ALL
    SELECT c.id, c.parent_id, c.name, CAST(t.path + '/' + c.slug AS VARCHAR(255)), t.depth + 1
    FROM categories c JOIN tree t ON t.id = c.parent_id
)"""

# users and company_users are two disjoint identity tables in the source; one
# human can appear in both. Rank so the buyer row wins, and key on email.
PRINCIPALS = """WITH principals AS (
    SELECT 'users' AS src_table, u.id AS src_id,
           LOWER(LTRIM(RTRIM(u.email))) AS email,
           u.first_name + N' ' + u.last_name AS display_name,
           u.phone AS phone, u.password_hash AS password_hash, u.is_active AS is_active,
           u.last_login_at AS last_seen_at, u.created_at AS created_at,
           (SELECT a.kind AS kind, a.line1 AS line1, a.line2 AS line2,
                   a.postal_code AS postal_code, a.city AS city, a.country AS country
            FROM addresses a WHERE a.user_id = u.id FOR JSON PATH) AS addresses,
           1 AS pref
    FROM users u
    UNION ALL
    SELECT 'company_users', cu.id, LOWER(LTRIM(RTRIM(cu.email))), cu.full_name,
           NULL, cu.password_hash, cu.is_active, cu.last_login_at, cu.created_at, NULL, 2
    FROM company_users cu
), ranked AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY email ORDER BY pref, src_id) AS rn
    FROM principals
)"""

SPECS = [
    simple("01-organisations", "companies -> organisations (contact/address as JSON)", f"""
SELECT {uid('companies', 'c.id')} AS id,
       c.org_number, c.country, c.name, c.slug,
       (SELECT c.email AS email, c.phone AS phone
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS contact,
       (SELECT c.address_line1 AS line1, c.address_line2 AS line2,
               c.postal_code AS postal_code, c.city AS city, c.country AS country
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS address,
       c.status, c.commission_rate,
       CONVERT(VARCHAR(19), c.created_at, 120) AS created_at,
       'companies' AS source_table, CAST(c.id AS VARCHAR(40)) AS source_id,
       'organisations' AS target_table, {uid('companies', 'c.id')} AS target_id,
       'derived uuid' AS note
FROM companies c""".strip(),
        "organisations",
        ["id", "org_number", "country", "name", "slug", "contact", "address",
         "status", "commission_rate", "created_at"],
        source_table="companies"),

    # Two branches on purpose: accounts is one row per human, migration_map is
    # one row per SOURCE row. Different cardinality, so different queries.
    {"name": "02-accounts",
     "desc": "users + company_users -> accounts, deduplicated on email",
     "branches": [
         {"input": "distinct humans (mssql)",
          "sql": f"""{PRINCIPALS}
SELECT {uid_email('email')} AS id,
       email, display_name, phone, addresses,
       CASE WHEN is_active = 1 THEN 'active' ELSE 'disabled' END AS status,
       CONVERT(VARCHAR(19), last_seen_at, 120) AS last_seen_at,
       CONVERT(VARCHAR(19), created_at, 120) AS created_at
FROM ranked WHERE rn = 1""",
          "outputs": [("→ accounts", "accounts",
                       ["id", "email", "display_name", "phone", "addresses",
                        "status", "last_seen_at", "created_at"])]},
         {"input": "every source row (mssql)",
          "sql": f"""{PRINCIPALS}
SELECT src_table AS source_table, CAST(src_id AS VARCHAR(40)) AS source_id,
       'accounts' AS target_table, {uid_email('email')} AS target_id,
       CASE WHEN rn = 1 THEN 'primary' ELSE 'merged into existing account (same email)' END AS note
FROM ranked""",
          "outputs": [("→ migration_map", "migration_map", MAP_FIELDS)]}]},

    simple("03-logins", "password hashes from both identity tables -> logins", f"""
{PRINCIPALS}
SELECT {uid_str('login', 'email')} AS id,
       {uid_email('email')} AS account_id,
       'password' AS provider, email AS identifier,
       password_hash AS secret_hash, is_active,
       CONVERT(VARCHAR(19), last_seen_at, 120) AS last_used_at,
       CONVERT(VARCHAR(19), created_at, 120) AS created_at
FROM ranked WHERE rn = 1""".strip(),
        "logins",
        ["id", "account_id", "provider", "identifier", "secret_hash",
         "is_active", "last_used_at", "created_at"]),

    simple("04-memberships", "company_users.role -> memberships (account <-> organisation)", f"""
WITH m AS (
    SELECT {uid_email('cu.email')} AS account_id,
           {uid('companies', 'cu.company_id')} AS organisation_id,
           cu.role, cu.is_active,
           CONVERT(VARCHAR(19), cu.created_at, 120) AS created_at,
           ROW_NUMBER() OVER (PARTITION BY LOWER(LTRIM(RTRIM(cu.email))), cu.company_id
                              ORDER BY cu.id) AS rn
    FROM company_users cu
)
SELECT account_id, organisation_id, role, is_active, created_at
FROM m WHERE rn = 1""".strip(),
        "memberships",
        ["account_id", "organisation_id", "role", "is_active", "created_at"]),

    simple("05-categories", "categories.parent_id -> materialised path", f"""
{CAT_TREE}
SELECT {uid('categories', 'id')} AS id, path, name, depth FROM tree""".strip(),
        "categories", ["id", "path", "name", "depth"],
        source_table=None),

    simple("06-listings", "products + product_images -> listings (media JSON, price in minor units)", f"""
{CAT_TREE}
SELECT {uid('products', 'p.id')} AS id,
       {uid('companies', 'p.company_id')} AS organisation_id,
       t.path AS category_path,
       p.sku, p.name AS title, p.description AS body,
       CAST(ROUND(p.price * 100, 0) AS BIGINT) AS price_minor,
       p.currency, p.stock, p.status,
       (SELECT pi.url AS url, pi.alt_text AS alt, pi.sort_order AS sort
        FROM product_images pi WHERE pi.product_id = p.id
        ORDER BY pi.sort_order FOR JSON PATH) AS media,
       r.rating_avg, ISNULL(r.rating_count, 0) AS rating_count,
       CONVERT(VARCHAR(19), p.created_at, 120) AS created_at,
       'products' AS source_table, CAST(p.id AS VARCHAR(40)) AS source_id,
       'listings' AS target_table, {uid('products', 'p.id')} AS target_id,
       'derived uuid' AS note
FROM products p
JOIN tree t ON t.id = p.category_id
LEFT JOIN (SELECT product_id,
                  CAST(AVG(CAST(rating AS DECIMAL(5,2))) AS DECIMAL(3,2)) AS rating_avg,
                  COUNT(*) AS rating_count
           FROM reviews GROUP BY product_id) r ON r.product_id = p.id""".strip(),
        "listings",
        ["id", "organisation_id", "category_path", "sku", "title", "body",
         "price_minor", "currency", "stock", "status", "media",
         "rating_avg", "rating_count", "created_at"],
        source_table="products"),

    simple("07-orders", "orders + addresses + payments -> orders (snapshots as JSON)", f"""
SELECT {uid('orders', 'o.id')} AS id,
       CONCAT('ORD-', RIGHT('00000000' + CAST(o.id AS VARCHAR(8)), 8)) AS reference,
       {uid_email('u.email')} AS account_id,
       CONVERT(VARCHAR(19), o.placed_at, 120) AS placed_at,
       o.status,
       (SELECT sa.line1 AS line1, sa.line2 AS line2, sa.postal_code AS postal_code,
               sa.city AS city, sa.country AS country
        FROM addresses sa WHERE sa.id = o.shipping_address_id
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS ship_to,
       (SELECT ba.line1 AS line1, ba.line2 AS line2, ba.postal_code AS postal_code,
               ba.city AS city, ba.country AS country
        FROM addresses ba WHERE ba.id = o.billing_address_id
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS bill_to,
       (SELECT TOP 1 pm.method AS method, pm.status AS status,
               CAST(ROUND(pm.amount * 100, 0) AS BIGINT) AS amount_minor,
               pm.transaction_ref AS ref,
               CONVERT(VARCHAR(19), pm.paid_at, 120) AS paid_at
        FROM payments pm WHERE pm.order_id = o.id
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS payment,
       CAST(ROUND(o.subtotal * 100, 0) AS BIGINT) AS subtotal_minor,
       CAST(ROUND(o.shipping_cost * 100, 0) AS BIGINT) AS shipping_minor,
       CAST(ROUND(o.total * 100, 0) AS BIGINT) AS total_minor,
       o.currency,
       'orders' AS source_table, CAST(o.id AS VARCHAR(40)) AS source_id,
       'orders' AS target_table, {uid('orders', 'o.id')} AS target_id,
       'derived uuid' AS note
FROM orders o JOIN users u ON u.id = o.user_id""".strip(),
        "orders",
        ["id", "reference", "account_id", "placed_at", "status", "ship_to",
         "bill_to", "payment", "subtotal_minor", "shipping_minor",
         "total_minor", "currency"],
        source_table="orders"),

    simple("08-order-lines", "order_items -> order_lines (line_total is generated, not inserted)", f"""
SELECT {uid('orders', 'oi.order_id')} AS order_id,
       ROW_NUMBER() OVER (PARTITION BY oi.order_id ORDER BY oi.id) AS line_no,
       {uid('products', 'oi.product_id')} AS listing_id,
       {uid('companies', 'oi.company_id')} AS organisation_id,
       p.sku AS sku_snapshot, p.name AS title_snapshot,
       oi.quantity,
       CAST(ROUND(oi.unit_price * 100, 0) AS BIGINT) AS unit_price_minor
FROM order_items oi JOIN products p ON p.id = oi.product_id""".strip(),
        "order_lines",
        ["order_id", "line_no", "listing_id", "organisation_id",
         "sku_snapshot", "title_snapshot", "quantity", "unit_price_minor"]),

    simple("09-reviews", "reviews -> reviews (listing and account by derived uuid)", f"""
SELECT {uid('reviews', 'r.id')} AS id,
       {uid('products', 'r.product_id')} AS listing_id,
       {uid_email('u.email')} AS account_id,
       r.rating, r.title, r.body,
       CONVERT(VARCHAR(19), r.created_at, 120) AS created_at
FROM reviews r JOIN users u ON u.id = r.user_id""".strip(),
        "reviews", ["id", "listing_id", "account_id", "rating", "title",
                    "body", "created_at"]),

    simple("10-auth-events", "login_events (polymorphic principal) -> auth_events (real FK)", f"""
SELECT {uid_email('COALESCE(u.email, cu.email)')} AS account_id,
       CONVERT(VARCHAR(19), le.occurred_at, 120) AS occurred_at,
       'password' AS provider,
       CAST(CAST(PARSENAME(le.ip_address, 4) AS TINYINT) AS BINARY(1))
     + CAST(CAST(PARSENAME(le.ip_address, 3) AS TINYINT) AS BINARY(1))
     + CAST(CAST(PARSENAME(le.ip_address, 2) AS TINYINT) AS BINARY(1))
     + CAST(CAST(PARSENAME(le.ip_address, 1) AS TINYINT) AS BINARY(1)) AS ip_address,
       le.user_agent, le.success
FROM login_events le
LEFT JOIN users u         ON le.principal_type = 'user'  AND u.id  = le.principal_id
LEFT JOIN company_users cu ON le.principal_type = 'staff' AND cu.id = le.principal_id
WHERE COALESCE(u.email, cu.email) IS NOT NULL""".strip(),
        "auth_events",
        ["account_id", "occurred_at", "provider", "ip_address",
         "user_agent", "success"]),
]

if __name__ == "__main__":
    import sys
    if "--dump-sql" in sys.argv:
        for s in SPECS:
            for b in s["branches"]:
                print(f"-- ===== {s['name']} :: {b['input']}\n{b['sql']};\nGO")
    else:
        for s in SPECS:
            p = OUT / f"{s['name']}.hpl"
            p.write_text(build(s))
            print(f"wrote {p.relative_to(OUT.parent.parent)}")
