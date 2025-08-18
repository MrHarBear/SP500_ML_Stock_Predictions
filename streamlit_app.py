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
    return session


def list_model_versions(session) -> List[str]:
    # Prefer Registry API to avoid permissions/views issues
    try:
        from snowflake.ml.registry import Registry

        reg = Registry(session=session, database_name="SP500_STOCK_DEMO", schema_name="DATA")
        models_df = reg.show_models()
        if not models_df.empty:
            df = models_df.rename(columns=lambda c: str(c).lower())
            import ast as _ast

            row = df.loc[df["name"] == "XGB_SP500_RET3M"]
            if not row.empty:
                val = row.iloc[0]["versions"]
                if isinstance(val, str):
                    return _ast.literal_eval(val) or []
                if isinstance(val, list):
                    return val
    except Exception:
        pass
    # Fallback: read versions column and parse
    try:
        row = (
            session.sql(
                "SELECT versions FROM SP500_STOCK_DEMO.DATA.SNOWFLAKE_ML_MODELS WHERE name = 'XGB_SP500_RET3M'"
            ).collect()
        )
        if row:
            val = row[0]["VERSIONS"]
            import ast as _ast

            if isinstance(val, str):
                return _ast.literal_eval(val) or []
            if isinstance(val, list):
                return val
    except Exception:
        pass
    return []


def get_default_version(session) -> str | None:
    try:
        from snowflake.ml.registry import Registry

        reg = Registry(session=session, database_name="SP500_STOCK_DEMO", schema_name="DATA")
        mv = reg.get_model("XGB_SP500_RET3M").default
        # mv may be a ModelVersion object with name attribute
        name = getattr(mv, "name", None)
        if isinstance(name, str):
            return name
    except Exception:
        pass
    # Fallback: highest version from list
    try:
        vers = list_model_versions(session)
        if vers:
            # sort by numeric suffix
            def key(v):
                try:
                    return int(str(v).split("_")[-1])
                except Exception:
                    return -1
            return sorted(vers, key=key)[-1]
    except Exception:
        pass
    return None


def list_tickers(session) -> List[str]:
    try:
        tickers = (
            session.table("SP500_STOCK_DEMO.DATA.SP500_TICKERS").select("TICKER").to_pandas()["TICKER"].tolist()
        )
        if tickers:
            return tickers
    except Exception:
        pass
    # Fallback: distinct from PRICE_FEATURES
    return (
        session.table("SP500_STOCK_DEMO.DATA.PRICE_FEATURES")
        .select("TICKER")
        .distinct()
        .to_pandas()["TICKER"].tolist()
    )


def get_time_bounds(session):
    bounds = session.sql("SELECT MIN(TS) AS MN, MAX(TS) AS MX FROM SP500_STOCK_DEMO.DATA.PRICE_FEATURES").collect()[0]
    mn = pd.to_datetime(bounds["MN"]) if bounds["MN"] is not None else pd.Timestamp.today() - pd.Timedelta(days=90)
    mx = pd.to_datetime(bounds["MX"]) if bounds["MX"] is not None else pd.Timestamp.today()
    return mn, mx


def load_existing_predictions(session, symbol: str, start_ts: pd.Timestamp, end_ts: pd.Timestamp) -> pd.DataFrame:
    start_dt = pd.Timestamp(start_ts).to_pydatetime()
    end_dt = pd.Timestamp(end_ts).to_pydatetime()
    sp = (
        session.table("SP500_STOCK_DEMO.DATA.PREDICTIONS_SP500_RET3M")
        .filter((col("TICKER") == symbol) & (col("TS") >= start_dt) & (col("TS") <= end_dt))
        .sort(col("TS"))
    )
    return sp.to_pandas()


def score_on_demand(session, symbol: str, start_ts: pd.Timestamp, end_ts: pd.Timestamp, version: str) -> pd.DataFrame:
    from snowflake.ml.registry import Registry

    reg = Registry(session=session, database_name="SP500_STOCK_DEMO", schema_name="DATA")
    mv = reg.get_model("XGB_SP500_RET3M").version(version)
    start_dt = pd.Timestamp(start_ts).to_pydatetime()
    end_dt = pd.Timestamp(end_ts).to_pydatetime()
    feats = (
        session.table("SP500_STOCK_DEMO.DATA.PRICE_FEATURES")
        .filter((col("TICKER") == symbol) & (col("TS") >= start_dt) & (col("TS") <= end_dt))
        .sort(col("TS"))
    )
    preds_sp = mv.run(feats, function_name="PREDICT")
    return preds_sp.to_pandas()


