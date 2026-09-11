-- OUR platform: Melvis, on MariaDB. Extracted verbatim from
--   apps/melvis/dbSchema.md
-- so the rehearsal targets the real thing, not an invention. Melvis conventions:
--   * int primary keys with a per-table prefix (co_id, us_id, pr_id, or_id)
--   * no foreign keys at all
--   * mi_id is a MASTER id from customer_master_id_lookup, shared across entities
--   * (mi_id, mi_rel_type) where a row can be owned by more than one kind of thing.
--     mi_rel_type is a Constantine const; only Econ uses the pair.
--   * meta* columns on every table; metaregtime/metauptime are unix SECONDS in an int
--
-- The merge: no Oferta id is ever stored in Melvis. Every Melvis key is auto_increment
-- and Melvis mints it. Where a pipeline needs a parent's Melvis id it re-reads the origin
-- for the NATURAL key (org number, email, company+sku, company+placed_at) and looks the
-- Melvis row up by that. Nothing here depends on the acquired system's numbering, which
-- means their ids can be renumbered or reused without corrupting ours.

CREATE DATABASE IF NOT EXISTS melvis
  CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
USE melvis;

CREATE TABLE customer_master_id_lookup
(
mi_id               int(10) auto_increment
primary key,
mi_guid             varchar(255)     default '' not null,
mi_name             varchar(255)                not null,
mi_org_nr           varchar(30)                 null,
mi_co_id            int unsigned     default 0  not null,
mi_ma_id            int(10)          default 0  not null,
mi_an_id            int(10)          default 0  not null,
mi_emg_id           int unsigned     default 0  not null,
mi_meglersiden_id   int unsigned     default 0  not null,
mi_servicefinder_id int(11) unsigned default 0  not null,
mi_3byggetilbud_id  int(11) unsigned default 0  not null,
metaregtime         int(10)          default 0  null,
metareguser         int(10)          default 0  null,
metauptime          int(10)          default 0  null,
metaupuser          int(10)          default 0  null,
metaunit            int(10)          default 0  null
);

CREATE TABLE customer_companies
(
co_id             int(11) unsigned auto_increment
primary key,
mi_id             int                     not null,
co_org_nr         varchar(30)             null,
co_name           varchar(255) default '' not null,
co_status         int(2)       default 0  not null,
co_phone          varchar(255)            null,
co_mobile         varchar(255)            null,
co_email          varchar(255)            null,
co_description    text                    null,
co_ref            varchar(150) default '' not null,
ww_id             text                    null,
co_blacklist      int(3)                  not null,
co_parent         int(10)                 not null,
co_invoice_parent int(10)      default 0  not null,
co_more_emails    varchar(255)            null,
co_website        varchar(255)            null,
co_facebook       varchar(255)            null,
co_meta_content   text                    null,
co_exist_status   int(3)                  not null,
co_elma           int(2)       default 0  not null,
co_flags          int(10)      default 0  not null,
metaregtime       int(10)      default 0  null,
metareguser       int(10)      default 0  null,
metauptime        int(10)      default 0  null,
metaupuser        int(10)      default 0  null,
metaunit          int(10)      default 0  null,
constraint master_id_unit
unique (mi_id, metaunit)
);

CREATE TABLE customer_users
(
us_id         int(11) unsigned auto_increment
primary key,
us_first_name varchar(150) default '' not null,
us_last_name  varchar(150) default '' not null,
us_email      varchar(150)            null,
us_hash       varchar(255) default '' not null,
us_phone      varchar(100)            null,
us_status     int(2)       default 0  not null,
us_birth_date int(15)                 null,
us_score      int(10)                 null,
us_type       int(3)                  not null,
metaregtime   int(10)      default 0  null,
metareguser   int(10)      default 0  null,
metauptime    int(10)      default 0  null,
metaupuser    int(10)      default 0  null,
metaunit      int(10)      default 0  null,
constraint unique_email
unique (us_email)
);

CREATE TABLE econ_product
(
pr_id                  int(10) auto_increment
primary key,
pr_name                varchar(100)                   not null,
pr_description         text                           null,
pr_slug                varchar(100)     default ''    not null,
tp_id                  int(10)                        not null,
pr_renewal             tinyint(1)       default 0     null,
pr_renewal_price       tinyint(2)       default 1     not null,
pr_renewal_price_value double(10, 2)    default 0.00  not null,
pr_price               double(10, 2)    default 0.00  null,
pr_customPrice         int(2)                         not null,
pr_vat                 decimal(5, 2)    default 25.00 not null,
pr_unit                int(10)                        not null,
pr_unit_value          int(10)          default 1     null,
pr_unit_value_name     varchar(100)     default ''    not null,
pr_refresh_frequency   tinyint unsigned default 0     not null,
pr_refresh_interval    int              default 0     not null,
pr_default_length      tinyint(2)       default 12    not null,
pr_status              int(10)                        not null,
pr_public              int(1)           default 0     not null,
pr_public_name         varchar(191)     default ''    not null,
pr_payment_type        int(10)          default 0     not null,
metaregtime            int(10)          default 0     null,
metareguser            int(10)          default 0     null,
metauptime             int(10)          default 0     null,
metaupuser             int(10)          default 0     null,
metaunit               int(10)          default 0     null
);

