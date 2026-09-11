-- Marketplace SOURCE schema (MS SQL Server). Re-runnable: drops and rebuilds.
IF DB_ID('marketplace') IS NULL CREATE DATABASE marketplace;
GO
USE marketplace;
GO

DROP TABLE IF EXISTS login_events, reviews, payments, order_items, orders, product_images,
                     products, categories, addresses, company_users, users, companies;
GO

-- ---------------------------------------------------------------- structure
CREATE TABLE companies (
    id              INT IDENTITY(1,1) PRIMARY KEY,
    org_number      VARCHAR(9)     NOT NULL UNIQUE,
    name            NVARCHAR(150)  NOT NULL,
    slug            VARCHAR(160)   NOT NULL UNIQUE,
    email           NVARCHAR(255)  NOT NULL,
    phone           VARCHAR(20)    NULL,
    address_line1   NVARCHAR(150)  NOT NULL,
    address_line2   NVARCHAR(150)  NULL,
    postal_code     VARCHAR(10)    NOT NULL,
    city            NVARCHAR(100)  NOT NULL,
    country         CHAR(2)        NOT NULL,
    status          VARCHAR(20)    NOT NULL CHECK (status IN ('pending','active','suspended','closed')),
    commission_rate DECIMAL(5,4)   NOT NULL DEFAULT 0.1000,
    created_at      DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE TABLE users (
    id          INT IDENTITY(1,1) PRIMARY KEY,
    email       NVARCHAR(255) NOT NULL UNIQUE,
    first_name  NVARCHAR(80)  NOT NULL,
    last_name   NVARCHAR(80)  NOT NULL,
    phone         VARCHAR(20)   NULL,
    password_hash VARCHAR(120)  NOT NULL,
    is_active     BIT           NOT NULL DEFAULT 1,
    last_login_at DATETIME2     NULL,
    created_at    DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME()
);

-- Seller-side staff logins live in their OWN table here, disjoint from users.
CREATE TABLE company_users (
    id            INT IDENTITY(1,1) PRIMARY KEY,
    company_id    INT           NOT NULL REFERENCES companies(id),
    email         NVARCHAR(255) NOT NULL UNIQUE,
    full_name     NVARCHAR(150) NOT NULL,
    password_hash VARCHAR(120)  NOT NULL,
    role          VARCHAR(20)   NOT NULL CHECK (role IN ('owner','admin','staff')),
    is_active     BIT           NOT NULL DEFAULT 1,
    last_login_at DATETIME2     NULL,
    created_at    DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME()
);
CREATE INDEX ix_company_users_company ON company_users(company_id);

CREATE TABLE addresses (
    id          INT IDENTITY(1,1) PRIMARY KEY,
    user_id     INT           NOT NULL REFERENCES users(id),
    kind        VARCHAR(10)   NOT NULL CHECK (kind IN ('shipping','billing')),
    line1       NVARCHAR(150) NOT NULL,
    line2       NVARCHAR(150) NULL,
    postal_code VARCHAR(10)   NOT NULL,
    city        NVARCHAR(100) NOT NULL,
    country     CHAR(2)       NOT NULL
);
CREATE INDEX ix_addresses_user ON addresses(user_id, kind);

CREATE TABLE categories (
    id        INT IDENTITY(1,1) PRIMARY KEY,
    parent_id INT           NULL REFERENCES categories(id),
    name      NVARCHAR(100) NOT NULL,
    slug      VARCHAR(120)  NOT NULL UNIQUE
);

CREATE TABLE products (
    id          INT IDENTITY(1,1) PRIMARY KEY,
    company_id  INT            NOT NULL REFERENCES companies(id),
    category_id INT            NOT NULL REFERENCES categories(id),
    sku         VARCHAR(32)    NOT NULL UNIQUE,
    name        NVARCHAR(200)  NOT NULL,
    description NVARCHAR(MAX)  NULL,
    price       DECIMAL(10,2)  NOT NULL CHECK (price >= 0),
    currency    CHAR(3)        NOT NULL DEFAULT 'NOK',
    stock       INT            NOT NULL DEFAULT 0,
    status      VARCHAR(20)    NOT NULL CHECK (status IN ('draft','active','out_of_stock','archived')),
    created_at  DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);
CREATE INDEX ix_products_company  ON products(company_id);
CREATE INDEX ix_products_category ON products(category_id);

CREATE TABLE product_images (
    id         INT IDENTITY(1,1) PRIMARY KEY,
    product_id INT           NOT NULL REFERENCES products(id),
    url        VARCHAR(400)  NOT NULL,
    alt_text   NVARCHAR(200) NULL,
    sort_order TINYINT       NOT NULL,
    CONSTRAINT uq_product_images UNIQUE (product_id, sort_order)
);

CREATE TABLE orders (
    id                  INT IDENTITY(1,1) PRIMARY KEY,
    user_id             INT           NOT NULL REFERENCES users(id),
    placed_at           DATETIME2     NOT NULL,
    status              VARCHAR(20)   NOT NULL CHECK (status IN ('pending','paid','shipped','completed','cancelled','refunded')),
    shipping_address_id INT           NOT NULL REFERENCES addresses(id),
    billing_address_id  INT           NOT NULL REFERENCES addresses(id),
    subtotal            DECIMAL(12,2) NOT NULL DEFAULT 0,
    shipping_cost       DECIMAL(12,2) NOT NULL DEFAULT 0,
    total               DECIMAL(12,2) NOT NULL DEFAULT 0,
    currency            CHAR(3)       NOT NULL DEFAULT 'NOK'
);
CREATE INDEX ix_orders_user ON orders(user_id, placed_at);

CREATE TABLE order_items (
    id         INT IDENTITY(1,1) PRIMARY KEY,
    order_id   INT           NOT NULL REFERENCES orders(id),
    product_id INT           NOT NULL REFERENCES products(id),
    company_id INT           NOT NULL REFERENCES companies(id),
    quantity   INT           NOT NULL CHECK (quantity > 0),
    unit_price DECIMAL(10,2) NOT NULL,
    line_total AS (quantity * unit_price) PERSISTED,
    CONSTRAINT uq_order_items UNIQUE (order_id, product_id)
);
CREATE INDEX ix_order_items_product ON order_items(product_id);

CREATE TABLE payments (
    id              INT IDENTITY(1,1) PRIMARY KEY,
    order_id        INT           NOT NULL REFERENCES orders(id),
    method          VARCHAR(20)   NOT NULL CHECK (method IN ('card','vipps','invoice','klarna')),
    status          VARCHAR(20)   NOT NULL CHECK (status IN ('authorized','captured','failed','refunded')),
    amount          DECIMAL(12,2) NOT NULL,
    transaction_ref VARCHAR(40)   NOT NULL UNIQUE,
    paid_at         DATETIME2     NULL
);
CREATE INDEX ix_payments_order ON payments(order_id);

CREATE TABLE reviews (
    id         INT IDENTITY(1,1) PRIMARY KEY,
    product_id INT           NOT NULL REFERENCES products(id),
    user_id    INT           NOT NULL REFERENCES users(id),
    rating     TINYINT       NOT NULL CHECK (rating BETWEEN 1 AND 5),
    title      NVARCHAR(150) NULL,
    body       NVARCHAR(MAX) NULL,
    created_at DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT uq_reviews UNIQUE (product_id, user_id)
);
GO
-- Polymorphic, no FK: 'user' -> users.id, 'staff' -> company_users.id.
CREATE TABLE login_events (
    id             BIGINT IDENTITY(1,1) PRIMARY KEY,
    principal_type VARCHAR(10)   NOT NULL CHECK (principal_type IN ('user','staff')),
    principal_id   INT           NOT NULL,
    occurred_at    DATETIME2     NOT NULL,
    ip_address     VARCHAR(45)   NOT NULL,
    user_agent     NVARCHAR(300) NULL,
    success        BIT           NOT NULL
);
CREATE INDEX ix_login_events_principal ON login_events(principal_type, principal_id, occurred_at);
GO
-- ------------------------------------------------------------------- data
SET NOCOUNT ON;

SELECT TOP (60000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i
INTO #n FROM sys.all_objects a CROSS JOIN sys.all_objects b;
CREATE UNIQUE CLUSTERED INDEX ix_n ON #n(i);

DECLARE @city TABLE (r INT IDENTITY(0,1), name NVARCHAR(50), zip VARCHAR(10), cc CHAR(2));
INSERT INTO @city (name, zip, cc) VALUES
 (N'Oslo','0150','NO'),(N'Bergen','5003','NO'),(N'Trondheim','7010','NO'),(N'Stavanger','4005','NO'),
 (N'Tromsø','9008','NO'),(N'Kristiansand','4610','NO'),(N'Drammen','3015','NO'),(N'Ålesund','6002','NO'),
 (N'Stockholm','11120','SE'),(N'Göteborg','41103','SE'),(N'København','1050','DK'),(N'Aarhus','8000','DK'),
 (N'Helsinki','00100','FI');
DECLARE @ncity INT = (SELECT COUNT(*) FROM @city);

DECLARE @street TABLE (r INT IDENTITY(0,1), name NVARCHAR(60));
INSERT INTO @street (name) VALUES
 (N'Storgata'),(N'Kirkeveien'),(N'Industriveien'),(N'Havnegata'),(N'Bjørnsons gate'),(N'Solbakken'),
 (N'Fjellveien'),(N'Parkveien'),(N'Nedre Slottsgate'),(N'Trondheimsveien'),(N'Verkstedveien'),(N'Sjøgata');
DECLARE @nstreet INT = (SELECT COUNT(*) FROM @street);

DECLARE @cop1 TABLE (r INT IDENTITY(0,1), w NVARCHAR(30));
INSERT INTO @cop1 (w) VALUES (N'Nordisk'),(N'Fjord'),(N'Vik'),(N'Berg'),(N'Sør'),(N'Nord'),(N'Bjørn'),
 (N'Granit'),(N'Elv'),(N'Skog'),(N'Kyst'),(N'Polar'),(N'Midt'),(N'Vest'),(N'Øst'),(N'Stål'),(N'Tre'),(N'Sol');
DECLARE @cop2 TABLE (r INT IDENTITY(0,1), w NVARCHAR(30));
INSERT INTO @cop2 (w) VALUES (N'Bygg'),(N'Handel'),(N'Verktøy'),(N'Teknikk'),(N'Marine'),(N'Elektro'),
 (N'Montasje'),(N'Logistikk'),(N'Design'),(N'Service'),(N'Produkter'),(N'Anlegg');
DECLARE @cop3 TABLE (r INT IDENTITY(0,1), w NVARCHAR(10));
INSERT INTO @cop3 (w) VALUES (N'AS'),(N'ASA'),(N'AB'),(N'ApS'),(N'Group');
DECLARE @nc1 INT=(SELECT COUNT(*) FROM @cop1), @nc2 INT=(SELECT COUNT(*) FROM @cop2), @nc3 INT=(SELECT COUNT(*) FROM @cop3);

DECLARE @first TABLE (r INT IDENTITY(0,1), w NVARCHAR(40));
INSERT INTO @first (w) VALUES (N'Kari'),(N'Ola'),(N'Ingrid'),(N'Lars'),(N'Astrid'),(N'Magnus'),(N'Sofie'),
 (N'Erik'),(N'Nora'),(N'Håkon'),(N'Emma'),(N'Jonas'),(N'Maja'),(N'Anders'),(N'Thea'),(N'Sindre'),
 (N'Linnea'),(N'Fredrik'),(N'Amalie'),(N'Yusuf'),(N'Aisha'),(N'Piotr'),(N'Elena'),(N'Mateo');
DECLARE @last TABLE (r INT IDENTITY(0,1), w NVARCHAR(40));
INSERT INTO @last (w) VALUES (N'Hansen'),(N'Johansen'),(N'Olsen'),(N'Larsen'),(N'Andersen'),(N'Nilsen'),
 (N'Pedersen'),(N'Kristiansen'),(N'Berg'),(N'Haugen'),(N'Moen'),(N'Lie'),(N'Solberg'),(N'Dahl'),
 (N'Nowak'),(N'Ahmed'),(N'Rossi'),(N'García');
DECLARE @nf INT=(SELECT COUNT(*) FROM @first), @nl INT=(SELECT COUNT(*) FROM @last);

DECLARE @adj TABLE (r INT IDENTITY(0,1), w NVARCHAR(30));
INSERT INTO @adj (w) VALUES (N'Profesjonell'),(N'Kompakt'),(N'Robust'),(N'Trådløs'),(N'Justerbar'),
 (N'Isolert'),(N'Sammenleggbar'),(N'Forsterket'),(N'Vanntett'),(N'Lett'),(N'Premium'),(N'Klassisk');
DECLARE @noun TABLE (r INT IDENTITY(0,1), w NVARCHAR(40));
INSERT INTO @noun (w) VALUES (N'drill'),(N'vinkelsliper'),(N'stillas'),(N'hansker'),(N'arbeidslampe'),
 (N'målebånd'),(N'sag'),(N'hammer'),(N'skrutrekkersett'),(N'kompressor'),(N'stige'),(N'hjelm'),
 (N'vernebriller'),(N'sement'),(N'isolasjon'),(N'terrassebord'),(N'maling'),(N'kabeltrommel');
DECLARE @na INT=(SELECT COUNT(*) FROM @adj), @nn INT=(SELECT COUNT(*) FROM @noun);

-- categories: 8 roots then 32 leaves (leaf ids stay contiguous)
INSERT INTO categories (parent_id, name, slug) VALUES
 (NULL,N'Verktøy','verktoy'),(NULL,N'Byggevarer','byggevarer'),(NULL,N'Elektro','elektro'),
 (NULL,N'Verneutstyr','verneutstyr'),(NULL,N'Hage','hage'),(NULL,N'Maling','maling'),
 (NULL,N'VVS','vvs'),(NULL,N'Transport','transport');

INSERT INTO categories (parent_id, name, slug)
SELECT p.id, x.name, x.slug FROM (VALUES
 ('verktoy',N'Håndverktøy','handverktoy'),('verktoy',N'Elektroverktøy','elektroverktoy'),
 ('verktoy',N'Måleverktøy','maleverktoy'),('verktoy',N'Verktøykasser','verktoykasser'),
 ('byggevarer',N'Trelast','trelast'),('byggevarer',N'Isolasjon','isolasjon'),
 ('byggevarer',N'Betong','betong'),('byggevarer',N'Festemidler','festemidler'),
 ('elektro',N'Kabel','kabel'),('elektro',N'Belysning','belysning'),
 ('elektro',N'Varmekabel','varmekabel'),('elektro',N'Sikringsskap','sikringsskap'),
 ('verneutstyr',N'Hansker','hansker'),('verneutstyr',N'Hjelmer','hjelmer'),
 ('verneutstyr',N'Vernebriller','vernebriller'),('verneutstyr',N'Arbeidsklær','arbeidsklaer'),
 ('hage',N'Gressklippere','gressklippere'),('hage',N'Hagemøbler','hagemobler'),
 ('hage',N'Terrasse','terrasse'),('hage',N'Vanning','vanning'),
 ('maling',N'Innendørs','maling-inne'),('maling',N'Utendørs','maling-ute'),
 ('maling',N'Beis','beis'),('maling',N'Tilbehør','maling-tilbehor'),
 ('vvs',N'Rør','ror'),('vvs',N'Armatur','armatur'),('vvs',N'Sanitær','sanitar'),('vvs',N'Avløp','avlop'),
 ('transport',N'Stiger','stiger'),('transport',N'Tilhengere','tilhengere'),
 ('transport',N'Stropper','stropper'),('transport',N'Sekketraller','sekketraller')
) x(parent, name, slug) JOIN categories p ON p.slug = x.parent;

DECLARE @minCat INT = (SELECT MIN(id) FROM categories WHERE parent_id IS NOT NULL);
DECLARE @nCat   INT = (SELECT COUNT(*) FROM categories WHERE parent_id IS NOT NULL);

-- 250 companies
INSERT INTO companies (org_number, name, slug, email, phone, address_line1, address_line2,
                       postal_code, city, country, status, commission_rate, created_at)
SELECT
 CAST(910000000 + n.i * 7 AS VARCHAR(9)),
 w1.w + w2.w + N' ' + w3.w,
 LOWER(CONCAT(w1.w, '-', w2.w, '-', n.i)),
 CONCAT('post@', LOWER(w1.w), LOWER(w2.w), n.i, '.example.no'),
 CONCAT('+47', 40000000 + n.i * 137),
 st.name + N' ' + CAST(1 + (n.i * 3) % 90 AS NVARCHAR(4)),
 CASE WHEN n.i % 5 = 0 THEN N'Postboks ' + CAST(100 + n.i % 800 AS NVARCHAR(4)) END,
 c.zip, c.name, c.cc,
 CASE WHEN n.i % 25 = 0 THEN 'suspended' WHEN n.i % 17 = 0 THEN 'pending'
      WHEN n.i % 41 = 0 THEN 'closed' ELSE 'active' END,
 0.05 + (n.i % 8) * 0.01,
 DATEADD(DAY, -(400 + (n.i * 13) % 900), SYSUTCDATETIME())
FROM #n n
JOIN @cop1 w1 ON w1.r = (n.i * 5) % @nc1
JOIN @cop2 w2 ON w2.r = (n.i * 3) % @nc2
JOIN @cop3 w3 ON w3.r = n.i % @nc3
JOIN @city c  ON c.r  = (n.i * 7) % @ncity
JOIN @street st ON st.r = (n.i * 11) % @nstreet
WHERE n.i <= 250;

DECLARE @minCo INT=(SELECT MIN(id) FROM companies), @nCo INT=(SELECT COUNT(*) FROM companies);

-- 1-4 staff logins per company
INSERT INTO company_users (company_id, email, full_name, password_hash, role, is_active, last_login_at, created_at)
SELECT co.id,
 CONCAT(LOWER(f.w), '.', LOWER(l.w), '.', co.id, k.i, '@', LEFT(co.slug, 20), '.example.no'),
 f.w + N' ' + l.w,
 CONCAT('$2a$10$', LEFT(CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', CONCAT('staff', co.id, k.i)), 2), 40)),
 CASE k.i WHEN 1 THEN 'owner' WHEN 2 THEN 'admin' ELSE 'staff' END,
 CASE WHEN (co.id + k.i) % 13 = 0 THEN 0 ELSE 1 END,
 DATEADD(HOUR, -(ABS(CHECKSUM(NEWID())) % 4000), SYSUTCDATETIME()),
 DATEADD(DAY, -(300 + (co.id * 7 + k.i) % 800), SYSUTCDATETIME())
FROM companies co
JOIN #n k ON k.i <= 1 + (co.id % 4)
JOIN @first f ON f.r = (co.id * 3 + k.i) % @nf
JOIN @last  l ON l.r = (co.id * 5 + k.i * 7) % @nl;

-- 3000 buyers
INSERT INTO users (email, first_name, last_name, phone, password_hash, is_active, last_login_at, created_at)
SELECT
 CONCAT(LOWER(f.w), '.', LOWER(l.w), n.i, '@example.', CASE n.i % 4 WHEN 0 THEN 'com' WHEN 1 THEN 'no' WHEN 2 THEN 'se' ELSE 'dk' END),
 f.w, l.w,
 CASE WHEN n.i % 7 <> 0 THEN CONCAT('+47', 90000000 + n.i * 251) END,
 CONCAT('$2a$10$', LEFT(CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', CONCAT('user', n.i)), 2), 40)),
 CASE WHEN n.i % 19 = 0 THEN 0 ELSE 1 END,
 CASE WHEN n.i % 6 <> 0 THEN DATEADD(HOUR, -(ABS(CHECKSUM(NEWID())) % 8000), SYSUTCDATETIME()) END,
 DATEADD(DAY, -(30 + (n.i * 11) % 1000), SYSUTCDATETIME())
FROM #n n
JOIN @first f ON f.r = (n.i * 7) % @nf
JOIN @last  l ON l.r = (n.i * 13) % @nl
WHERE n.i <= 3000;

-- one shipping + one billing address per buyer
INSERT INTO addresses (user_id, kind, line1, line2, postal_code, city, country)
SELECT u.id, CASE k.i WHEN 1 THEN 'shipping' ELSE 'billing' END,
 st.name + N' ' + CAST(1 + (u.id * 3 + k.i) % 120 AS NVARCHAR(4)),
 CASE WHEN (u.id + k.i) % 6 = 0 THEN N'Leilighet H' + CAST(100 + u.id % 400 AS NVARCHAR(4)) END,
 c.zip, c.name, c.cc
FROM users u
JOIN #n k ON k.i <= 2
JOIN @city c ON c.r = (u.id * 5 + k.i) % @ncity
JOIN @street st ON st.r = (u.id * 7 + k.i) % @nstreet;

-- 6000 products
INSERT INTO products (company_id, category_id, sku, name, description, price, currency, stock, status, created_at)
SELECT
 @minCo + (n.i * 17) % @nCo,
 @minCat + (n.i * 11) % @nCat,
 CONCAT('SKU-', RIGHT('000000' + CAST(n.i AS VARCHAR(6)), 6)),
 a.w + N' ' + nn.w,
 CONCAT(N'Kvalitets', nn.w, N' til proff og privat. Modell ', 2018 + n.i % 8, N'. Leveres fra lager.'),
 ROUND(49 + (ABS(CHECKSUM(NEWID())) % 1200) * (1 + n.i % 5) * 0.9, 2),
 CASE WHEN n.i % 11 = 0 THEN 'SEK' WHEN n.i % 23 = 0 THEN 'DKK' ELSE 'NOK' END,
 CASE WHEN n.i % 9 = 0 THEN 0 ELSE ABS(CHECKSUM(NEWID())) % 400 END,
 CASE WHEN n.i % 9 = 0 THEN 'out_of_stock' WHEN n.i % 31 = 0 THEN 'archived'
      WHEN n.i % 37 = 0 THEN 'draft' ELSE 'active' END,
 DATEADD(DAY, -((n.i * 7) % 700), SYSUTCDATETIME())
FROM #n n
JOIN @adj  a  ON a.r  = (n.i * 5) % @na
JOIN @noun nn ON nn.r = (n.i * 3) % @nn
WHERE n.i <= 6000;

DECLARE @minP INT=(SELECT MIN(id) FROM products), @nP INT=(SELECT COUNT(*) FROM products);

INSERT INTO product_images (product_id, url, alt_text, sort_order)
SELECT p.id, CONCAT('https://cdn.example.no/img/', p.sku, '-', k.i, '.jpg'),
       CONCAT(p.name, N' bilde ', k.i), k.i
FROM products p JOIN #n k ON k.i <= 1 + (p.id % 3);

-- 8000 orders
INSERT INTO orders (user_id, placed_at, status, shipping_address_id, billing_address_id, currency)
SELECT u.id,
 DATEADD(MINUTE, -(ABS(CHECKSUM(NEWID())) % 780000), SYSUTCDATETIME()),
 CASE WHEN n.i % 29 = 0 THEN 'cancelled' WHEN n.i % 53 = 0 THEN 'refunded'
      WHEN n.i % 7  = 0 THEN 'pending'   WHEN n.i % 3 = 0 THEN 'shipped'
      WHEN n.i % 2  = 0 THEN 'completed' ELSE 'paid' END,
 sa.id, ba.id, 'NOK'
FROM #n n
JOIN users u ON u.id = (SELECT MIN(id) FROM users) + (n.i * 13) % 3000
CROSS APPLY (SELECT TOP 1 id FROM addresses a WHERE a.user_id = u.id AND a.kind='shipping' ORDER BY a.id) sa
CROSS APPLY (SELECT TOP 1 id FROM addresses a WHERE a.user_id = u.id AND a.kind='billing'  ORDER BY a.id) ba
WHERE n.i <= 8000;

-- 1-4 distinct products per order
INSERT INTO order_items (order_id, product_id, company_id, quantity, unit_price)
SELECT o.id, p.id, p.company_id, 1 + ABS(CHECKSUM(NEWID())) % 3,
       ROUND(p.price * (1 - (o.id % 4) * 0.02), 2)
FROM orders o
JOIN #n k ON k.i <= 1 + (o.id % 4)
JOIN products p ON p.id = @minP + ((o.id * 7919 + k.i * 1013) % @nP);

UPDATE o SET subtotal = t.s, shipping_cost = CASE WHEN t.s > 1500 THEN 0 ELSE 99 END,
             total    = t.s + CASE WHEN t.s > 1500 THEN 0 ELSE 99 END
FROM orders o JOIN (SELECT order_id, SUM(line_total) s FROM order_items GROUP BY order_id) t
  ON t.order_id = o.id;

INSERT INTO payments (order_id, method, status, amount, transaction_ref, paid_at)
SELECT o.id,
 CASE o.id % 4 WHEN 0 THEN 'card' WHEN 1 THEN 'vipps' WHEN 2 THEN 'invoice' ELSE 'klarna' END,
 CASE WHEN o.status = 'refunded' THEN 'refunded' WHEN o.id % 47 = 0 THEN 'failed'
      WHEN o.status = 'paid' THEN 'authorized' ELSE 'captured' END,
 o.total, CONCAT('TXN-', RIGHT('00000000' + CAST(o.id AS VARCHAR(8)), 8)),
 DATEADD(MINUTE, 3 + o.id % 120, o.placed_at)
FROM orders o WHERE o.status NOT IN ('pending','cancelled');

INSERT INTO reviews (product_id, user_id, rating, title, body, created_at)
SELECT product_id, user_id, rating,
 CASE rating WHEN 5 THEN N'Meget bra' WHEN 4 THEN N'Bra kjøp' WHEN 3 THEN N'Helt greit'
             WHEN 2 THEN N'Skuffende' ELSE N'Ikke anbefalt' END,
 CASE rating WHEN 5 THEN N'Fungerer akkurat som beskrevet, rask levering.'
             WHEN 4 THEN N'God kvalitet for prisen, men emballasjen var slitt.'
             WHEN 3 THEN N'Gjør jobben. Ikke noe mer, ikke noe mindre.'
             WHEN 2 THEN N'Kvaliteten står ikke til prisen.'
             ELSE N'Gikk i stykker etter kort tid. Returnert.' END,
 created_at
FROM (
  SELECT DISTINCT oi.product_id, o.user_id,
         1 + ABS(CHECKSUM(oi.product_id, o.user_id)) % 5 AS rating,
         DATEADD(DAY, 5 + ABS(CHECKSUM(oi.product_id, o.user_id)) % 30, MIN(o.placed_at)) AS created_at
  FROM order_items oi JOIN orders o ON o.id = oi.order_id
  WHERE o.status IN ('shipped','completed')
  GROUP BY oi.product_id, o.user_id
) d
WHERE ABS(CHECKSUM(d.product_id * 31 + d.user_id)) % 10 < 4;

INSERT INTO login_events (principal_type, principal_id, occurred_at, ip_address, user_agent, success)
SELECT 'user', u.id,
 DATEADD(MINUTE, -(ABS(CHECKSUM(NEWID())) % 700000), SYSUTCDATETIME()),
 CONCAT('84.', u.id % 255, '.', (u.id * 7) % 255, '.', (u.id * 13) % 255),
 CASE (u.id + k.i) % 3 WHEN 0 THEN N'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/124.0'
                       WHEN 1 THEN N'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4) Safari/605.1'
                       ELSE N'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Firefox/125.0' END,
 CASE WHEN (u.id * k.i) % 23 = 0 THEN 0 ELSE 1 END
FROM users u JOIN #n k ON k.i <= 1 + (u.id % 8)
UNION ALL
SELECT 'staff', cu.id,
 DATEADD(MINUTE, -(ABS(CHECKSUM(NEWID())) % 500000), SYSUTCDATETIME()),
 CONCAT('51.', cu.id % 255, '.', (cu.id * 3) % 255, '.', (cu.id * 17) % 255),
 N'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Edge/124.0',
 CASE WHEN (cu.id * k.i) % 19 = 0 THEN 0 ELSE 1 END
FROM company_users cu JOIN #n k ON k.i <= 1 + (cu.id % 6);

-- 60 staff who are also buyers: one human, two rows, two password hashes, no link
-- between them. Collapsing these into one account is the merge's real work.
UPDATE cu SET email = u.email, full_name = u.first_name + N' ' + u.last_name
FROM company_users cu
JOIN (SELECT id, email, first_name, last_name, ROW_NUMBER() OVER (ORDER BY id) rn FROM users) u
  ON u.rn = cu.id
WHERE cu.id <= 60;

-- Acquired data is never clean. ~4% of their reviews are a star rating and nothing
-- else: the web form let people submit an empty body for years. Our reviews table
-- says a review has words in it, so the migration has to decide what happens to these.
UPDATE reviews SET body = NULL, title = NULL WHERE id % 23 = 0;

DROP TABLE #n;
GO

SELECT t.name, SUM(p.rows) AS rows
FROM sys.tables t JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
GROUP BY t.name ORDER BY t.name;
GO
