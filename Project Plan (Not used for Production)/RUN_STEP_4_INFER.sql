-- -------------------------------------------------------------------
-- RUN STEP 4: Batch inference + simple drift monitoring
-- -------------------------------------------------------------------
USE WAREHOUSE DEMO_WH_M;
USE DATABASE SP500_STOCK_DEMO;
USE SCHEMA DATA;

CREATE OR REPLACE PROCEDURE SP500_INFER_DRIFT()
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python','snowflake-ml-python','pandas','numpy')
HANDLER = 'run'
AS
$$
from snowflake.snowpark import Session
from snowflake.snowpark.functions import col
from snowflake.ml.registry import Registry
import pandas as pd
import numpy as np


def compute_psi_pd(reference: pd.Series, current: pd.Series, bins: int = 10) -> float:
    reference = reference.dropna().astype(float)
    current = current.dropna().astype(float)
    if reference.empty or current.empty:
        return None
    mn = min(reference.min(), current.min())
    mx = max(reference.max(), current.max())
    if not np.isfinite(mn) or not np.isfinite(mx) or mn == mx:
        return None
    edges = np.linspace(mn, mx, bins + 1)
    ref_counts, _ = np.histogram(reference, bins=edges)
    cur_counts, _ = np.histogram(current, bins=edges)
    ref_pct = ref_counts / max(ref_counts.sum(), 1)
    cur_pct = cur_counts / max(cur_counts.sum(), 1)
    ref_pct = np.where(ref_pct == 0, 1e-6, ref_pct)
    cur_pct = np.where(cur_pct == 0, 1e-6, cur_pct)
    psi = ((cur_pct - ref_pct) * np.log(cur_pct / ref_pct)).sum()
    return float(psi)


def run(session: Session):
    # Load latest model
    reg = Registry(session=session, database_name='SP500_STOCK_DEMO', schema_name='DATA')
    model = reg.get_model('XGB_SP500_RET3M').last()

    # Prepare windows
    cutoff = session.sql("select dateadd('day', -5, max(TS)) as c from PRICE_FEATURES").collect()[0]['C']
    recent_df = session.table('PRICE_FEATURES').filter(col('TS') >= cutoff)

    # Run batch predictions and persist
    preds = model.run(recent_df, function_name='PREDICT')
    preds.write.save_as_table('PREDICTIONS_SP500_RET3M', mode='overwrite')

    # Drift: compare previous 35->5 days vs recent 5 days
    ref_cutoff = session.sql("select dateadd('day', -35, max(TS)) as c from PRICE_FEATURES").collect()[0]['C']
    reference_df = session.table('PRICE_FEATURES').filter((col('TS') >= ref_cutoff) & (col('TS') < cutoff))

    features = ['RET_1','SMA_5','SMA_20','VOL_20']
    psi_rows = []
    for f in features:
        ref_pd = reference_df.select(f).to_pandas()[f]
        cur_pd = recent_df.select(f).to_pandas()[f]
        psi = compute_psi_pd(ref_pd, cur_pd, bins=10)
        psi_rows.append({'FEATURE': f, 'PSI': psi})

    psi_df = pd.DataFrame(psi_rows)
    session.create_dataframe(psi_df).write.save_as_table('DRIFT_PSI_SP500', mode='overwrite')

    return {
        'predictions_rows': session.table('PREDICTIONS_SP500_RET3M').count(),
        'psi': psi_rows
    }
$$;

-- Execute inference + drift
CALL SP500_INFER_DRIFT();

-- Quick validations
SELECT COUNT(*) AS PRED_ROWS FROM PREDICTIONS_SP500_RET3M;
SELECT * FROM DRIFT_PSI_SP500 ORDER BY FEATURE;
