"""
SP500 Forecasts and Monitoring — Streamlit in Snowflake app

This app is designed to run inside Snowflake (Snowsight Streamlit).
It connects to your active Snowflake session, reads/writes only Snowflake
objects, and visualizes model predictions, drift metrics, and explainability.

Prereqs (created by notebooks 01–05 / SQL scripts):
- Tables: DAILY_SP500, HOURLY_SP500_SIM, PRICE_FEATURES, PREDICTIONS_SP500_RET3M, DRIFT_PSI_SP500
- Model Registry: XGB_SP500_RET3M with one or more versions
- Optional: FEATURE_SHAP_GLOBAL_TOP persisted by Notebook 03
"""

from __future__ import annotations

import pandas as pd
import numpy as np
import streamlit as st
from typing import List

from snowflake.snowpark.context import get_active_session
from snowflake.snowpark.functions import col


def get_session():
    session = get_active_session()
    session.sql("USE DATABASE SP500_STOCK_DEMO").collect()
    session.sql("USE SCHEMA DATA").collect()
    return session


def list_model_versions(session) -> List[str]:
    try:
        df = session.sql(
            """
            SELECT name, versions
            FROM DATA.SNOWFLAKE_ML_MODELS
            WHERE name = 'XGB_SP500_RET3M'
            """
        ).to_pandas()
        if not df.empty:
            import ast as _ast

            return _ast.literal_eval(df.iloc[0]["VERSIONS"]) or []
    except Exception:
        pass
    return []


def list_tickers(session) -> List[str]:
    try:
        tickers = (
            session.table("SP500_TICKERS").select("TICKER").to_pandas()["TICKER"].tolist()
        )
        if tickers:
            return tickers
    except Exception:
        pass
    # Fallback: distinct from PRICE_FEATURES
    return (
        session.table("PRICE_FEATURES")
        .select("TICKER")
        .distinct()
        .to_pandas()["TICKER"].tolist()
    )


def get_time_bounds(session):
    bounds = session.sql("SELECT MIN(TS) AS MN, MAX(TS) AS MX FROM PRICE_FEATURES").collect()[0]
    mn = pd.to_datetime(bounds["MN"]) if bounds["MN"] is not None else pd.Timestamp.today() - pd.Timedelta(days=90)
    mx = pd.to_datetime(bounds["MX"]) if bounds["MX"] is not None else pd.Timestamp.today()
    return mn, mx


def load_existing_predictions(session, symbol: str, start_ts: pd.Timestamp, end_ts: pd.Timestamp) -> pd.DataFrame:
    sp = (
        session.table("PREDICTIONS_SP500_RET3M")
        .filter((col("TICKER") == symbol) & (col("TS") >= start_ts) & (col("TS") <= end_ts))
        .sort(col("TS"))
    )
    return sp.to_pandas()


def score_on_demand(session, symbol: str, start_ts: pd.Timestamp, end_ts: pd.Timestamp, version: str) -> pd.DataFrame:
    from snowflake.ml.registry import Registry

    reg = Registry(session=session, database_name="SP500_STOCK_DEMO", schema_name="DATA")
    mv = reg.get_model("XGB_SP500_RET3M").version(version)
    feats = (
        session.table("PRICE_FEATURES")
        .filter((col("TICKER") == symbol) & (col("TS") >= start_ts) & (col("TS") <= end_ts))
        .sort(col("TS"))
    )
    preds_sp = mv.run(feats, function_name="PREDICT")
    return preds_sp.to_pandas()


def load_close_series(session, symbol: str, start_ts: pd.Timestamp, end_ts: pd.Timestamp) -> pd.DataFrame:
    return (
        session.table("PRICE_FEATURES")
        .filter((col("TICKER") == symbol) & (col("TS") >= start_ts) & (col("TS") <= end_ts))
        .select("TICKER", "TS", "CLOSE")
        .sort(col("TS"))
        .to_pandas()
    )


