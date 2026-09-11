-- OUR platform (MariaDB) — the merge TARGET. Empty by design: rows arrive from the
-- acquired company's MS SQL database. Deliberately a different model:
--   their users + company_users      -> accounts (one identity per human) + logins
--   their companies                  -> organisations (contact/address as JSON)
--   their company_users.role         -> memberships (account <-> organisation, N:N)
--   their categories (parent_id)     -> categories (materialised path)
--   their products + product_images  -> listings (media as JSON, review aggregates)
--   their addresses                  -> accounts.addresses JSON + order snapshots
--   their payments                   -> orders.payment JSON
--   their login_events (polymorphic) -> auth_events (real FK to accounts)
--
-- Columns marked [hop] are not in the source at all: Apache Hop computes them in
-- flight. They exist so the pipelines have something to demonstrate — a value
-- mapping, a range bucket, an aggregate — rather than a straight column copy.
-- metaunit is on every table: a constant 111 stamped by an "Add constants" transform.

CREATE DATABASE IF NOT EXISTS marketplace
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE marketplace;

CREATE TABLE organisations (
    id              UUID          NOT NULL PRIMARY KEY,
    org_number      VARCHAR(20)   NOT NULL,
    country         CHAR(2)       NOT NULL,
    name            VARCHAR(150)  NOT NULL,
    slug            VARCHAR(160)  NOT NULL,
    contact         JSON          NOT NULL,          -- {email, phone, www}
    address         JSON          NOT NULL,          -- {line1, line2, postal_code, city, country}
    status          ENUM('pending','active','suspended','closed') NOT NULL DEFAULT 'pending',
    status_label    VARCHAR(40)   NOT NULL,          -- [hop] Value mapper
    commission_rate DECIMAL(5,4)  NOT NULL DEFAULT 0.1000,
    created_at      TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    metaunit        SMALLINT      NOT NULL,
    UNIQUE KEY uq_org_number (country, org_number),
    UNIQUE KEY uq_org_slug (slug)
);

-- One row per human, whether they buy, sell, or both.
CREATE TABLE accounts (
    id           UUID         NOT NULL PRIMARY KEY,
    email        VARCHAR(255) NOT NULL,
    display_name VARCHAR(150) NOT NULL,
    phone        VARCHAR(20)  NULL,
    addresses    JSON         NULL,                  -- [{kind, line1, line2, postal_code, city, country}]
    status       ENUM('active','disabled','merged') NOT NULL DEFAULT 'active',
    merge_source ENUM('buyer','staff','both') NOT NULL,  -- [hop] which side(s) of the merge join matched
    last_seen_at TIMESTAMP   NULL DEFAULT NULL,
    created_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    metaunit     SMALLINT     NOT NULL,
    UNIQUE KEY uq_accounts_email (email)
);

-- Credentials are separate: one account can carry several ways to sign in.
CREATE TABLE logins (
    id           UUID        NOT NULL PRIMARY KEY,
    account_id   UUID        NOT NULL,
    provider     ENUM('password','vipps','bankid','google') NOT NULL,
    identifier   VARCHAR(255) NOT NULL,              -- email / subject / phone
    secret_hash  VARCHAR(120) NULL,                  -- password only
    is_active    TINYINT(1)  NOT NULL DEFAULT 1,
    source_rows  SMALLINT    NOT NULL DEFAULT 1,     -- [hop] Unique rows counter: 2 = the same human in both source tables
    last_used_at TIMESTAMP  NULL DEFAULT NULL,
    created_at   TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    metaunit     SMALLINT    NOT NULL,
    UNIQUE KEY uq_logins (provider, identifier),
    KEY ix_logins_account (account_id),
    CONSTRAINT fk_logins_account FOREIGN KEY (account_id) REFERENCES accounts(id)
);

CREATE TABLE memberships (
    account_id      UUID      NOT NULL,
    organisation_id UUID      NOT NULL,
    role            ENUM('owner','admin','staff') NOT NULL,
    account_email   VARCHAR(255) NULL,               -- [hop] Database lookup back into accounts
    is_active       TINYINT(1) NOT NULL DEFAULT 1,
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    metaunit        SMALLINT  NOT NULL,
    PRIMARY KEY (account_id, organisation_id),
    KEY ix_memberships_org (organisation_id),
    CONSTRAINT fk_memberships_account FOREIGN KEY (account_id) REFERENCES accounts(id),
    CONSTRAINT fk_memberships_org     FOREIGN KEY (organisation_id) REFERENCES organisations(id)
);