CREATE TABLE econ_order
(
or_id                int unsigned auto_increment
primary key,
mi_id                int unsigned           not null,
mi_rel_type          int(10)      default 0 not null,
pd_id                int(10)      default 0 not null,
or_type              int(10)                not null,
or_status            int(10)                not null,
or_payment_type      int(3)                 not null,
or_start_date        int(10)                not null,
or_end_date          int(10)                not null,
or_payment_frequency int(3)                 not null,
or_renew             int(3)                 not null,
or_timestamp         int(10)                not null,
or_closed_date       int(10)      default 0 null,
un_id                int unsigned           not null,
or_comment           text                   null,
or_verif_required    int(1)       default 1 not null,
ve_timestamp         int(10)      default 0 not null,
or_reminder_sent     tinyint      default 0 null,
or_new_order         int(10)                not null,
or_transferred_order int(10)      default 0 not null,
or_owner             int unsigned default 0 not null,
or_split             int(10)      default 0 not null,
or_flags             int(10)      default 0 not null,
or_terms_type        int(10)                null,
metaregtime          int(10)      default 0 null,
metareguser          int(10)      default 0 null,
metauptime           int(10)      default 0 null,
metaupuser           int(10)      default 0 null,
metaunit             int(10)      default 0 null
);

CREATE TABLE econ_order_line
(
ol_id                int unsigned auto_increment
primary key,
or_id                int(10)                       not null,
pr_id                int(10)                       not null,
tp_id                int(10)                       not null,
tp_slug              varchar(191)                  not null,
ol_name              varchar(100)                  not null,
ol_description       text                          null,
ol_basic_price       double(10, 2)    default 0.00 not null,
ol_price             double(10, 2)    default 0.00 not null,
ol_discount_amount   double(10, 2)    default 0.00 not null,
ol_discount_percent  double(10, 2)    default 0.00 not null,
ol_discount_type     int(1)           default 1    not null,
ol_vat               double(10, 2)                 not null,
ol_start_date        int(10)                       not null,
ol_end_date          int(10)                       not null,
ol_unit              int(10)                       not null,
ol_unit_value        int(10)          default 1    not null,
ol_unit_value_name   varchar(100)     default ''   not null,
ol_refresh_frequency tinyint unsigned default 0    not null,
ol_refresh_interval  int              default 0    not null,
ol_total_quantity    int              default 0    not null,
ol_json_settings     text                          null,
ol_renew             int(3)                        not null,
ol_renew_order       int unsigned     default 0    not null,
ol_ref               varchar(255)                  null,
dc_id                int unsigned     default 0    not null,
ol_version           tinyint unsigned default 1    not null,
metaregtime          int(10)          default 0    null,
metareguser          int(10)          default 0    null,
metauptime           int(10)          default 0    null,
metaupuser           int(10)          default 0    null,
metaunit             int(10)          default 0    null
);

CREATE TABLE econ_payment_details
(
pd_id                  int(10) auto_increment
primary key,
pd_ma                  int(1)       default 0  not null,
pd_agreement_hash      varchar(191)            not null,
pd_recurrence_token    varchar(255)            null,
pd_payment_token       varchar(255)            null,
pd_exp_date            bigint                  null,
mi_id                  int(10)                 not null,
mi_rel_type            int(10)      default 0  not null,
pd_card_masked         varchar(255)            null,
pd_card_expiry         varchar(255)            null,
pd_card_type           varchar(191)            null,
pd_status              int(10)      default 1  not null,
pd_fingerprint         varchar(191) default '' not null,
pd_cooldown_timestamp  int(10)                 null,
pd_cooldown_multiplier int(10)                 null,
pd_cooldown_reason     varchar(255)            null,
metaregtime            int(10)      default 0  null,
metareguser            int(10)      default 0  null,
metauptime             int(10)      default 0  null,
metaupuser             int(10)      default 0  null,
metaunit               int(10)      default 0  null
);

CREATE TABLE econ_payments
(
pa_id               int unsigned auto_increment
primary key,
or_id               int(10)                    not null,
mi_id               int(10)                    not null,
mi_rel_type         int(10)                    not null,
in_id               int(10)       default 0    not null,
pa_invoice_number   bigint                     not null,
pa_payment_date     int(10)                    not null,
pa_amount           double(10, 2)              not null,
pa_pay_fee          double(10, 2) default 0.00 not null,
pa_payment_provider int(2)                     not null comment 'arvato/payex',
pa_status           tinyint(2)                 not null comment 'payment/credit',
pa_record_number    varchar(50)                null,
metaregtime         int(10)       default 0    null,
metareguser         int(10)       default 0    null,
metauptime          int(10)       default 0    null,
metaupuser          int(10)       default 0    null,
metaunit            int(10)       default 0    null
);

-- Not a Melvis table: reference data generated from Constantine.php by
-- bin/constantine-export.py and loaded by 00-constantine.hpl, so the pipelines can
-- resolve and validate mi_rel_type instead of hard-coding numbers.
CREATE TABLE constantine (
    mi_rel_type INT          NOT NULL PRIMARY KEY,
    const_name  VARCHAR(80)  NOT NULL,
    module      VARCHAR(40)  NULL,
    app_class   VARCHAR(80)  NULL,
    metaunit    INT          NOT NULL DEFAULT 0,
    KEY ix_constantine_module (module)
);

