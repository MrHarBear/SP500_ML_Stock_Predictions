-- -------------------------------------------------------------------
-- RUN STEP 1 and 2: Data Prep + Feature Store registration (server-side)
-- -------------------------------------------------------------------
USE WAREHOUSE DEMO_WH_M;
USE DATABASE SP500_STOCK_DEMO;
USE SCHEMA DATA;

-- 0) Seed S and P 500 tickers from mapping table
CREATE OR REPLACE TABLE SP500_TICKERS AS
SELECT DISTINCT SYMBOL AS TICKER
FROM SP_500_LIST
WHERE SYMBOL IS NOT NULL;

-- 1) Stored procedure: subset and simulate hourly data (1-year window)
CREATE OR REPLACE PROCEDURE SP500_PREP()
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python','pandas','numpy')
HANDLER = 'run'
AS
$$
from typing import Any
import pandas as pd
import numpy as np
from snowflake.snowpark import Session
from snowflake.snowpark.functions import col, to_timestamp, lit

def run(session: Session) -> str:
    source_table = 'CORTEX_DEMO.FSI_STOCKS_INSIGHT.DAILY_STOCK_PRICE'

    # Subset to tickers (S and P 500 universe from mapping table)
    daily = session.table(source_table)
    tickers = session.table('SP500_TICKERS')
    joined = daily.join(tickers, on=(daily['TICKER'] == tickers['TICKER']))
    subset = joined.select(
        daily['TICKER'].alias('TICKER'),
        daily['DATE'].alias('DATE'),
        daily['OPEN'],
        daily['HIGH'],
        daily['LOW'],
        daily['CLOSE'],
        daily['VOLUME']
    )
    subset.write.save_as_table('DAILY_SP500', mode='overwrite')

    # Compute cutoff date (365 days back) via SQL and filter
    cutoff = session.sql("select dateadd('day', -365, current_date()) as D").collect()[0]['D']
    limited = session.table('DAILY_SP500').filter(col('DATE') >= lit(cutoff))

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
                rows.append([sym, ts.to_pydatetime(), op, hi, lo, cl, int(vol_alloc[i])])

    hourly_pdf = pd.DataFrame(rows, columns=['TICKER','TS','OPEN','HIGH','LOW','CLOSE','VOLUME'])
    hourly_df = session.create_dataframe(hourly_pdf)
    hourly_df = hourly_df.with_column('TS', to_timestamp(col('TS')))
    hourly_df.write.save_as_table('HOURLY_SP500_SIM', mode='overwrite')
    session.sql("CREATE OR REPLACE VIEW HOURLY_SP500_SIM_VIEW AS SELECT TICKER, TS, OPEN, HIGH, LOW, CLOSE, VOLUME FROM HOURLY_SP500_SIM").collect()
    return 'Created DAILY_SP500, HOURLY_SP500_SIM, HOURLY_SP500_SIM_VIEW'
$$;

-- 2) Stored procedure: compute features and register Feature Store view
CREATE OR REPLACE PROCEDURE SP500_FEATURES_FS()
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python','snowflake-ml-python')
HANDLER = 'run'
AS
$$
from snowflake.snowpark import Session
from snowflake.snowpark.functions import col, avg, stddev, lag, when
from snowflake.snowpark import Window
from snowflake.ml.feature_store import FeatureStore, FeatureView, Entity, CreationMode

def run(session: Session) -> str:
    win_order = Window.partition_by('TICKER').order_by(col('TS'))
    win_5 = Window.partition_by('TICKER').order_by(col('TS')).rows_between(-4, 0)
    win_20 = Window.partition_by('TICKER').order_by(col('TS')).rows_between(-19, 0)

    hourly = session.table('HOURLY_SP500_SIM')
    features = (
        hourly
        .with_column('RET_1', (col('CLOSE')/lag(col('CLOSE'), 1).over(win_order) - 1))
        .with_column('SMA_5', avg(col('CLOSE')).over(win_5))
        .with_column('SMA_20', avg(col('CLOSE')).over(win_20))
        .with_column('VOL_20', stddev(col('CLOSE')).over(win_20))
        .with_column('RSI_PROXY', when(col('RET_1')>0, col('RET_1')).otherwise(0))
        .select('TICKER','TS','CLOSE','VOLUME','RET_1','SMA_5','SMA_20','VOL_20','RSI_PROXY')
    )
    features.write.save_as_table('PRICE_FEATURES', mode='overwrite')

    fs = FeatureStore(
        session=session,
        database='SP500_STOCK_DEMO',
        name='DATA',
        default_warehouse='DEMO_WH_M',
        creation_mode=CreationMode.CREATE_IF_NOT_EXIST,
    )
    ticker = Entity(name='TICKER', join_keys=['TICKER'])
    fs.register_entity(ticker)
    fv = FeatureView(
        name='price_features',
        entities=[ticker],
        feature_df=session.table('PRICE_FEATURES'),
        desc='Hourly price features (SMA, VOL, RSI proxy, returns)'
    )
    fs.register_feature_view(feature_view=fv, version='V1', overwrite=True)
    return 'Created PRICE_FEATURES and registered FeatureView price_features V1'
$$;

-- Run procedures
CALL SP500_PREP();
CALL SP500_FEATURES_FS();

-- Validation (optional)
SELECT COUNT(DISTINCT TICKER) AS TICKERS FROM HOURLY_SP500_SIM;
SELECT COUNT(*) AS DAILY_ROWS FROM DAILY_SP500;
SELECT COUNT(*) AS HOURLY_ROWS FROM HOURLY_SP500_SIM;
SELECT COUNT(*) AS FEATURE_ROWS FROM PRICE_FEATURES;