-- Materialised path instead of parent_id recursion.
CREATE TABLE categories (
    id        UUID         NOT NULL PRIMARY KEY,
    path      VARCHAR(255) NOT NULL,                 -- 'verktoy/handverktoy'
    root_slug VARCHAR(80)  NULL,                     -- [hop] Split fields on '/'
    leaf_slug VARCHAR(80)  NULL,                     -- [hop] Split fields on '/'
    name      VARCHAR(100) NOT NULL,
    depth     TINYINT      NOT NULL,
    created_at TIMESTAMP   NOT NULL,                 -- [hop] no date in the source: Get system info stamps the run
    level     TINYINT      NOT NULL,                 -- [hop] Calculator: depth + 1, 1-based for the UI
    metaunit  SMALLINT     NOT NULL,
    UNIQUE KEY uq_categories_path (path)
);

CREATE TABLE listings (
    id              UUID          NOT NULL PRIMARY KEY,
    organisation_id UUID          NOT NULL,
    category_path   VARCHAR(255)  NOT NULL,
    sku             VARCHAR(32)   NOT NULL,
    title           VARCHAR(200)  NOT NULL,
    body            TEXT          NULL,
    price_minor     BIGINT        NOT NULL,          -- øre, not DECIMAL
    price_band      ENUM('budget','mid','premium','luxury') NOT NULL,  -- [hop] Number range
    currency        CHAR(3)       NOT NULL DEFAULT 'NOK',
    stock           INT           NOT NULL DEFAULT 0,
    status          ENUM('draft','active','out_of_stock','archived') NOT NULL DEFAULT 'draft',
    media           JSON          NULL,              -- [{url, alt, sort}]
    rating_avg      DECIMAL(3,2)  NOT NULL DEFAULT 0.00,  -- [hop] If null -> 0.00
    rating_count    INT           NOT NULL DEFAULT 0,
    search_blob     TEXT          NULL,              -- [hop] Concat fields: title | sku | category
    created_at      TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    metaunit        SMALLINT      NOT NULL,
    UNIQUE KEY uq_listings_sku (organisation_id, sku),
    KEY ix_listings_org (organisation_id),
    KEY ix_listings_category (category_path),
    CONSTRAINT fk_listings_org FOREIGN KEY (organisation_id) REFERENCES organisations(id)
);

CREATE TABLE orders (
    id             UUID        NOT NULL PRIMARY KEY,
    reference      VARCHAR(20) NOT NULL,
    account_id     UUID        NOT NULL,
    placed_at      TIMESTAMP   NOT NULL,
    status         ENUM('pending','paid','shipped','completed','cancelled','refunded') NOT NULL,
    ship_to        JSON        NOT NULL,             -- address snapshot, not an FK
    bill_to        JSON        NOT NULL,
    payment        JSON        NULL,                 -- {method, status, amount_minor, ref, paid_at}
    subtotal_minor BIGINT      NOT NULL DEFAULT 0,
    shipping_minor BIGINT      NOT NULL DEFAULT 0,
    total_minor    BIGINT      NOT NULL DEFAULT 0,
    currency       CHAR(3)     NOT NULL DEFAULT 'NOK',
    metaunit       SMALLINT    NOT NULL,
    UNIQUE KEY uq_orders_reference (reference),
    KEY ix_orders_account (account_id, placed_at),
    CONSTRAINT fk_orders_account FOREIGN KEY (account_id) REFERENCES accounts(id)
);

-- [hop] Switch/case on status sends cancelled + refunded here instead: money that
-- never moved does not belong in the table the finance reports read.
CREATE TABLE orders_archive (
    id             UUID        NOT NULL PRIMARY KEY,
    reference      VARCHAR(20) NOT NULL,
    account_id     UUID        NOT NULL,
    placed_at      TIMESTAMP   NOT NULL,
    status         ENUM('cancelled','refunded') NOT NULL,
    total_minor    BIGINT      NOT NULL DEFAULT 0,
    currency       CHAR(3)     NOT NULL DEFAULT 'NOK',
    metaunit       SMALLINT    NOT NULL,
    KEY ix_orders_archive_account (account_id)
);