-- Rows whose mi_rel_type does not resolve. No keys, no constraints: a holding pen.
CREATE TABLE _migration_rejected (
    id            BIGINT       AUTO_INCREMENT PRIMARY KEY,
    source_table  VARCHAR(60)  NOT NULL,
    source_id     INT          NOT NULL,
    mi_id         INT          NULL,
    mi_rel_type   INT          NULL,
    const_name    VARCHAR(80)  NULL,
    reason        VARCHAR(80)  NOT NULL,
    metaregtime   INT          NOT NULL DEFAULT 0,
    metaunit      INT          NOT NULL DEFAULT 0
);

-- ---------------------------------------------------------------------------
-- Melvis is NOT empty when an acquisition lands. This seeds what we already have,
-- with deliberate overlap against Oferta: org numbers 910000007..910000546 are the
-- first 80 of their 250 companies, so 01-master-ids has real matches to find and
-- real inserts to make. Emails overlap too, for the user merge.
-- ---------------------------------------------------------------------------
INSERT INTO customer_master_id_lookup (mi_guid, mi_name, mi_org_nr, mi_co_id, metaregtime, metaunit)
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 80)
SELECT CONCAT('melvis-', LPAD(i, 6, '0')),
       CONCAT('Eksisterende Kunde ', i),
       LPAD(910000000 + (i - 1) * 7 + 7, 9, '0'),
       i,
       UNIX_TIMESTAMP() - 86400 * (400 + i),
       1
FROM n;

INSERT INTO customer_companies (mi_id, co_org_nr, co_name, co_status, co_email, co_phone,
                                co_blacklist, co_parent, co_exist_status, metaregtime, metaunit)
SELECT l.mi_id, l.mi_org_nr, l.mi_name, 1,
       CONCAT('post', l.mi_co_id, '@eksisterende.no'), CONCAT('4', LPAD(l.mi_co_id, 7, '0')),
       0, 0, 1, l.metaregtime, 1
FROM customer_master_id_lookup l;

-- Users we already have. The first 120 share an email with an Oferta user, so the
-- user merge has to recognise them instead of creating a duplicate account.
INSERT INTO customer_users (us_first_name, us_last_name, us_email, us_hash, us_phone,
                            us_status, us_type, metaregtime, metaunit)
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 500)
SELECT CONCAT('Eksisterende', i), CONCAT('Bruker', i),
       CONCAT('user', i, '@example.com'),
       MD5(CONCAT('melvis-hash-', i)), CONCAT('9', LPAD(i, 7, '0')),
       1, 1, UNIX_TIMESTAMP() - 86400 * (300 + i % 200), 1
FROM n;

