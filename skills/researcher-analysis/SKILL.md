---
name: researcher-analysis
description: Data analysis methods — quantitative analysis, qualitative synthesis, trend analysis, visualization
---

# Data Analysis & Research Synthesis

Comprehensive guide to analyzing and synthesizing research data, covering quantitative methods, qualitative analysis, trend identification, comparative frameworks, and visualization techniques for producing actionable insights.

## Table of Contents

1. Quantitative Analysis Fundamentals
2. Qualitative Analysis Methods
3. Data Collection Strategies
4. Data Cleaning & Preprocessing
5. Comparative Analysis
6. Trend Analysis
7. Synthesis Techniques
8. Visualization for Insight
9. Tools & Libraries
10. Best Practices
11. Anti-Patterns
12. Sources & References

---

## 1. Quantitative Analysis Fundamentals

### Statistical Methods Hierarchy

**Descriptive Statistics** — summarize and describe data characteristics:
- Central tendency: mean, median, mode
- Dispersion: standard deviation, variance, range, IQR
- Distribution shape: skewness, kurtosis

**Inferential Statistics** — draw conclusions about populations from samples:
- Parametric tests (assume normal distribution): t-test, ANOVA, linear regression
- Non-parametric tests (no distribution assumption): Mann-Whitney U, Kruskal-Wallis, chi-square
- Selection guidance: choose based on data type (nominal, ordinal, interval, ratio), sample size, and distribution characteristics

**Predictive Analytics**:
- Machine learning regression and classification
- Bayesian methods for probabilistic inference
- Time series forecasting (ARIMA, Prophet, neural architectures)

### Data Validation Framework

```python
import pandas as pd
import numpy as np
from scipy import stats

def validate_dataset(df):
    """Validate a dataset before analysis."""
    report = {}

    # Completeness
    report["missing_pct"] = (df.isnull().sum() / len(df) * 100).round(2).to_dict()

    # Normality test for numeric columns
    report["normality"] = {}
    for col in df.select_dtypes(include=[np.number]).columns:
        stat, p_value = stats.shapiro(df[col].dropna().head(5000))
        report["normality"][col] = {
            "statistic": round(stat, 4),
            "p_value": round(p_value, 4),
            "is_normal": p_value > 0.05
        }

    # Outlier detection (IQR method)
    report["outliers"] = {}
    for col in df.select_dtypes(include=[np.number]).columns:
        Q1, Q3 = df[col].quantile(0.25), df[col].quantile(0.75)
        IQR = Q3 - Q1
        mask = (df[col] < Q1 - 1.5 * IQR) | (df[col] > Q3 + 1.5 * IQR)
        report["outliers"][col] = int(mask.sum())

    # Correlation check
    corr = df.select_dtypes(include=[np.number]).corr()
    high_corr = []
    for i in range(len(corr.columns)):
        for j in range(i + 1, len(corr.columns)):
            if abs(corr.iloc[i, j]) > 0.8:
                high_corr.append({
                    "col_a": corr.columns[i],
                    "col_b": corr.columns[j],
                    "correlation": round(corr.iloc[i, j], 3)
                })
    report["high_correlations"] = high_corr

    return report
```

### Choosing the Right Test

| Data Type | Comparison (2 groups) | Comparison (3+ groups) | Association |
|-----------|----------------------|----------------------|-------------|
| **Continuous, normal** | Independent t-test | One-way ANOVA | Pearson r |
| **Continuous, non-normal** | Mann-Whitney U | Kruskal-Wallis | Spearman rho |
| **Categorical** | Chi-square / Fisher's | Chi-square | Cramér's V |
| **Ordinal** | Mann-Whitney U | Kruskal-Wallis | Spearman rho |
| **Time series** | Paired t-test | Repeated measures ANOVA | Cross-correlation |

---

## 2. Qualitative Analysis Methods

### Thematic Analysis (Braun & Clarke Six-Phase Framework)

1. **Familiarization** — immerse in data, read/re-read transcripts, note initial ideas
2. **Initial coding** — systematic generation of codes across the entire dataset
3. **Theme searching** — collate codes into candidate themes, gather supporting data
4. **Theme reviewing** — check themes against coded extracts and full dataset
5. **Theme defining** — refine specifics, name each theme, define scope
6. **Report production** — final analysis with vivid extracts, relate to research question

### Grounded Theory

