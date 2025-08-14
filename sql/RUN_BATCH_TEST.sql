-- -------------------------------------------------------------------
-- RUN BATCH TEST: Generate hourly intraday for small ticker set
-- -------------------------------------------------------------------
USE WAREHOUSE DEMO_WH_M;
USE DATABASE SP500_STOCK_DEMO;
USE SCHEMA DATA;

CREATE OR REPLACE PROCEDURE SP500_PREP_BATCH_TEST(N_TICKERS INTEGER, YEARS_BACK INTEGER, OUT_TABLE STRING)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python','pandas','numpy')
HANDLER = 'run'
AS
$$
from snowflake.snowpark import Session
from snowflake.snowpark.functions import col, to_timestamp, lit
import pandas as pd
import numpy as np


def run(session: Session, N_TICKERS: int, YEARS_BACK: int, OUT_TABLE: str):
    # Select a small subset of tickers from SP_500_LIST
    syms = [r['SYMBOL'] for r in session.table('SP_500_LIST').select('SYMBOL').limit(N_TICKERS).collect()]

    # Compute cutoff date and filter DAILY_SP500 to selected tickers
    cutoff = session.sql(f"select dateadd('year', -{YEARS_BACK}, current_date()) as D").collect()[0]['D']
    limited = session.table('DAILY_SP500').filter((col('DATE') >= lit(cutoff)) & (col('TICKER').isin(syms)))

    # Pull to pandas for Brownian-bridge-like intraday synthesis
    pdf = limited.to_pandas().sort_values(['TICKER','DATE'])

    rng = np.random.default_rng(42)
    rows = []
    for sym, grp in pdf.groupby('TICKER'):
        for _, r in grp.iterrows():
            o, h, l, c = float(r.OPEN), float(r.HIGH), float(r.LOW), float(r.CLOSE)
            v = float(r.VOLUME)
            date = pd.to_datetime(r.DATE)
            hours = pd.date_range(date + pd.Timedelta(hours=10), date + pd.Timedelta(hours=16), freq='1h', inclusive='left')
            vol_alloc = rng.multinomial(int(v) if v>0 else 0, np.ones(len(hours))/len(hours)) if v>0 else np.zeros(len(hours), dtype=int)
            steps = len(hours)
            noise = rng.normal(0, 1, steps)
            noise = (noise - noise.mean()) / (noise.std() + 1e-6)
            path = o + (c - o) * (np.arange(steps)/(steps-1 if steps>1 else 1)) + noise * max((h-l)/6, 1e-6)
            path = np.clip(path, l, h)
            for i, ts in enumerate(hours):
                base = float(path[i])
                hi = float(min(h, base + abs(base)*0.002))
                lo = float(max(l, base - abs(base)*0.002))
                op = float(base)
                cl = float(base + rng.normal(0, abs(base)*0.0008))
                rows.append([sym, ts, op, hi, lo, cl, int(vol_alloc[i])])

    if rows:
        hourly_pdf = pd.DataFrame(rows, columns=['TICKER','TS','OPEN','HIGH','LOW','CLOSE','VOLUME'])
        hourly_df = session.create_dataframe(hourly_pdf).with_column('TS', to_timestamp(col('TS')))
        hourly_df.write.save_as_table(OUT_TABLE, mode='overwrite')

    return {'out_table': OUT_TABLE, 'rows': len(rows), 'tickers': len(syms), 'years_back': YEARS_BACK}
$$;

-- Execute: generate batch table for first 10 tickers, 1-year window
CALL SP500_PREP_BATCH_TEST(10, 1, 'HOURLY_SP500_SIM_BATCH');

-- Quick validations
SELECT COUNT(*) AS BATCH_ROWS FROM HOURLY_SP500_SIM_BATCH;
SELECT * FROM HOURLY_SP500_SIM_BATCH LIMIT 5;