def main():
    session = get_session()

    st.set_page_config(page_title="SP500 ML Forecasts", layout="wide")
    st.title("SP500 Forecasts and Monitoring")
    st.caption("Model: XGB_SP500_RET3M — training, inference, drift and explainability")

    with st.sidebar:
        st.header("Controls")
        versions = list_model_versions(session)
        selected_version = st.selectbox("Model version", options=versions if versions else ["V_1"])

        source_mode = st.radio(
            "Prediction source",
            options=["Existing predictions", "On-demand scoring"],
            index=0,
            help="Use persisted predictions or run the selected model on-the-fly for the time range",
        )

        tickers = sorted(list_tickers(session))
        ticker = st.selectbox("Ticker", options=tickers[:500] if tickers else [])

        mn, mx = get_time_bounds(session)
        start_date = st.date_input(
            "Start date", value=(mx - pd.Timedelta(days=30)).date(), min_value=mn.date(), max_value=mx.date()
        )
        end_date = st.date_input("End date", value=mx.date(), min_value=mn.date(), max_value=mx.date())

        run_button = st.button("Update view")

    tab_overview, tab_preds, tab_drift, tab_explain = st.tabs([
        "Overview",
        "Predictions",
        "Drift",
        "Explainability",
    ])

    if run_button or True:
        start_ts = pd.to_datetime(start_date)
        end_ts = pd.to_datetime(end_date) + pd.Timedelta(hours=23, minutes=59)

        try:
            if source_mode == "Existing predictions":
                preds_pd = load_existing_predictions(session, ticker, start_ts, end_ts)
            else:
                preds_pd = score_on_demand(session, ticker, start_ts, end_ts, selected_version)
        except Exception as e:
            preds_pd = pd.DataFrame()
            st.warning(f"Could not load predictions: {e}")

        try:
            feats_pd = load_close_series(session, ticker, start_ts, end_ts)
        except Exception:
            feats_pd = pd.DataFrame(columns=["TICKER", "TS", "CLOSE"])

        merged = preds_pd.merge(feats_pd, on=["TICKER", "TS"], how="left") if not preds_pd.empty else feats_pd

        with tab_overview:
            c1, c2, c3, c4 = st.columns(4)
            num_rows = int(len(merged)) if merged is not None else 0
            avg_pred = float(merged["PREDICTED_RETURN"].mean()) if "PREDICTED_RETURN" in merged else 0.0
            std_pred = float(merged["PREDICTED_RETURN"].std()) if "PREDICTED_RETURN" in merged else 0.0
            c1.metric("Rows", f"{num_rows:,}")
            c2.metric("Avg predicted", f"{avg_pred:.5f}")
            c3.metric("Std predicted", f"{std_pred:.5f}")
            c4.metric("Model version", selected_version)
            st.divider()
            st.subheader(f"{ticker} — Predictions (selected window)")
            if not merged.empty and "PREDICTED_RETURN" in merged:
                st.line_chart(merged[["TS", "PREDICTED_RETURN"]].set_index("TS"))
            else:
                st.info("No predictions available for the selection.")

        with tab_preds:
            st.subheader("Detail table")
            if not merged.empty:
                st.dataframe(merged.sort_values("TS").reset_index(drop=True))
                st.subheader("Close price context")
                if "CLOSE" in merged:
                    st.line_chart(merged[["TS", "CLOSE"]].set_index("TS"))
            else:
                st.info("No data to display for current filters.")

        with tab_drift:
            st.subheader("Recent feature drift (PSI)")
            try:
                psi_pd = session.table("DRIFT_PSI_SP500").to_pandas()
                if not psi_pd.empty:
                    st.dataframe(psi_pd.sort_values("FEATURE").reset_index(drop=True))
                else:
                    st.info("PSI table is empty.")
            except Exception:
                st.info("PSI table not found. Run the inference/monitoring notebook to generate it.")

        with tab_explain:
            st.subheader("Global feature importance (mean |SHAP|)")
            try:
                shap_pd = session.table("FEATURE_SHAP_GLOBAL_TOP").to_pandas()
                if not shap_pd.empty:
                    topn = shap_pd.sort_values("mean_abs_shap", ascending=False).head(15)
                    st.bar_chart(topn.set_index("feature")["mean_abs_shap"])
                    st.dataframe(topn.reset_index(drop=True))
                else:
                    st.info("No SHAP importance table found.")
            except Exception:
                st.info("No SHAP importance table found.")


if __name__ == "__main__":
    main()