- **Open coding** — break data into discrete concepts, label phenomena
- **Axial coding** — relate categories to subcategories, identify relationships
- **Selective coding** — integrate categories around a core category, develop theory
- Continue iterative process until **theoretical saturation** — when new data stops yielding new insights

### Coding Best Practices

- Use member checking (participant validation) to confirm interpretations
- Employ peer debriefing for analytical rigor
- Triangulate across data sources, methods, and researchers
- Maintain an audit trail of coding decisions
- Target inter-coder reliability: Cohen's kappa >= 0.80 for strong agreement

### AI-Assisted Qualitative Analysis

AI tools (LLMs) can enhance efficiency and diversity of coding, but show shortcomings in depth, context, and connections compared with manual coding. Use AI as a complementary tool, not a replacement. Always validate AI-generated codes against manual review.

---

## 3. Data Collection Strategies

### Primary Data Collection

**Surveys & Questionnaires**:
- Use validated instruments where possible (Likert scales, semantic differentials)
- Conduct power analysis to determine minimum sample size (G*Power tool)
- Pilot test before full deployment
- Optimize response rate: incentives, reminders, mobile-friendly design

**Interviews**:
- Structured (standardized questions), semi-structured (guided flexibility), unstructured (exploratory)
- Saturation typically reached at 12-20 participants for homogeneous groups
- Record and transcribe for accurate analysis

### Automated Data Collection

**Web Scraping**:
- Always check for a public API first
- Respect robots.txt and rate limits
- Add pause time between requests to avoid server overload
- Tools: Scrapy (large-scale crawling), BeautifulSoup (lightweight parsing)

**API Integration**:
- Implement exponential backoff for rate limit retries
- Handle pagination properly (follow next-page tokens or offset parameters)
- Validate response schema on receipt

### Ethical Considerations

- GDPR/CCPA compliance for personal data collection
- Informed consent documentation for human subjects
- Data anonymization and secure storage
- Transparent methodology disclosure

---

## 4. Data Cleaning & Preprocessing

### Handling Missing Data

| Strategy | When to Use | Implementation |
|----------|-------------|----------------|
| Listwise deletion | MCAR, <5% missing | `df.dropna()` |
| Mean/median imputation | Numerical, MCAR | `SimpleImputer(strategy='mean')` |
| Mode imputation | Categorical data | `SimpleImputer(strategy='most_frequent')` |
| KNN imputation | MAR, complex patterns | `KNNImputer(n_neighbors=5)` |
| Multiple imputation | Research-grade analysis | `IterativeImputer` |

### Data Cleaning Pipeline

```python
import pandas as pd
import numpy as np
from sklearn.impute import KNNImputer
from sklearn.preprocessing import RobustScaler

def clean_dataframe(df):
    """Comprehensive data cleaning pipeline."""
    report = {"original_shape": df.shape}
    df_clean = df.copy()

    # Remove exact duplicates
    n_dupes = df_clean.duplicated().sum()
    df_clean = df_clean.drop_duplicates()
    report["duplicates_removed"] = int(n_dupes)

    # Standardize column names
    df_clean.columns = (
        df_clean.columns.str.strip()
        .str.lower()
        .str.replace(r"[^\w]", "_", regex=True)
    )

    # Handle missing values
    num_cols = df_clean.select_dtypes(include=[np.number]).columns.tolist()
    cat_cols = df_clean.select_dtypes(include=["object", "category"]).columns.tolist()

    # Numeric: KNN imputation for moderate missingness, median for high
    for col in num_cols:
        pct_missing = df_clean[col].isnull().mean()
        if pct_missing > 0.3:
            df_clean[col] = df_clean[col].fillna(df_clean[col].median())

    if any(df_clean[num_cols].isnull().any()):
        imputer = KNNImputer(n_neighbors=5)
        df_clean[num_cols] = imputer.fit_transform(df_clean[num_cols])

    # Categorical: mode imputation
    for col in cat_cols:
        mode = df_clean[col].mode()
        fill_val = mode.iloc[0] if not mode.empty else "Unknown"
        df_clean[col] = df_clean[col].fillna(fill_val)

    # Flag outliers (IQR method)
    outlier_counts = {}
    for col in num_cols:
        Q1, Q3 = df_clean[col].quantile(0.25), df_clean[col].quantile(0.75)
        IQR = Q3 - Q1
        mask = (df_clean[col] < Q1 - 1.5 * IQR) | (df_clean[col] > Q3 + 1.5 * IQR)
        outlier_counts[col] = int(mask.sum())
    report["outliers_per_column"] = outlier_counts

    report["final_shape"] = df_clean.shape
    report["remaining_nulls"] = int(df_clean.isnull().sum().sum())
    return df_clean, report
```

