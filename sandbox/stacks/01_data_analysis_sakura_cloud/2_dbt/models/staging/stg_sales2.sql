with sys2 as (
    select
        'sys2'::varchar        as source_system,
        sales_mgmt_no,
        customer_id,
        product_id,
        billing_status as order_status,
        billing_datetime as sale_ym,
        price as amount
    from {{ source('raw', 'raw_sales_sys2') }}
)
select * from sys2
