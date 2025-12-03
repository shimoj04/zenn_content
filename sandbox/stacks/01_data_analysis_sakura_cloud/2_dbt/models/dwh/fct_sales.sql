select * from {{ ref('stg_sales') }}
union all
select * from {{ ref('stg_sales2') }}
