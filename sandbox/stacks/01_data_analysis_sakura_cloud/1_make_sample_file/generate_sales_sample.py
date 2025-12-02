import calendar
from datetime import datetime

import numpy as np
import pandas as pd
import boto3

from product_master import PRODUCT_PRICE, PRODUCT_IDS

# ===== 設定 =====
YEAR = 2025
ROWS_PER_MONTH = 100  # 月ごとのレコード数
TARGET_RANGE_MONTH = 13 

# さくらのオブジェクトストレージ設定
S3_ENDPOINT = "https://s3.isk01.sakurastorage.jp"
S3_BUCKET = "{バケット名}"
AWS_ACCESS_KEY_ID = "{アクセスキー}"
AWS_SECRET_ACCESS_KEY = "{シークレットキー}"


s3 = boto3.client(
    "s3",
    endpoint_url=S3_ENDPOINT,
    aws_access_key_id=AWS_ACCESS_KEY_ID,
    aws_secret_access_key=AWS_SECRET_ACCESS_KEY,
)


def make_dates_for_month(year: int, month: int, n: int) -> pd.Series:
    start = datetime(year, month, 1)
    last_day = calendar.monthrange(year, month)[1]
    end = datetime(year, month, last_day, 23, 59, 59)

    timestamps = pd.to_datetime(
        np.random.randint(int(start.timestamp()), int(end.timestamp()), size=n),
        unit="s",
    )
    return timestamps


def make_sales_sys1_df(year: int, month: int, n: int, start_seq: int):
    """
    System1 用売上データ作成
    sales_mgmt_no: A00001 形式で、start_seq から連番（年内で通し）
    """
    dates = make_dates_for_month(year, month, n)

    seq = np.arange(start_seq, start_seq + n)
    sales_mgmt_no = [f"A{num:05d}" for num in seq]

    product_ids = np.random.choice(PRODUCT_IDS, size=n)
    unit_prices = np.array([PRODUCT_PRICE[p] for p in product_ids])

    amount = unit_prices
    amount_include_tax = (unit_prices * 1.1).astype(int)

    df = pd.DataFrame(
        {
            "sales_mgmt_no": sales_mgmt_no,
            "order_datetime": dates,
            "customer_id": np.random.randint(1000, 1100, size=n),
            "product_id": product_ids,
            "amount": amount,
            "amount_include_tax": amount_include_tax,
            "order_status": np.random.choice(
                ["purchase", "canceled"], size=n, p=[0.9, 0.1]
            ),
            "payment_method": np.random.choice(
                ["credit_card", "bank_transfer", "convenience"], size=n
            ),
            "store_code": np.random.choice(["TOKYO", "OSAKA", "ONLINE"], size=n),
        }
    )

    next_seq = start_seq + n
    return df, next_seq


def make_sales_sys2_df(year: int, month: int, n: int, start_seq: int):
    """
    System2 用売上データ作成
    sales_mgmt_no: B00001 形式で、start_seq から連番（年内で通し）
    """
    dates = make_dates_for_month(year, month, n)

    seq = np.arange(start_seq, start_seq + n)
    sales_mgmt_no = [f"B{num:05d}" for num in seq]

    product_ids = np.random.choice(PRODUCT_IDS, size=n)
    unit_prices = np.array([PRODUCT_PRICE[p] for p in product_ids])

    price = unit_prices
    tax_price = (unit_prices * 0.1).astype(int)

    df = pd.DataFrame(
        {
            "sales_mgmt_no": sales_mgmt_no,
            "billing_datetime": dates,
            "customer_id": np.random.randint(1000, 1100, size=n),
            "product_id": product_ids,
            "price": price,
            "tax_price": tax_price,
            "billing_status": np.random.choice(
                ["billed", "canceled", "adjusted"], size=n, p=[0.85, 0.1, 0.05]
            ),
            "subscription_plan_id": np.random.choice(
                ["PLAN_A", "PLAN_B", "PLAN_C"], size=n
            ),
            "billing_cycle": np.random.choice(
                ["one_time", "monthly", "yearly"], size=n
            ),
        }
    )

    next_seq = start_seq + n
    return df, next_seq


def upload_file_to_s3(local_path: str, key: str):
    """ローカルのファイルをさくらのオブジェクトストレージへアップロード"""
    s3.upload_file(local_path, S3_BUCKET, key)
    print(f"uploaded: s3://{S3_BUCKET}/{key}")


if __name__ == "__main__":
    seq_sys1 = 1  # A00001 からスタート（年内で通し）
    seq_sys2 = 1  # B00001 からスタート（年内で通し）

    for month in range(1, TARGET_RANGE_MONTH):
        # ===== System1 =====
        df1, seq_sys1 = make_sales_sys1_df(YEAR, month, ROWS_PER_MONTH, seq_sys1)
        base_path1 = f"{YEAR}_{month:02d}_sales_sys1.csv"
        local1 = "sample/" + base_path1
        df1.to_csv(local1, index=False)
        print(f"saved local: {local1}")

        s3_key1 = f"raw/sales_sys1/{YEAR}/{month:02d}/{base_path1}"
        upload_file_to_s3(local1, s3_key1)

        # ===== System2 =====
        df2, seq_sys2 = make_sales_sys2_df(YEAR, month, ROWS_PER_MONTH, seq_sys2)
        base_path2 = f"{YEAR}_{month:02d}_sales_sys2.csv"
        local2 = "sample/" + base_path2
        df2.to_csv(local2, index=False)
        print(f"saved local: {local2}")

        s3_key2 = f"raw/sales_sys2/{YEAR}/{month:02d}/{base_path2}"
        upload_file_to_s3(local2, s3_key2)