### Normalization & Feature Scaling

| Method | Use Case | Properties |
|--------|----------|------------|
| Min-Max Scaling | Bounded range needed | Rescales to [0, 1] |
| Standardization (Z-score) | Normally distributed features | Mean=0, std=1 |
| RobustScaler | Data with many outliers | Uses median and IQR |
| Log transformation | Right-skewed distributions | Reduces skew, stabilizes variance |

---

## 5. Comparative Analysis

### Benchmarking Methodology

1. **Identify metrics** — select KPIs relevant to the research question
2. **Establish baselines** — current state performance measurements
3. **Select benchmarks** — industry standards, competitor data, best-in-class examples
4. **Measure gaps** — quantify differences between current and target
5. **Prioritize** — rank gaps by impact and feasibility of closure

### Gap Analysis Framework

```
Current State → Desired State → Gap Identification → Action Plan

Types of gaps:
  - Performance gap: actual vs target KPIs
  - Market gap: unmet customer needs
  - Compliance gap: current vs required standards
  - Capability gap: existing vs needed skills/tools
```

### SWOT Framework for Research

| | Helpful | Harmful |
|---|---------|---------|
| **Internal** | Strengths (strong dataset, validated methods) | Weaknesses (small sample, single data source) |
| **External** | Opportunities (new data sources, emerging methods) | Threats (data quality issues, changing regulations) |

Use SWOT first for strategic overview, then gap analysis for specific improvement plans.

### Weighted Decision Matrix

```python
import pandas as pd

def weighted_comparison(options, criteria, weights, scores):
    """
    Create a weighted decision matrix.

    Args:
        options: list of option names
        criteria: list of criteria names
        weights: dict of criteria -> weight (should sum to 1.0)
        scores: dict of option -> dict of criteria -> score (1-5)
    """
    df = pd.DataFrame(scores).T
    df.columns = criteria

    # Calculate weighted scores
    weighted = pd.DataFrame(index=options)
    for criterion in criteria:
        weighted[criterion] = df[criterion] * weights[criterion]
    weighted["total"] = weighted.sum(axis=1)

    return weighted.sort_values("total", ascending=False)

# Example usage
result = weighted_comparison(
    options=["Tool A", "Tool B", "Tool C"],
    criteria=["performance", "ease_of_use", "cost", "community"],
    weights={"performance": 0.3, "ease_of_use": 0.25, "cost": 0.25, "community": 0.2},
    scores={
        "Tool A": {"performance": 4, "ease_of_use": 5, "cost": 3, "community": 4},
        "Tool B": {"performance": 5, "ease_of_use": 3, "cost": 4, "community": 5},
        "Tool C": {"performance": 3, "ease_of_use": 4, "cost": 5, "community": 3},
    }
)
print(result)
```

---

## 6. Trend Analysis

### Time Series Decomposition

- **Trend component** — long-term direction (upward, downward, flat)
- **Seasonal component** — regular periodic fluctuations
- **Cyclical component** — irregular fluctuations around the trend
- **Residual/noise** — random variation after removing other components

### Forecasting Methods

**Classical Statistical Methods**:
- ARIMA/SARIMA: autoregressive integrated moving average (handles non-stationary data)
- Exponential Smoothing / Holt-Winters: for trend + seasonal data
- Prerequisites: check stationarity (ADF test), autocorrelation (ACF/PACF plots)

**Modern Approaches**:
- Temporal Fusion Transformers (TFT): multi-horizon forecasting with interpretability
- Meta Prophet: additive model for business time series with strong seasonality
- N-BEATS: deep neural architecture for univariate time series

**Pattern Recognition**:
- Anomaly detection: isolation forests, autoencoders, statistical process control
- Change point detection: CUSUM, PELT algorithm
- Time series clustering: DTW (dynamic time warping) distance

### Key Libraries

| Library | Purpose |
|---------|---------|
| `statsmodels` | ARIMA, SARIMAX, exponential smoothing, seasonal decomposition |
| `pmdarima` | Auto-ARIMA model selection |
| `prophet` | Business time series forecasting (Meta) |
| `tsfresh` | Automated feature extraction from time series |
| `darts` | Unified API for multiple forecasting models |

---

## 7. Synthesis Techniques