-- Snapshots title/sku so a delisted listing does not rewrite history.
CREATE TABLE order_lines (
    order_id         UUID         NOT NULL,
    line_no          SMALLINT     NOT NULL,
    listing_id       UUID         NULL,
    organisation_id  UUID         NOT NULL,
    sku_snapshot     VARCHAR(32)  NOT NULL,
    title_snapshot   VARCHAR(200) NOT NULL,
    quantity         INT          NOT NULL,
    unit_price_minor BIGINT       NOT NULL,
    line_total_minor BIGINT       NOT NULL,          -- [hop] Calculator, no longer a generated column
    placed_at        TIMESTAMP    NOT NULL,          -- carried down from the order so lines are queryable alone
    metaunit         SMALLINT     NOT NULL,
    PRIMARY KEY (order_id, line_no),
    KEY ix_order_lines_listing (listing_id),
    CONSTRAINT fk_lines_order   FOREIGN KEY (order_id) REFERENCES orders(id),
    CONSTRAINT fk_lines_listing FOREIGN KEY (listing_id) REFERENCES listings(id),
    CONSTRAINT fk_lines_org     FOREIGN KEY (organisation_id) REFERENCES organisations(id),
    CONSTRAINT ck_lines_qty CHECK (quantity > 0)
);

CREATE TABLE reviews (
    id         UUID         NOT NULL PRIMARY KEY,
    listing_id UUID         NOT NULL,
    account_id UUID         NOT NULL,
    rating     TINYINT      NOT NULL,
    title      VARCHAR(150) NULL,
    body       TEXT         NULL,
    created_at TIMESTAMP    NOT NULL,
    metaunit   SMALLINT     NOT NULL,
    UNIQUE KEY uq_reviews (listing_id, account_id),
    KEY ix_reviews_account (account_id),
    CONSTRAINT fk_reviews_listing FOREIGN KEY (listing_id) REFERENCES listings(id),
    CONSTRAINT fk_reviews_account FOREIGN KEY (account_id) REFERENCES accounts(id),
    CONSTRAINT ck_reviews_rating CHECK (rating BETWEEN 1 AND 5)
);

-- [hop] Filter rows: a review with no words in it is not a review. No FKs on
-- purpose — this is a holding pen someone looks at, not part of the model.
CREATE TABLE reviews_quarantine (
    id         UUID         NOT NULL PRIMARY KEY,
    listing_id UUID         NOT NULL,
    account_id UUID         NOT NULL,
    rating     TINYINT      NOT NULL,
    title      VARCHAR(150) NULL,
    body       TEXT         NULL,
    created_at TIMESTAMP    NOT NULL,
    metaunit   SMALLINT     NOT NULL
);

CREATE TABLE auth_events (
    id          BIGINT AUTO_INCREMENT PRIMARY KEY,
    account_id  UUID         NOT NULL,
    occurred_at TIMESTAMP    NOT NULL,
    provider    ENUM('password','vipps','bankid','google') NOT NULL,
    ip_address  VARBINARY(16) NULL,                  -- INET6_ATON, not a string
    user_agent  VARCHAR(300) NULL,
    success     TINYINT(1)   NOT NULL,
    metaunit    SMALLINT     NOT NULL,
    KEY ix_auth_events_account (account_id, occurred_at),
    CONSTRAINT fk_auth_events_account FOREIGN KEY (account_id) REFERENCES accounts(id)
);

-- [hop] Group by over the same stream that fills auth_events: one row per account,
-- so "has this person ever failed to sign in" is not a scan of 15k rows.
CREATE TABLE auth_summary (
    account_id   UUID      NOT NULL PRIMARY KEY,
    events       INT       NOT NULL,
    failures     INT       NOT NULL,
    first_seen   TIMESTAMP NOT NULL,
    last_seen    TIMESTAMP NOT NULL,
    metaunit     SMALLINT  NOT NULL,
    CONSTRAINT fk_auth_summary_account FOREIGN KEY (account_id) REFERENCES accounts(id)
);
