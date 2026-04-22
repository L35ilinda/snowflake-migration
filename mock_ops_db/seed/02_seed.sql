-- Synthetic seed data. ~10K policies + ~3K claims. Volume is low on purpose
-- — Airbyte sync mechanics, not throughput, are what we're demonstrating.

insert into ops.policies_master (
    policy_number, client_id_number, product_code, inception_date, status,
    sum_assured, monthly_premium, advisor_identifier
)
select
    'POL-' || lpad(g::text, 8, '0')                                            as policy_number,
    lpad((1000000000 + (random() * 8999999999)::bigint)::text, 13, '0')        as client_id_number,
    (array['LIFE_001', 'LIFE_002', 'DIS_001', 'CHR_001', 'ACC_001', 'INV_001'])[1 + (random() * 5)::int] as product_code,
    date '2018-01-01' + (random() * 2900)::int                                 as inception_date,
    (array['ACTIVE', 'ACTIVE', 'ACTIVE', 'ACTIVE', 'LAPSED', 'CANCELLED', 'PAID_UP'])[1 + (random() * 6)::int] as status,
    round((50000 + random() * 4950000)::numeric, 2)                            as sum_assured,
    round((150 + random() * 9850)::numeric, 2)                                 as monthly_premium,
    'ADV-' || lpad((1 + (random() * 199)::int)::text, 4, '0')                  as advisor_identifier
from generate_series(1, 10000) as g;

insert into ops.claims (
    claim_reference, policy_id, claim_type, claim_status,
    claim_amount, paid_amount, lodged_at, decision_at, paid_at
)
select
    'CLM-' || lpad(g::text, 9, '0')                                           as claim_reference,
    1 + (random() * 9999)::int                                                as policy_id,
    (array['DEATH', 'DISABILITY', 'CHRONIC', 'ACCIDENT', 'SURRENDER'])[1 + (random() * 4)::int] as claim_type,
    (array['LODGED', 'ASSESSING', 'APPROVED', 'REJECTED', 'PAID'])[1 + (random() * 4)::int]    as claim_status,
    round((1000 + random() * 999000)::numeric, 2)                             as claim_amount,
    case when random() > 0.4 then round((1000 + random() * 999000)::numeric, 2) end as paid_amount,
    timestamp '2022-01-01' + (random() * 365 * 4 || ' days')::interval        as lodged_at,
    case when random() > 0.3 then timestamp '2022-06-01' + (random() * 365 * 3 || ' days')::interval end as decision_at,
    case when random() > 0.5 then timestamp '2023-01-01' + (random() * 365 * 3 || ' days')::interval end as paid_at
from generate_series(1, 3000) as g;

analyze ops.policies_master;
analyze ops.claims;