### Meta-Analysis

- **Purpose**: quantitatively combine results from multiple studies
- **Effect sizes**: Cohen's d, odds ratios, risk ratios, correlation coefficients
- **Models**: fixed-effects (one true effect) vs. random-effects (distribution of effects)
- **Heterogeneity**: I-squared statistic (>75% = substantial heterogeneity)
- **Publication bias**: funnel plots, Egger's test, trim-and-fill method
- **Visual tools**: forest plots (individual + pooled effects), funnel plots (bias detection)

### Systematic Reviews (PRISMA 2020)

- 27-item checklist for transparent reporting
- Flow diagram: identification → screening → eligibility → inclusion
- Protocol registration (PROSPERO) before conducting the review
- Quality assessment tools: AMSTAR (review quality), GRADE (evidence quality)

### Narrative Synthesis

- Used when meta-analysis is not feasible (heterogeneous study designs/outcomes)
- Systematic approach to summarizing and explaining findings from multiple studies
- Tabulation of study characteristics and results
- Prefer effect direction plots over vote counting

### Qualitative Synthesis

- Meta-ethnography: translating concepts across studies
- Thematic synthesis: coding findings from primary studies into descriptive and analytical themes
- Framework synthesis: using a priori framework to organize findings

---

## 8. Visualization for Insight

### Chart Selection Guide

| Data Relationship | Recommended Charts |
|-------------------|-------------------|
| Comparison (categorical) | Bar chart, grouped bar, lollipop |
| Composition | Pie/donut (few categories), stacked bar, treemap |
| Distribution | Histogram, box plot, violin plot, density plot |
| Relationship | Scatter plot, bubble chart, heatmap |
| Trend over time | Line chart, area chart, sparklines |
| Part-to-whole | Waterfall, Marimekko, sunburst |
| Geospatial | Choropleth, bubble map, hex-bin map |

### Multi-Panel Dashboard

```python
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns

def create_eda_dashboard(df, target_col, feature_cols):
    """Generate a 4-panel exploratory data analysis dashboard."""
    sns.set_theme(style="whitegrid", palette="viridis")
    fig, axes = plt.subplots(2, 2, figsize=(14, 10))

    # Panel 1: Target distribution
    sns.histplot(df[target_col], kde=True, ax=axes[0, 0], color="steelblue")
    axes[0, 0].axvline(df[target_col].mean(), color="red", ls="--",
                        label=f"Mean: {df[target_col].mean():.1f}")
    axes[0, 0].set_title(f"Distribution of {target_col}")
    axes[0, 0].legend()

    # Panel 2: Correlation heatmap
    corr = df[feature_cols + [target_col]].corr()
    mask = np.triu(np.ones_like(corr, dtype=bool))
    sns.heatmap(corr, mask=mask, annot=True, fmt=".2f", cmap="RdBu_r",
                center=0, ax=axes[0, 1], square=True)
    axes[0, 1].set_title("Correlation Matrix")

    # Panel 3: Box plots for features
    df_melted = df[feature_cols].melt(var_name="Feature", value_name="Value")
    sns.boxplot(data=df_melted, x="Feature", y="Value", ax=axes[1, 0])
    axes[1, 0].set_title("Feature Distributions")
    axes[1, 0].tick_params(axis="x", rotation=45)

    # Panel 4: Top correlated feature vs target
    top_feat = corr[target_col].drop(target_col).abs().idxmax()
    axes[1, 1].scatter(df[top_feat], df[target_col], alpha=0.5, s=20)
    axes[1, 1].set_xlabel(top_feat)
    axes[1, 1].set_ylabel(target_col)
    axes[1, 1].set_title(f"{target_col} vs {top_feat}")

    plt.suptitle("Exploratory Data Analysis", fontsize=14, fontweight="bold")
    plt.tight_layout()
    return fig
```

### Data Storytelling Principles

- Structure visualizations to guide viewers through logical analytical progressions
- Highlight key insights — do not just display data points
- Use annotations to call out critical findings
- Maintain consistent color schemes across a report
- Use colorblind-friendly palettes (viridis, cividis)
- Limit to 5-7 colors per visualization

---

## 9. Tools & Libraries

### Core Data Stack

| Library | Purpose |
|---------|---------|
| `pandas` | DataFrames, data manipulation, I/O |
| `numpy` | Numerical computation, array operations |
| `scipy` | Statistical tests, optimization |
| `scikit-learn` | ML models, preprocessing, validation |

