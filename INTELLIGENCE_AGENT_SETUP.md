# Snowflake Intelligence Agent Setup for SP500 ML Stock Demo

This guide walks you through setting up a Snowflake Intelligence agent that can provide ML-driven trading signals.

## Prerequisites

1. **Function is ready:** `GET_TRADING_SIGNAL()` is deployed in `SP500_STOCK_DEMO.DATA`
2. **Required privileges:**
   - CREATE AGENT privilege on `snowflake_intelligence.agents` schema
   - USAGE on SP500_STOCK_DEMO database and DATA schema

## Step-by-Step Agent Creation

### 1. Initial Setup

1. **Sign in to Snowsight**
2. **Navigate to AI & ML > Agents**
3. **Click "Create agent"**

### 2. Basic Configuration

1. **Platform integration:** Select "Create this agent for Snowflake Intelligence"
2. **Agent object name:** `SP500_TRADING_ADVISOR`
3. **Display name:** `SP500 ML Trading Advisor`
4. **Click "Create agent"**

### 3. Agent Configuration

After creating the agent, select it from the list and click **Edit**:

#### Description
```
I am your AI trading advisor for S&P 500 stocks. I can analyze stock performance using semantic views and provide ML-driven trading signals based on our trained XGBoost model.

I have access to:
- Comprehensive stock performance data via Cortex Analyst
- ML model predictions for 3-month forward returns
- Trading signal generation (BUY/SELL/HOLD) with recent data context
- Technical indicators and market analysis
```

#### Instructions Tab

**Response instruction:**
```
You are a professional stock trading advisor with access to ML models and comprehensive market data. 

Guidelines:
1. For stock performance questions: Use Cortex Analyst to query the semantic views
2. For trading signals: Use the ML Trading Signal Generator with appropriate time periods
3. Always provide clear, actionable insights with relevant data points
4. Explain the reasoning behind trading signals and model predictions
5. Add appropriate disclaimers about investment risks
6. Use emojis to make responses engaging but professional
7. When users specify time periods, pass them to the trading signal function
```

#### Sample Questions
Add these sample questions for users:

1. `Show me the performance of AAPL stock in the last 30 days`
2. `Based on the data and our latest ML model, what is the signal (buy/sell) for SNOW based on the last 7 days?`
3. `What is the trading signal for TSLA using the last 14 days of data?`
4. `Give me a trading recommendation for MSFT based on recent performance and our ML model`

### 4. Add Custom Tools

Click on the **Tools** tab and add the following:

#### Add Custom Trading Signal Tool

1. **Click "+ Add" under Custom tools**
2. **Name:** `ML Trading Signal Generator`
3. **Resource type:** Function
4. **Custom tool identifier:** `SP500_STOCK_DEMO.DATA.GET_TRADING_SIGNAL`
5. **Parameters:**
   - **TICKER_SYMBOL** (STRING, Required): "Stock ticker symbol for signal generation (e.g., 'AAPL', 'MSFT', 'SNOW'). Must be a valid S&P 500 ticker symbol that exists in our dataset."
   - **DAYS_BACK** (INTEGER, Optional): "Number of days to analyze for recent performance context (default: 7). Determines the lookback period for trend analysis, volatility calculation, and performance metrics. Common values: 7 (week), 14 (two weeks), 30 (month)."
6. **Warehouse:** `DEMO_WH_M`
7. **Description:**
   ```
   Generates ML-driven trading signals (BUY/SELL/HOLD) using our trained XGBoost model. 
   Analyzes recent performance over specified days and predicts 3-month forward returns. 
   Use this when users ask for trading recommendations, buy/sell advice, or ML predictions 
   with specific time periods.
   ```

### 5. Orchestration Settings

1. **Orchestration model:** Select `Claude 4.0` (or the best available model in your region)
2. **Planning instructions:**
   ```
   When users ask about stock trading signals:

   1. Use the ML Trading Signal Generator tool for all trading recommendations
   2. When users specify time periods (e.g., "last 7 days"), pass the days parameter to the function
   3. Always validate ticker symbols are valid S&P 500 stocks
   4. Provide context about the ML model predictions and recent data analysis
   5. Include appropriate investment disclaimers
   6. Use emojis to make responses engaging but professional
   ```

### 6. Access Control

1. **Click "Add role"**
2. **Select appropriate roles** (e.g., `PUBLIC` for demo purposes, or specific roles for production)
3. **Click "Save"**

## Demo Questions

Once your agent is set up, test these demo questions:

### Question 1: Stock Performance Analysis
```
I am interested in researching company with ticker SNOW, show me the stock performance and volume in the last month?
```

**Expected Response:** The agent will use the Stock Performance Analyzer tool to provide:
- Price performance metrics
- Volume analysis  
- Volatility measurements
- Performance summary

### Question 2: Trading Signal with Time Period
```
Based on the data and our latest ML model, what is the signal (buy/sell) for SNOW based on the last 7 days?
```

**Expected Response:** The agent will use the ML Trading Signal Generator with days_back=7 to provide:
- BUY/SELL/HOLD recommendation
- Predicted 3-month return
- Confidence level
- Recent performance context (7 days)
- Technical indicators and trend analysis
- Model explanation

### Question 3: Combined Analysis
```
Show me AAPL's recent performance and give me a trading recommendation based on the last 14 days
```

**Expected Response:** The agent will use both Cortex Analyst for performance data and the ML Trading Signal Generator for recommendations.

## Troubleshooting

### Common Issues:

1. **"Function does not exist" error:**
   - Ensure `sql/INTELLIGENCE_SETUP.sql` was executed successfully
   - Verify function names match exactly in the tool configuration

2. **"Access denied" error:**
   - Check that the user's role has USAGE privileges on the functions
   - Verify access to SP500_STOCK_DEMO database and DATA schema

3. **"No data found" error:**
   - Ensure the ticker symbol is in the S&P 500 list
   - Check that PRICE_FEATURES table has recent data

4. **Model registry errors:**
   - Verify XGB_SP500_RET3M model exists and has a default version set
   - Ensure Model Registry access privileges

## Advanced Configuration

### Adding More Tools

You can extend the agent by adding more UDFs:

```sql
-- Example: Sector analysis
CREATE OR REPLACE FUNCTION GET_SECTOR_ANALYSIS(sector_name STRING)
RETURNS STRING
-- Implementation details...

-- Example: Portfolio optimization
CREATE OR REPLACE FUNCTION OPTIMIZE_PORTFOLIO(tickers ARRAY)
RETURNS STRING  
-- Implementation details...
```

### Custom Prompts for Specific Use Cases

Modify the response instructions for different scenarios:

- **Conservative Investor Focus:** Emphasize risk metrics and stability
- **Day Trader Focus:** Highlight short-term signals and volatility
- **Research Analyst Focus:** Provide detailed technical analysis

## Security Considerations

For production deployments:

1. **Limit function access** to specific roles
2. **Implement row-level security** on data tables
3. **Add audit logging** for function calls
4. **Rate limit** expensive operations
5. **Validate input parameters** to prevent injection attacks

## Next Steps

1. **Test the agent** with various stock tickers
2. **Refine prompts** based on user feedback  
3. **Add more sophisticated tools** (portfolio analysis, sector comparison)
4. **Integrate with real-time data** feeds
5. **Implement backtesting capabilities** within the agent

This setup creates a powerful AI trading advisor that showcases Snowflake's ML and Intelligence capabilities while providing practical stock analysis functionality.
