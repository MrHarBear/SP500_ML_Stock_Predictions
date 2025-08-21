-- Autodetect supported parameter names for Snowflake ML metrics in this account
USE WAREHOUSE DEMO_WH_M;
USE DATABASE SP500_STOCK_DEMO;
USE SCHEMA DATA;

CREATE OR REPLACE PROCEDURE TEST_METRICS_AUTODETECT()
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python','snowflake-ml-python')
HANDLER = 'run'
AS
$$
from snowflake.snowpark import Session
from snowflake.ml.modeling.metrics import mean_squared_error, mean_absolute_percentage_error, r2_score

def try_metrics(df):
    # Try positional first
    try:
        mse = mean_squared_error(df, 'Y', 'YHAT')
        mape = mean_absolute_percentage_error(df, 'Y', 'YHAT')
        r2 = r2_score(df, 'Y', 'YHAT')
        return {'style': 'positional', 'mse': float(mse), 'mape': float(mape), 'r2': float(r2)}
    except TypeError:
        pass

    # Singular names
    try:
        mse = mean_squared_error(df=df, y_true_col_name='Y', y_pred_col_name='YHAT')
        mape = mean_absolute_percentage_error(df=df, y_true_col_name='Y', y_pred_col_name='YHAT')
        r2 = r2_score(df=df, y_true_col_name='Y', y_pred_col_name='YHAT')
        return {'style': 'singular', 'mse': float(mse), 'mape': float(mape), 'r2': float(r2)}
    except TypeError:
        pass

    # Plural names
    try:
        mse = mean_squared_error(df=df, y_true_col_names=['Y'], y_pred_col_names=['YHAT'])
        mape = mean_absolute_percentage_error(df=df, y_true_col_names=['Y'], y_pred_col_names=['YHAT'])
        r2 = r2_score(df=df, y_true_col_names=['Y'], y_pred_col_names=['YHAT'])
        return {'style': 'plural', 'mse': float(mse), 'mape': float(mape), 'r2': float(r2)}
    except TypeError:
        pass

    # Fallback: not supported
    return {'style': 'unsupported'}

def run(session: Session):
    df = session.create_dataframe([(1.0, 0.9),(2.0, 2.1),(3.0, 2.9)], schema=['Y','YHAT'])
    res = try_metrics(df)
    if res.get('style') != 'unsupported':
        res['rmse'] = res['mse'] ** 0.5
    return res
$$;

CALL TEST_METRICS_AUTODETECT();