### Visualization

| Library | Purpose |
|---------|---------|
| `matplotlib` | Static publication-quality plots |
| `seaborn` | Statistical visualization (built on matplotlib) |
| `plotly` | Interactive charts, dashboards (Dash) |
| `altair` | Declarative statistical visualization |

### Specialized Analysis

| Library | Purpose |
|---------|---------|
| `statsmodels` | Statistical models, time series, econometrics |
| `prophet` | Business time series forecasting |
| `nltk` / `spaCy` | Text analysis, NLP for qualitative coding |
| `networkx` | Graph/network analysis |

### Data Collection & Cleaning

| Library | Purpose |
|---------|---------|
| `requests` | HTTP API calls |
| `beautifulsoup4` | HTML/XML parsing |
| `scrapy` | Large-scale web crawling |
| `fuzzywuzzy` | Fuzzy string matching for deduplication |

---

## 10. Best Practices

- **Start with a clear research question** — define hypotheses before touching data
- **Document everything** — methodology, decisions, transformations, version control
- **Use reproducible pipelines** — scripts with seed values, environment files
- **Validate at every stage** — source validation, assumption testing, cross-validation
- **Triangulate** — use multiple data sources, methods, and analysts where possible
- **Invest 60-80% of project time in data understanding and cleaning** — garbage in, garbage out
- **Profile data before analysis** — use `df.info()`, `df.describe()`, missing value heatmaps
- **Handle missing data appropriately** — understand missingness mechanism (MCAR, MAR, MNAR) before imputation
- **Document outlier decisions** — never silently remove data points without justification
- **Choose methods appropriate to data type and distribution** — parametric tests require distributional assumptions
- **Report effect sizes, not just p-values** — statistical significance is not practical significance
- **Use confidence intervals** — they convey both magnitude and precision
- **Visualize before modeling** — EDA is not optional
- **Tell a story with data** — connect findings to decisions, not just metrics
- **Version control data and code** — Git for code, DVC for data versioning

---

## 11. Anti-Patterns

- **Analysis without objectives** — jumping into data without clear goals leads to directionless exploration and false discoveries. Always define the question first
- **Overfitting** — models that match training data too precisely, including noise. They show excellent training results but fail on new data. Use cross-validation and regularization
- **Data leakage** — model learns from information unavailable at prediction time. Use strict temporal splits and pipeline-aware feature engineering
- **Confirmation bias / HARKing** — interpreting data to fit preconceived conclusions or hypothesizing after results are known. Pre-register analysis plans
- **Ignoring data quality** — using raw, uncleaned data. Errors, duplicates, and missing values doom analysis before it starts
- **Survivorship bias** — analyzing only successful cases, ignoring failures or dropouts. Track attrition and analyze non-respondents
- **Cherry-picking metrics** — reporting only favorable results. Pre-define success metrics and report all outcomes
- **Simpson's Paradox blindness** — trends in aggregated data that reverse when split by subgroups. Always stratify and examine subgroups
- **Confusing correlation with causation** — the perennial anti-pattern. Use causal inference frameworks (DAGs, instrumental variables) or explicitly state correlational findings
- **Model drift ignorance** — deployed model performance degrades over time as data distribution changes. Monitor dashboards and set retraining triggers

---

## 12. Sources & References

- https://pmc.ncbi.nlm.nih.gov/articles/PMC11467495/ — PMC comprehensive guidelines for statistical analysis methods (2024)
- https://www.prisma-statement.org/ — PRISMA 2020 statement for systematic review reporting guidelines
- https://scikit-learn.org/stable/modules/preprocessing.html — scikit-learn preprocessing documentation
- https://www.frontiersin.org/journals/research-metrics-and-analytics/articles/10.3389/frma.2025.1669578/full — Frontiers: Qualitative data analysis reflections and procedures (2025)
- https://machinelearningmastery.com/time-series-forecasting-methods-in-python-cheat-sheet/ — Machine Learning Mastery: time series forecasting methods in Python
- https://www.freecodecamp.org/news/common-pitfalls-to-avoid-when-analyzing-and-modeling-data/ — FreeCodeCamp: common pitfalls in data analysis and modeling
- https://pmc.ncbi.nlm.nih.gov/articles/PMC12366998/ — PMC comprehensive guide to systematic review and meta-analysis (2025)
- https://atlan.com/data-analysis-methods/ — Atlan: data analysis methods, techniques, tools & best practices
