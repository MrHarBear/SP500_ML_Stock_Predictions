-- Validate Snowflake ML metrics parameter names in this account
USE WAREHOUSE DEMO_WH_M;
USE DATABASE SP500_STOCK_DEMO;
USE SCHEMA DATA;

CREATE OR REPLACE PROCEDURE TEST_METRICS_SIG()
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python','snowflake-ml-python')
HANDLER = 'run'
AS
$$
from snowflake.snowpark import Session
from snowflake.ml.modeling.metrics import mean_squared_error, mean_absolute_percentage_error, r2_score

def run(session: Session):
    df = session.create_dataframe([(1.0, 0.9),(2.0, 2.1),(3.0, 2.9)], schema=['Y','YHAT'])
    # Use singular parameter names per account package version
    mse = mean_squared_error(df=df, y_true_col_name='Y', y_pred_col_name='YHAT')
    mape = mean_absolute_percentage_error(df=df, y_true_col_name='Y', y_pred_col_name='YHAT')
    r2 = r2_score(df=df, y_true_col_name='Y', y_pred_col_name='YHAT')
    rmse = float(mse) ** 0.5
    return {'mse': float(mse), 'rmse': rmse, 'mape': float(mape), 'r2': float(r2)}
$$;

CALL TEST_METRICS_SIG();


