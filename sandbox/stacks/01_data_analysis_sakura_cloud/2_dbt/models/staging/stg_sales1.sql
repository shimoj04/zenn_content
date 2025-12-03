with sys1 as (
    select
        'sys1'::varchar        as source_system,
        sales_mgmt_no,
        customer_id,
        product_id,
        order_status,
        order_datetime as sale_ym,
        amount
    from {{ source('raw', 'raw_sales_sys1') }}
)
select * from sys1

