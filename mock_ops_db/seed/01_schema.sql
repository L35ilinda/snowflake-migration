-- Mock operational schema. Two tables that mimic what an upstream policy
-- admin system would expose: a master record (policies_master) and an
-- event stream (claims). Deliberately small — Airbyte CDC mechanics are
-- the lesson, not the data volume.

create schema if not exists ops;

create table ops.policies_master (
    policy_id          bigserial primary key,
    policy_number      text        not null unique,
    client_id_number   text        not null,
    product_code       text        not null,
    inception_date     date        not null,
    status             text        not null check (status in ('ACTIVE', 'LAPSED', 'CANCELLED', 'PAID_UP')),
    sum_assured        numeric(18, 2),
    monthly_premium    numeric(18, 2),
    advisor_identifier text,
    -- updated_at + soft-delete flag are what Airbyte CDC uses for incremental
    -- sync once we move past full-refresh in Phase B.
    created_at         timestamptz not null default now(),
    updated_at         timestamptz not null default now(),
    is_deleted         boolean     not null default false
);

create index policies_master_updated_at_idx on ops.policies_master (updated_at);
create index policies_master_status_idx on ops.policies_master (status);

create table ops.claims (
    claim_id        bigserial primary key,
    claim_reference text        not null unique,
    policy_id       bigint      not null references ops.policies_master (policy_id),
    claim_type      text        not null check (claim_type in ('DEATH', 'DISABILITY', 'CHRONIC', 'ACCIDENT', 'SURRENDER')),
    claim_status    text        not null check (claim_status in ('LODGED', 'ASSESSING', 'APPROVED', 'REJECTED', 'PAID')),
    claim_amount    numeric(18, 2),
    paid_amount     numeric(18, 2),
    lodged_at       timestamptz not null default now(),
    decision_at     timestamptz,
    paid_at         timestamptz,
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now(),
    is_deleted      boolean     not null default false
);

create index claims_policy_id_idx on ops.claims (policy_id);
create index claims_updated_at_idx on ops.claims (updated_at);
create index claims_status_idx on ops.claims (claim_status);

-- updated_at trigger so CDC has a real change marker to follow.
create or replace function ops.touch_updated_at() returns trigger as $$
begin
    new.updated_at := now();
    return new;
end;
$$ language plpgsql;

create trigger policies_master_touch_updated_at
    before update on ops.policies_master
    for each row execute function ops.touch_updated_at();

create trigger claims_touch_updated_at
    before update on ops.claims
    for each row execute function ops.touch_updated_at();
