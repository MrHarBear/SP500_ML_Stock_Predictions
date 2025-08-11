-- -------------------------------------------------------------------
-- RUN STEP 3: Dataset generation + model training + registry
-- -------------------------------------------------------------------
USE WAREHOUSE DEMO_WH_M;
USE DATABASE SP500_STOCK_DEMO;
USE SCHEMA DATA;

-- Stored procedure to generate target, train model, and register
CREATE OR REPLACE PROCEDURE SP500_TRAIN_REGISTER()
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python','snowflake-ml-python','pandas')
HANDLER = 'run'
AS
$$
from snowflake.snowpark import Session
from snowflake.snowpark.functions import col, lead, avg, pow as sp_pow, sqrt, abs as sp_abs
from snowflake.snowpark import Window
from snowflake.ml.modeling.pipeline import Pipeline
from snowflake.ml.modeling.xgboost import XGBRegressor
from snowflake.ml.registry import Registry
import pandas as pd

def compute_regression_metrics(df, label_col: str, pred_col: str) -> dict:
    # RMSE
    rmse_df = df.select(sqrt(avg(sp_pow(col(label_col) - col(pred_col), 2))).alias('rmse'))
    rmse = rmse_df.collect()[0]['RMSE']
    # MAPE (guard divide-by-zero)
    mape_df = df.select(avg(sp_abs((col(label_col) - col(pred_col)) / (col(label_col) + 1e-9))).alias('mape'))
    mape = mape_df.collect()[0]['MAPE']
    # R^2 = 1 - SSE/SST
    mean_y = df.select(avg(col(label_col)).alias('mean_y')).collect()[0]['MEAN_Y']
    sse = df.select(avg(sp_pow(col(label_col) - col(pred_col), 2)).alias('mse')).collect()[0]['MSE']
    sst = df.select(avg(sp_pow(col(label_col) - mean_y, 2)).alias('var')).collect()[0]['VAR']
    r2 = 1.0 - (sse / sst if sst and sst != 0 else 0.0)
    return {'r2': r2, 'rmse': rmse, 'mape': mape}


def run(session: Session):
    # 1) Build supervised dataset from hourly features
    hourly = session.table('PRICE_FEATURES')
    # Approx 63 trading days * 6 hours/day = ~378 hours ahead
    horizon_hours = 378
    win_order = Window.partition_by('TICKER').order_by(col('TS'))
    ds = (
        hourly
        .with_column('FUT_CLOSE', lead(col('CLOSE'), horizon_hours).over(win_order))
        .with_column('TARGET_PCT_3M', (col('FUT_CLOSE')/col('CLOSE') - 1))
        .drop('FUT_CLOSE')
    )
    ds = ds.filter(col('TARGET_PCT_3M').is_not_null())

    # 2) Time-based split: last ~30 days as test
    cutoff = session.sql("select dateadd('day', -30, max(TS)) as c from PRICE_FEATURES").collect()[0]['C']
    train_df = ds.filter(col('TS') < cutoff)
    test_df = ds.filter(col('TS') >= cutoff)

    # 3) Define features and label
    feature_cols = ['RET_1','SMA_5','SMA_20','VOL_20','RSI_PROXY','VOLUME','CLOSE']
    label_col = 'TARGET_PCT_3M'
    output_col = 'PREDICTED_RETURN'

    # 4) Model pipeline with a fixed XGBRegressor
    xgb = XGBRegressor(
        n_estimators=200,
        max_depth=6,
        learning_rate=0.05,
        subsample=0.8,
        colsample_bytree=0.8,
        input_cols=feature_cols,
        label_cols=[label_col],
        output_cols=[output_col],
        random_state=42,
    )

    pipe = Pipeline(steps=[('xgb', xgb)])
    fitted = pipe.fit(train_df)

    # 5) Evaluate metrics (Snowpark expressions)
    train_pred = fitted.predict(train_df).select(label_col, output_col)
    test_pred = fitted.predict(test_df).select(label_col, output_col)

    train_metrics = compute_regression_metrics(train_pred, label_col, output_col)
    test_metrics = compute_regression_metrics(test_pred, label_col, output_col)

    metrics = {
        'train_r2': train_metrics['r2'],
        'test_r2': test_metrics['r2'],
        'train_rmse': train_metrics['rmse'],
        'test_rmse': test_metrics['rmse'],
        'train_mape': train_metrics['mape'],
        'test_mape': test_metrics['mape'],
    }

    # 6) Register model in Model Registry
    reg = Registry(session=session, database_name='SP500_STOCK_DEMO', schema_name='DATA')
    model_name = 'XGB_SP500_RET3M'
    def next_ver():
        models = reg.show_models()
        if models.empty or model_name not in models['name'].to_list():
            return 'V_1'
        import ast, builtins
        max_v = builtins.max([int(v.split('_')[-1]) for v in ast.literal_eval(models.loc[models['name']==model_name,'versions'].values[0])])
        return f'V_{max_v+1}'

    version = next_ver()
    mv = reg.log_model(
        fitted,
        model_name=model_name,
        version_name=version,
        conda_dependencies=['snowflake-ml-python'],
        comment='XGBRegressor predicting 3-month forward return from hourly features',
        metrics=metrics,
        options={'relax_version': False}
    )
    m = reg.get_model(model_name)
    m.default = version

    return {'model_name': model_name, 'version': version, **metrics}
$$;

-- Run training
CALL SP500_TRAIN_REGISTER();