def load_close_series(session, symbol: str, start_ts: pd.Timestamp, end_ts: pd.Timestamp) -> pd.DataFrame:
    start_dt = pd.Timestamp(start_ts).to_pydatetime()
    end_dt = pd.Timestamp(end_ts).to_pydatetime()
    return (
        session.table("SP500_STOCK_DEMO.DATA.PRICE_FEATURES")
        .filter((col("TICKER") == symbol) & (col("TS") >= start_dt) & (col("TS") <= end_dt))
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
        default_ver = get_default_version(session)
        # Put default first if present
        if default_ver and default_ver in versions:
            versions = [default_ver] + [v for v in versions if v != default_ver]
        selected_version = st.selectbox("Model version", options=versions if versions else ([default_ver] if default_ver else ["V_1"]))

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
        except Exception as e:
            feats_pd = pd.DataFrame(columns=["TICKER", "TS", "CLOSE"])
            st.warning(f"Could not load CLOSE series: {e}")

        # Build display frame: base on features to respect the selected window; left-join predictions
        if not feats_pd.empty:
            merged = feats_pd.copy()
            if not preds_pd.empty and "PREDICTED_RETURN" in preds_pd.columns:
                merged = merged.merge(
                    preds_pd[["TICKER", "TS", "PREDICTED_RETURN"]],
                    on=["TICKER", "TS"], how="left"
                )
        else:
            merged = preds_pd

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
                try:
                    import altair as alt
                    ch = (
                        alt.Chart(merged.rename(columns={"TS": "ts"}))
                        .mark_line()
                        .encode(
                            x=alt.X("ts:T", title="Time", axis=alt.Axis(format="%Y-%m-%d %H:%M")),
                            y=alt.Y("PREDICTED_RETURN:Q", title="Predicted return")
                        )
                    )
                    st.altair_chart(ch, use_container_width=True)
                except Exception:
                    st.line_chart(merged[["TS", "PREDICTED_RETURN"]].set_index("TS"))
            else:
                st.info("No predictions available for the selection.")

        with tab_preds:
            st.subheader("Detail table")
            if not merged.empty:
                st.dataframe(merged.sort_values("TS").reset_index(drop=True))
                st.subheader("Close price context")
                if not feats_pd.empty and "CLOSE" in feats_pd.columns and feats_pd["CLOSE"].notna().any():
                    try:
                        import altair as alt
                        ch2 = (
                            alt.Chart(feats_pd.rename(columns={"TS": "ts"}))
                            .mark_line(color="#1f77b4")
                            .encode(
                                x=alt.X("ts:T", title="Time", axis=alt.Axis(format="%Y-%m-%d %H:%M")),
                                y=alt.Y("CLOSE:Q", title="Close price")
                            )
                        )
                        st.altair_chart(ch2, use_container_width=True)
                    except Exception:
                        st.line_chart(feats_pd[["TS", "CLOSE"]].set_index("TS"))
                else:
                    st.info("No data to display for current filters.")
            else:
                st.info("No data to display for current filters.")

        with tab_drift:
            st.subheader("Recent feature drift (PSI)")
            try:
                psi_pd = session.table("SP500_STOCK_DEMO.DATA.DRIFT_PSI_SP500").to_pandas()
                if not psi_pd.empty:
                    st.dataframe(psi_pd.sort_values("FEATURE").reset_index(drop=True))
                else:
                    st.info("PSI table is empty.")
            except Exception:
                st.info("PSI table not found. Run the inference/monitoring notebook to generate it.")

        with tab_explain:
            st.subheader("Global feature importance (mean |SHAP|)")
            try:
                shap_pd = session.table("SP500_STOCK_DEMO.DATA.FEATURE_SHAP_GLOBAL_TOP").to_pandas()
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