-- 120 of our existing users share an email with an Oferta user. The user merge
-- has to recognise them and attach, not create a second customer_users row for one human.
INSERT INTO customer_users (us_first_name, us_last_name, us_email, us_hash, us_phone,
                            us_status, us_type, metaregtime, metaunit) VALUES
  ('Kjent1', 'Bruker1', 'aisha.berg1100@example.com', MD5('melvis-hash-aisha.berg1100@example.com'), '90000001', 1, 1, UNIX_TIMESTAMP() - 86400 * 201, 1),
  ('Kjent2', 'Bruker2', 'aisha.berg2900@example.com', MD5('melvis-hash-aisha.berg2900@example.com'), '90000002', 1, 1, UNIX_TIMESTAMP() - 86400 * 202, 1),
  ('Kjent3', 'Bruker3', 'aisha.nowak1700@example.com', MD5('melvis-hash-aisha.nowak1700@example.com'), '90000003', 1, 1, UNIX_TIMESTAMP() - 86400 * 203, 1),
  ('Kjent4', 'Bruker4', 'aisha.olsen2300@example.com', MD5('melvis-hash-aisha.olsen2300@example.com'), '90000004', 1, 1, UNIX_TIMESTAMP() - 86400 * 204, 1),
  ('Kjent5', 'Bruker5', 'aisha.olsen500@example.com', MD5('melvis-hash-aisha.olsen500@example.com'), '90000005', 1, 1, UNIX_TIMESTAMP() - 86400 * 205, 1),
  ('Kjent6', 'Bruker6', 'amalie.hansen1350@example.se', MD5('melvis-hash-amalie.hansen1350@example.se'), '90000006', 1, 1, UNIX_TIMESTAMP() - 86400 * 206, 1),
  ('Kjent7', 'Bruker7', 'amalie.pedersen150@example.se', MD5('melvis-hash-amalie.pedersen150@example.se'), '90000007', 1, 1, UNIX_TIMESTAMP() - 86400 * 207, 1),
  ('Kjent8', 'Bruker8', 'amalie.pedersen1950@example.se', MD5('melvis-hash-amalie.pedersen1950@example.se'), '90000008', 1, 1, UNIX_TIMESTAMP() - 86400 * 208, 1),
  ('Kjent9', 'Bruker9', 'amalie.solberg2550@example.se', MD5('melvis-hash-amalie.solberg2550@example.se'), '90000009', 1, 1, UNIX_TIMESTAMP() - 86400 * 209, 1),
  ('Kjent10', 'Bruker10', 'amalie.solberg750@example.se', MD5('melvis-hash-amalie.solberg750@example.se'), '90000010', 1, 1, UNIX_TIMESTAMP() - 86400 * 210, 1),
  ('Kjent11', 'Bruker11', 'anders.dahl1675@example.dk', MD5('melvis-hash-anders.dahl1675@example.dk'), '90000011', 1, 1, UNIX_TIMESTAMP() - 86400 * 211, 1),
  ('Kjent12', 'Bruker12', 'anders.johansen2275@example.dk', MD5('melvis-hash-anders.johansen2275@example.dk'), '90000012', 1, 1, UNIX_TIMESTAMP() - 86400 * 212, 1),
  ('Kjent13', 'Bruker13', 'anders.johansen475@example.dk', MD5('melvis-hash-anders.johansen475@example.dk'), '90000013', 1, 1, UNIX_TIMESTAMP() - 86400 * 213, 1),
  ('Kjent14', 'Bruker14', 'anders.kristiansen1075@example.dk', MD5('melvis-hash-anders.kristiansen1075@example.dk'), '90000014', 1, 1, UNIX_TIMESTAMP() - 86400 * 214, 1),
  ('Kjent15', 'Bruker15', 'anders.kristiansen2875@example.dk', MD5('melvis-hash-anders.kristiansen2875@example.dk'), '90000015', 1, 1, UNIX_TIMESTAMP() - 86400 * 215, 1),
  ('Kjent16', 'Bruker16', 'astrid.andersen100@example.com', MD5('melvis-hash-astrid.andersen100@example.com'), '90000016', 1, 1, UNIX_TIMESTAMP() - 86400 * 216, 1),
  ('Kjent17', 'Bruker17', 'astrid.andersen1900@example.com', MD5('melvis-hash-astrid.andersen1900@example.com'), '90000017', 1, 1, UNIX_TIMESTAMP() - 86400 * 217, 1),
  ('Kjent18', 'Bruker18', 'astrid.moen2500@example.com', MD5('melvis-hash-astrid.moen2500@example.com'), '90000018', 1, 1, UNIX_TIMESTAMP() - 86400 * 218, 1),
  ('Kjent19', 'Bruker19', 'astrid.moen700@example.com', MD5('melvis-hash-astrid.moen700@example.com'), '90000019', 1, 1, UNIX_TIMESTAMP() - 86400 * 219, 1),
  ('Kjent20', 'Bruker20', 'astrid.rossi1300@example.com', MD5('melvis-hash-astrid.rossi1300@example.com'), '90000020', 1, 1, UNIX_TIMESTAMP() - 86400 * 220, 1),
  ('Kjent21', 'Bruker21', 'elena.andersen1450@example.se', MD5('melvis-hash-elena.andersen1450@example.se'), '90000021', 1, 1, UNIX_TIMESTAMP() - 86400 * 221, 1),
  ('Kjent22', 'Bruker22', 'elena.moen2050@example.se', MD5('melvis-hash-elena.moen2050@example.se'), '90000022', 1, 1, UNIX_TIMESTAMP() - 86400 * 222, 1),
  ('Kjent23', 'Bruker23', 'elena.moen250@example.se', MD5('melvis-hash-elena.moen250@example.se'), '90000023', 1, 1, UNIX_TIMESTAMP() - 86400 * 223, 1),
  ('Kjent24', 'Bruker24', 'elena.rossi2650@example.se', MD5('melvis-hash-elena.rossi2650@example.se'), '90000024', 1, 1, UNIX_TIMESTAMP() - 86400 * 224, 1),
  ('Kjent25', 'Bruker25', 'elena.rossi850@example.se', MD5('melvis-hash-elena.rossi850@example.se'), '90000025', 1, 1, UNIX_TIMESTAMP() - 86400 * 225, 1),
  ('Kjent26', 'Bruker26', 'emma.andersen2350@example.se', MD5('melvis-hash-emma.andersen2350@example.se'), '90000026', 1, 1, UNIX_TIMESTAMP() - 86400 * 226, 1),
  ('Kjent27', 'Bruker27', 'emma.andersen550@example.se', MD5('melvis-hash-emma.andersen550@example.se'), '90000027', 1, 1, UNIX_TIMESTAMP() - 86400 * 227, 1),
  ('Kjent28', 'Bruker28', 'emma.moen1150@example.se', MD5('melvis-hash-emma.moen1150@example.se'), '90000028', 1, 1, UNIX_TIMESTAMP() - 86400 * 228, 1),
  ('Kjent29', 'Bruker29', 'emma.moen2950@example.se', MD5('melvis-hash-emma.moen2950@example.se'), '90000029', 1, 1, UNIX_TIMESTAMP() - 86400 * 229, 1),
  ('Kjent30', 'Bruker30', 'emma.rossi1750@example.se', MD5('melvis-hash-emma.rossi1750@example.se'), '90000030', 1, 1, UNIX_TIMESTAMP() - 86400 * 230, 1),
  ('Kjent31', 'Bruker31', 'erik.dahl1225@example.no', MD5('melvis-hash-erik.dahl1225@example.no'), '90000031', 1, 1, UNIX_TIMESTAMP() - 86400 * 231, 1),
  ('Kjent32', 'Bruker32', 'erik.johansen1825@example.no', MD5('melvis-hash-erik.johansen1825@example.no'), '90000032', 1, 1, UNIX_TIMESTAMP() - 86400 * 232, 1),
  ('Kjent33', 'Bruker33', 'erik.johansen25@example.no', MD5('melvis-hash-erik.johansen25@example.no'), '90000033', 1, 1, UNIX_TIMESTAMP() - 86400 * 233, 1),
  ('Kjent34', 'Bruker34', 'erik.kristiansen2425@example.no', MD5('melvis-hash-erik.kristiansen2425@example.no'), '90000034', 1, 1, UNIX_TIMESTAMP() - 86400 * 234, 1),
  ('Kjent35', 'Bruker35', 'erik.kristiansen625@example.no', MD5('melvis-hash-erik.kristiansen625@example.no'), '90000035', 1, 1, UNIX_TIMESTAMP() - 86400 * 235, 1),
  ('Kjent36', 'Bruker36', 'fredrik.garcía1775@example.dk', MD5('melvis-hash-fredrik.garcía1775@example.dk'), '90000036', 1, 1, UNIX_TIMESTAMP() - 86400 * 236, 1),
  ('Kjent37', 'Bruker37', 'fredrik.lie1175@example.dk', MD5('melvis-hash-fredrik.lie1175@example.dk'), '90000037', 1, 1, UNIX_TIMESTAMP() - 86400 * 237, 1),
  ('Kjent38', 'Bruker38', 'fredrik.lie2975@example.dk', MD5('melvis-hash-fredrik.lie2975@example.dk'), '90000038', 1, 1, UNIX_TIMESTAMP() - 86400 * 238, 1),
  ('Kjent39', 'Bruker39', 'fredrik.nilsen2375@example.dk', MD5('melvis-hash-fredrik.nilsen2375@example.dk'), '90000039', 1, 1, UNIX_TIMESTAMP() - 86400 * 239, 1),
  ('Kjent40', 'Bruker40', 'fredrik.nilsen575@example.dk', MD5('melvis-hash-fredrik.nilsen575@example.dk'), '90000040', 1, 1, UNIX_TIMESTAMP() - 86400 * 240, 1),
  ('Kjent41', 'Bruker41', 'håkon.ahmed2175@example.dk', MD5('melvis-hash-håkon.ahmed2175@example.dk'), '90000041', 1, 1, UNIX_TIMESTAMP() - 86400 * 241, 1),
  ('Kjent42', 'Bruker42', 'håkon.ahmed375@example.dk', MD5('melvis-hash-håkon.ahmed375@example.dk'), '90000042', 1, 1, UNIX_TIMESTAMP() - 86400 * 242, 1),
  ('Kjent43', 'Bruker43', 'håkon.haugen1575@example.dk', MD5('melvis-hash-håkon.haugen1575@example.dk'), '90000043', 1, 1, UNIX_TIMESTAMP() - 86400 * 243, 1),
  ('Kjent44', 'Bruker44', 'håkon.larsen2775@example.dk', MD5('melvis-hash-håkon.larsen2775@example.dk'), '90000044', 1, 1, UNIX_TIMESTAMP() - 86400 * 244, 1),
  ('Kjent45', 'Bruker45', 'håkon.larsen975@example.dk', MD5('melvis-hash-håkon.larsen975@example.dk'), '90000045', 1, 1, UNIX_TIMESTAMP() - 86400 * 245, 1),
  ('Kjent46', 'Bruker46', 'ingrid.berg1550@example.se', MD5('melvis-hash-ingrid.berg1550@example.se'), '90000046', 1, 1, UNIX_TIMESTAMP() - 86400 * 246, 1),
  ('Kjent47', 'Bruker47', 'ingrid.nowak2150@example.se', MD5('melvis-hash-ingrid.nowak2150@example.se'), '90000047', 1, 1, UNIX_TIMESTAMP() - 86400 * 247, 1),
  ('Kjent48', 'Bruker48', 'ingrid.nowak350@example.se', MD5('melvis-hash-ingrid.nowak350@example.se'), '90000048', 1, 1, UNIX_TIMESTAMP() - 86400 * 248, 1),
  ('Kjent49', 'Bruker49', 'ingrid.olsen2750@example.se', MD5('melvis-hash-ingrid.olsen2750@example.se'), '90000049', 1, 1, UNIX_TIMESTAMP() - 86400 * 249, 1),
  ('Kjent50', 'Bruker50', 'ingrid.olsen950@example.se', MD5('melvis-hash-ingrid.olsen950@example.se'), '90000050', 1, 1, UNIX_TIMESTAMP() - 86400 * 250, 1),
  ('Kjent51', 'Bruker51', 'jonas.garcía1325@example.no', MD5('melvis-hash-jonas.garcía1325@example.no'), '90000051', 1, 1, UNIX_TIMESTAMP() - 86400 * 251, 1),
  ('Kjent52', 'Bruker52', 'jonas.lie2525@example.no', MD5('melvis-hash-jonas.lie2525@example.no'), '90000052', 1, 1, UNIX_TIMESTAMP() - 86400 * 252, 1),
  ('Kjent53', 'Bruker53', 'jonas.lie725@example.no', MD5('melvis-hash-jonas.lie725@example.no'), '90000053', 1, 1, UNIX_TIMESTAMP() - 86400 * 253, 1),
  ('Kjent54', 'Bruker54', 'jonas.nilsen125@example.no', MD5('melvis-hash-jonas.nilsen125@example.no'), '90000054', 1, 1, UNIX_TIMESTAMP() - 86400 * 254, 1),
  ('Kjent55', 'Bruker55', 'jonas.nilsen1925@example.no', MD5('melvis-hash-jonas.nilsen1925@example.no'), '90000055', 1, 1, UNIX_TIMESTAMP() - 86400 * 255, 1),
  ('Kjent56', 'Bruker56', 'kari.hansen1800@example.com', MD5('melvis-hash-kari.hansen1800@example.com'), '90000056', 1, 1, UNIX_TIMESTAMP() - 86400 * 256, 1),
  ('Kjent57', 'Bruker57', 'kari.pedersen2400@example.com', MD5('melvis-hash-kari.pedersen2400@example.com'), '90000057', 1, 1, UNIX_TIMESTAMP() - 86400 * 257, 1),
  ('Kjent58', 'Bruker58', 'kari.pedersen600@example.com', MD5('melvis-hash-kari.pedersen600@example.com'), '90000058', 1, 1, UNIX_TIMESTAMP() - 86400 * 258, 1),
  ('Kjent59', 'Bruker59', 'kari.solberg1200@example.com', MD5('melvis-hash-kari.solberg1200@example.com'), '90000059', 1, 1, UNIX_TIMESTAMP() - 86400 * 259, 1),
  ('Kjent60', 'Bruker60', 'kari.solberg3000@example.com', MD5('melvis-hash-kari.solberg3000@example.com'), '90000060', 1, 1, UNIX_TIMESTAMP() - 86400 * 260, 1),
  ('Kjent61', 'Bruker61', 'lars.ahmed1725@example.no', MD5('melvis-hash-lars.ahmed1725@example.no'), '90000061', 1, 1, UNIX_TIMESTAMP() - 86400 * 261, 1),
  ('Kjent62', 'Bruker62', 'lars.haugen1125@example.no', MD5('melvis-hash-lars.haugen1125@example.no'), '90000062', 1, 1, UNIX_TIMESTAMP() - 86400 * 262, 1),
  ('Kjent63', 'Bruker63', 'lars.haugen2925@example.no', MD5('melvis-hash-lars.haugen2925@example.no'), '90000063', 1, 1, UNIX_TIMESTAMP() - 86400 * 263, 1),
  ('Kjent64', 'Bruker64', 'lars.larsen2325@example.no', MD5('melvis-hash-lars.larsen2325@example.no'), '90000064', 1, 1, UNIX_TIMESTAMP() - 86400 * 264, 1),
  ('Kjent65', 'Bruker65', 'lars.larsen525@example.no', MD5('melvis-hash-lars.larsen525@example.no'), '90000065', 1, 1, UNIX_TIMESTAMP() - 86400 * 265, 1),
  ('Kjent66', 'Bruker66', 'linnea.andersen1000@example.com', MD5('melvis-hash-linnea.andersen1000@example.com'), '90000066', 1, 1, UNIX_TIMESTAMP() - 86400 * 266, 1),
  ('Kjent67', 'Bruker67', 'linnea.andersen2800@example.com', MD5('melvis-hash-linnea.andersen2800@example.com'), '90000067', 1, 1, UNIX_TIMESTAMP() - 86400 * 267, 1),
  ('Kjent68', 'Bruker68', 'linnea.moen1600@example.com', MD5('melvis-hash-linnea.moen1600@example.com'), '90000068', 1, 1, UNIX_TIMESTAMP() - 86400 * 268, 1),
  ('Kjent69', 'Bruker69', 'linnea.rossi2200@example.com', MD5('melvis-hash-linnea.rossi2200@example.com'), '90000069', 1, 1, UNIX_TIMESTAMP() - 86400 * 269, 1),
  ('Kjent70', 'Bruker70', 'linnea.rossi400@example.com', MD5('melvis-hash-linnea.rossi400@example.com'), '90000070', 1, 1, UNIX_TIMESTAMP() - 86400 * 270, 1),
  ('Kjent71', 'Bruker71', 'magnus.garcía2675@example.dk', MD5('melvis-hash-magnus.garcía2675@example.dk'), '90000071', 1, 1, UNIX_TIMESTAMP() - 86400 * 271, 1),
  ('Kjent72', 'Bruker72', 'magnus.garcía875@example.dk', MD5('melvis-hash-magnus.garcía875@example.dk'), '90000072', 1, 1, UNIX_TIMESTAMP() - 86400 * 272, 1),
  ('Kjent73', 'Bruker73', 'magnus.lie2075@example.dk', MD5('melvis-hash-magnus.lie2075@example.dk'), '90000073', 1, 1, UNIX_TIMESTAMP() - 86400 * 273, 1),
  ('Kjent74', 'Bruker74', 'magnus.lie275@example.dk', MD5('melvis-hash-magnus.lie275@example.dk'), '90000074', 1, 1, UNIX_TIMESTAMP() - 86400 * 274, 1),
  ('Kjent75', 'Bruker75', 'magnus.nilsen1475@example.dk', MD5('melvis-hash-magnus.nilsen1475@example.dk'), '90000075', 1, 1, UNIX_TIMESTAMP() - 86400 * 275, 1),
  ('Kjent76', 'Bruker76', 'maja.hansen2700@example.com', MD5('melvis-hash-maja.hansen2700@example.com'), '90000076', 1, 1, UNIX_TIMESTAMP() - 86400 * 276, 1),
  ('Kjent77', 'Bruker77', 'maja.hansen900@example.com', MD5('melvis-hash-maja.hansen900@example.com'), '90000077', 1, 1, UNIX_TIMESTAMP() - 86400 * 277, 1),
  ('Kjent78', 'Bruker78', 'maja.pedersen1500@example.com', MD5('melvis-hash-maja.pedersen1500@example.com'), '90000078', 1, 1, UNIX_TIMESTAMP() - 86400 * 278, 1),
  ('Kjent79', 'Bruker79', 'maja.solberg2100@example.com', MD5('melvis-hash-maja.solberg2100@example.com'), '90000079', 1, 1, UNIX_TIMESTAMP() - 86400 * 279, 1),
  ('Kjent80', 'Bruker80', 'maja.solberg300@example.com', MD5('melvis-hash-maja.solberg300@example.com'), '90000080', 1, 1, UNIX_TIMESTAMP() - 86400 * 280, 1),
  ('Kjent81', 'Bruker81', 'mateo.garcía2225@example.no', MD5('melvis-hash-mateo.garcía2225@example.no'), '90000081', 1, 1, UNIX_TIMESTAMP() - 86400 * 281, 1),
  ('Kjent82', 'Bruker82', 'mateo.garcía425@example.no', MD5('melvis-hash-mateo.garcía425@example.no'), '90000082', 1, 1, UNIX_TIMESTAMP() - 86400 * 282, 1),
  ('Kjent83', 'Bruker83', 'mateo.lie1625@example.no', MD5('melvis-hash-mateo.lie1625@example.no'), '90000083', 1, 1, UNIX_TIMESTAMP() - 86400 * 283, 1),
  ('Kjent84', 'Bruker84', 'mateo.nilsen1025@example.no', MD5('melvis-hash-mateo.nilsen1025@example.no'), '90000084', 1, 1, UNIX_TIMESTAMP() - 86400 * 284, 1),
  ('Kjent85', 'Bruker85', 'mateo.nilsen2825@example.no', MD5('melvis-hash-mateo.nilsen2825@example.no'), '90000085', 1, 1, UNIX_TIMESTAMP() - 86400 * 285, 1),
  ('Kjent86', 'Bruker86', 'nora.berg200@example.com', MD5('melvis-hash-nora.berg200@example.com'), '90000086', 1, 1, UNIX_TIMESTAMP() - 86400 * 286, 1),
  ('Kjent87', 'Bruker87', 'nora.berg2000@example.com', MD5('melvis-hash-nora.berg2000@example.com'), '90000087', 1, 1, UNIX_TIMESTAMP() - 86400 * 287, 1),
  ('Kjent88', 'Bruker88', 'nora.nowak2600@example.com', MD5('melvis-hash-nora.nowak2600@example.com'), '90000088', 1, 1, UNIX_TIMESTAMP() - 86400 * 288, 1),
  ('Kjent89', 'Bruker89', 'nora.nowak800@example.com', MD5('melvis-hash-nora.nowak800@example.com'), '90000089', 1, 1, UNIX_TIMESTAMP() - 86400 * 289, 1),
  ('Kjent90', 'Bruker90', 'nora.olsen1400@example.com', MD5('melvis-hash-nora.olsen1400@example.com'), '90000090', 1, 1, UNIX_TIMESTAMP() - 86400 * 290, 1),
  ('Kjent91', 'Bruker91', 'ola.dahl2575@example.dk', MD5('melvis-hash-ola.dahl2575@example.dk'), '90000091', 1, 1, UNIX_TIMESTAMP() - 86400 * 291, 1),
  ('Kjent92', 'Bruker92', 'ola.dahl775@example.dk', MD5('melvis-hash-ola.dahl775@example.dk'), '90000092', 1, 1, UNIX_TIMESTAMP() - 86400 * 292, 1),
  ('Kjent93', 'Bruker93', 'ola.johansen1375@example.dk', MD5('melvis-hash-ola.johansen1375@example.dk'), '90000093', 1, 1, UNIX_TIMESTAMP() - 86400 * 293, 1),
  ('Kjent94', 'Bruker94', 'ola.kristiansen175@example.dk', MD5('melvis-hash-ola.kristiansen175@example.dk'), '90000094', 1, 1, UNIX_TIMESTAMP() - 86400 * 294, 1),
  ('Kjent95', 'Bruker95', 'ola.kristiansen1975@example.dk', MD5('melvis-hash-ola.kristiansen1975@example.dk'), '90000095', 1, 1, UNIX_TIMESTAMP() - 86400 * 295, 1),
  ('Kjent96', 'Bruker96', 'piotr.ahmed1275@example.dk', MD5('melvis-hash-piotr.ahmed1275@example.dk'), '90000096', 1, 1, UNIX_TIMESTAMP() - 86400 * 296, 1),
  ('Kjent97', 'Bruker97', 'piotr.haugen2475@example.dk', MD5('melvis-hash-piotr.haugen2475@example.dk'), '90000097', 1, 1, UNIX_TIMESTAMP() - 86400 * 297, 1),
  ('Kjent98', 'Bruker98', 'piotr.haugen675@example.dk', MD5('melvis-hash-piotr.haugen675@example.dk'), '90000098', 1, 1, UNIX_TIMESTAMP() - 86400 * 298, 1),
  ('Kjent99', 'Bruker99', 'piotr.larsen1875@example.dk', MD5('melvis-hash-piotr.larsen1875@example.dk'), '90000099', 1, 1, UNIX_TIMESTAMP() - 86400 * 299, 1),
  ('Kjent100', 'Bruker100', 'piotr.larsen75@example.dk', MD5('melvis-hash-piotr.larsen75@example.dk'), '90000100', 1, 1, UNIX_TIMESTAMP() - 86400 * 300, 1),
  ('Kjent101', 'Bruker101', 'sindre.ahmed2625@example.no', MD5('melvis-hash-sindre.ahmed2625@example.no'), '90000101', 1, 1, UNIX_TIMESTAMP() - 86400 * 301, 1),
  ('Kjent102', 'Bruker102', 'sindre.ahmed825@example.no', MD5('melvis-hash-sindre.ahmed825@example.no'), '90000102', 1, 1, UNIX_TIMESTAMP() - 86400 * 302, 1),
  ('Kjent103', 'Bruker103', 'sindre.haugen2025@example.no', MD5('melvis-hash-sindre.haugen2025@example.no'), '90000103', 1, 1, UNIX_TIMESTAMP() - 86400 * 303, 1),
  ('Kjent104', 'Bruker104', 'sindre.haugen225@example.no', MD5('melvis-hash-sindre.haugen225@example.no'), '90000104', 1, 1, UNIX_TIMESTAMP() - 86400 * 304, 1),
  ('Kjent105', 'Bruker105', 'sindre.larsen1425@example.no', MD5('melvis-hash-sindre.larsen1425@example.no'), '90000105', 1, 1, UNIX_TIMESTAMP() - 86400 * 305, 1),
  ('Kjent106', 'Bruker106', 'sofie.hansen2250@example.se', MD5('melvis-hash-sofie.hansen2250@example.se'), '90000106', 1, 1, UNIX_TIMESTAMP() - 86400 * 306, 1),
  ('Kjent107', 'Bruker107', 'sofie.hansen450@example.se', MD5('melvis-hash-sofie.hansen450@example.se'), '90000107', 1, 1, UNIX_TIMESTAMP() - 86400 * 307, 1),
  ('Kjent108', 'Bruker108', 'sofie.pedersen1050@example.se', MD5('melvis-hash-sofie.pedersen1050@example.se'), '90000108', 1, 1, UNIX_TIMESTAMP() - 86400 * 308, 1),
  ('Kjent109', 'Bruker109', 'sofie.pedersen2850@example.se', MD5('melvis-hash-sofie.pedersen2850@example.se'), '90000109', 1, 1, UNIX_TIMESTAMP() - 86400 * 309, 1),
  ('Kjent110', 'Bruker110', 'sofie.solberg1650@example.se', MD5('melvis-hash-sofie.solberg1650@example.se'), '90000110', 1, 1, UNIX_TIMESTAMP() - 86400 * 310, 1),
  ('Kjent111', 'Bruker111', 'thea.berg2450@example.se', MD5('melvis-hash-thea.berg2450@example.se'), '90000111', 1, 1, UNIX_TIMESTAMP() - 86400 * 311, 1),
  ('Kjent112', 'Bruker112', 'thea.berg650@example.se', MD5('melvis-hash-thea.berg650@example.se'), '90000112', 1, 1, UNIX_TIMESTAMP() - 86400 * 312, 1),
  ('Kjent113', 'Bruker113', 'thea.nowak1250@example.se', MD5('melvis-hash-thea.nowak1250@example.se'), '90000113', 1, 1, UNIX_TIMESTAMP() - 86400 * 313, 1),
  ('Kjent114', 'Bruker114', 'thea.olsen1850@example.se', MD5('melvis-hash-thea.olsen1850@example.se'), '90000114', 1, 1, UNIX_TIMESTAMP() - 86400 * 314, 1),
  ('Kjent115', 'Bruker115', 'thea.olsen50@example.se', MD5('melvis-hash-thea.olsen50@example.se'), '90000115', 1, 1, UNIX_TIMESTAMP() - 86400 * 315, 1),
  ('Kjent116', 'Bruker116', 'yusuf.dahl2125@example.no', MD5('melvis-hash-yusuf.dahl2125@example.no'), '90000116', 1, 1, UNIX_TIMESTAMP() - 86400 * 316, 1),
  ('Kjent117', 'Bruker117', 'yusuf.dahl325@example.no', MD5('melvis-hash-yusuf.dahl325@example.no'), '90000117', 1, 1, UNIX_TIMESTAMP() - 86400 * 317, 1),
  ('Kjent118', 'Bruker118', 'yusuf.johansen2725@example.no', MD5('melvis-hash-yusuf.johansen2725@example.no'), '90000118', 1, 1, UNIX_TIMESTAMP() - 86400 * 318, 1),
  ('Kjent119', 'Bruker119', 'yusuf.johansen925@example.no', MD5('melvis-hash-yusuf.johansen925@example.no'), '90000119', 1, 1, UNIX_TIMESTAMP() - 86400 * 319, 1),
  ('Kjent120', 'Bruker120', 'yusuf.kristiansen1525@example.no', MD5('melvis-hash-yusuf.kristiansen1525@example.no'), '90000120', 1, 1, UNIX_TIMESTAMP() - 86400 * 320, 1);

