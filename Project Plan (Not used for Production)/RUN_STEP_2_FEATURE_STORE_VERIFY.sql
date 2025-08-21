-- -------------------------------------------------------------------
-- RUN STEP 2 VERIFY: Enrich features + Feature Store register + retrieve
-- -------------------------------------------------------------------
USE WAREHOUSE DEMO_WH_M;
USE DATABASE SP500_STOCK_DEMO;
USE SCHEMA DATA;

CREATE OR REPLACE PROCEDURE SP500_FEATURE_STORE_ENRICH_V2()
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.12'
PACKAGES = ('snowflake-snowpark-python','snowflake-ml-python','pandas')
HANDLER = 'run'
AS
$$
from snowflake.snowpark import Session
from snowflake.snowpark.functions import col, avg, stddev, lag, when
from snowflake.snowpark import Window
from snowflake.ml.feature_store import FeatureStore, FeatureView, Entity, CreationMode

def run(session: Session):
    # 1) Build enriched PRICE_FEATURES (join hourly + SP_500_LIST for SECTOR)
    win_order = Window.partition_by('TICKER').order_by(col('TS'))
    win_5 = Window.partition_by('TICKER').order_by(col('TS')).rows_between(-4, 0)
    win_20 = Window.partition_by('TICKER').order_by(col('TS')).rows_between(-19, 0)

    hourly = session.table('HOURLY_SP500_SIM')
    spmap = session.table('SP_500_LIST').select(col('SYMBOL').alias('SP_SYMBOL'), col('SECTOR'))

    enriched = (
        hourly.join(spmap, hourly['TICKER'] == spmap['SP_SYMBOL'], how='left')
              .drop('SP_SYMBOL')
    )

    features = (
        enriched
        .with_column('RET_1', (col('CLOSE')/lag(col('CLOSE'), 1).over(win_order) - 1))
        .with_column('SMA_5', avg(col('CLOSE')).over(win_5))
        .with_column('SMA_20', avg(col('CLOSE')).over(win_20))
        .with_column('VOL_20', stddev(col('CLOSE')).over(win_20))
        .with_column('RSI_PROXY', when(col('RET_1')>0, col('RET_1')).otherwise(0))
        .select('TICKER','SECTOR','TS','CLOSE','VOLUME','RET_1','SMA_5','SMA_20','VOL_20','RSI_PROXY')
    )
    features.write.save_as_table('PRICE_FEATURES', mode='overwrite')

    # 2) Register Entity/FeatureView V2 in Feature Store
    fs = FeatureStore(
        session=session,
        database='SP500_STOCK_DEMO',
        name='DATA',
        default_warehouse='DEMO_WH_M',
        creation_mode=CreationMode.CREATE_IF_NOT_EXIST,
    )
    TICKER = Entity(name='TICKER', join_keys=['TICKER'])
    fs.register_entity(TICKER)

    fv = FeatureView(
        name='price_features',
        entities=[TICKER],
        feature_df=session.table('PRICE_FEATURES'),
        desc='Hourly price features with sector enrichment'
    )
    registered_fv = fs.register_feature_view(feature_view=fv, version='V2', overwrite=True)

    # 3) Retrieve onto a spine (subset of SP_500_LIST)
    spine_df = session.table('SP_500_LIST').select(col('SYMBOL').alias('TICKER')).limit(50)
    joined = fs.retrieve_feature_values(spine_df=spine_df, features=[registered_fv])
    # Persist a small sample for validation
    joined.limit(1000).write.save_as_table('PRICE_FEATURES_JOINED_PREVIEW', mode='overwrite')

    # Summary
    return {
        'price_features_rows': session.table('PRICE_FEATURES').count(),
        'joined_preview_rows': session.table('PRICE_FEATURES_JOINED_PREVIEW').count(),
        'feature_view': 'price_features',
        'feature_view_version': 'V2'
    }
$$;

-- Execute and validate
CALL SP500_FEATURE_STORE_ENRICH_V2();
SELECT COUNT(*) AS PRICE_FEATURES_ROWS FROM PRICE_FEATURES;
SELECT COUNT(*) AS JOINED_PREVIEW_ROWS FROM PRICE_FEATURES_JOINED_PREVIEW;
