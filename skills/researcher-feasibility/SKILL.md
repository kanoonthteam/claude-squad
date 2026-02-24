---
name: researcher-feasibility
description: >
  Comprehensive feasibility study framework for software and technology projects.
  Covers technical, economic, market, operational, and scheduling feasibility
  using the TELOS methodology. Includes cost-benefit analysis, risk assessment,
  decision matrices, stakeholder analysis, proof of concept design, and
  evidence-based go/no-go recommendation frameworks.
---

# Feasibility Study Framework for Software & Technology Projects

## 1. Overview

A feasibility study determines whether a proposed software or technology project
is viable before significant resources are committed. The study should be
conducted early in the project lifecycle -- ideally when less than 10% of the
total budget has been committed -- and should be time-boxed to 2-6 weeks
depending on project complexity.

The study answers one fundamental question: **Should we proceed?**

The output is not a binary yes/no but a graded recommendation:

| Recommendation    | Meaning                                                        |
|-------------------|----------------------------------------------------------------|
| GO                | Proceed with full commitment                                   |
| CONDITIONAL GO    | Proceed with specific conditions, mitigations, or phase gates  |
| NO-GO             | Do not proceed; redirect resources                             |
| DEFER             | Revisit when conditions change (market, technology, resources)  |

---

## 2. TELOS Feasibility Framework

TELOS is the primary multi-dimensional framework for structuring a feasibility
study. Each dimension addresses a distinct category of viability:

| Dimension     | Key Question                                                     |
|---------------|------------------------------------------------------------------|
| **T**echnical   | Can we build it with available or acquirable technology?         |
| **E**conomic    | Does the financial case justify the investment?                  |
| **L**egal       | Are there regulatory, compliance, or IP constraints?             |
| **O**perational | Can the organization absorb and sustain it?                      |
| **S**cheduling  | Can it be delivered within the required timeframe?               |

Each dimension is scored independently (typically 1-5) and then combined into a
weighted feasibility score. The weights depend on the project context -- a
healthcare project will weight Legal higher; a startup MVP will weight Scheduling
and Economic higher.

### When to Use TELOS

- New product or platform development
- Major technology migration or modernization
- Build vs. buy vs. partner decisions
- Entering a new market or domain
- Adopting a fundamentally new technology stack

### When TELOS May Be Overkill

- Incremental feature work on an established platform
- Bug fixes or performance tuning
- Well-understood integrations with proven technology

---

## 3. Technical Feasibility Assessment

Technical feasibility evaluates whether the proposed solution can be built,
integrated, scaled, and maintained with acceptable technical risk.

### 3.1 Stack Viability

Assess each technology component against these criteria:

- **Maturity**: Production-proven vs. bleeding-edge. Check GitHub stars, npm
  downloads, Stack Overflow activity, and release cadence.
- **Community & Ecosystem**: Size of contributor base, availability of libraries,
  plugins, and tooling.
- **Vendor Lock-in Risk**: Portability of data and workloads. Evaluate exit costs.
- **Talent Availability**: Can you hire or train engineers for this stack?
- **Long-term Support**: Is the technology backed by a sustainable organization?
  Check for LTS releases and deprecation policies.

### 3.2 Integration Complexity

Map every external system the solution must integrate with. For each integration:

- API availability and quality (REST, GraphQL, gRPC, legacy SOAP)
- Authentication and authorization mechanisms
- Data format compatibility and transformation requirements
- Rate limits and throughput constraints
- SLA and uptime guarantees of the external system
- Fallback and retry strategies

### 3.3 Scalability Analysis

Define expected load profiles across three horizons:

| Horizon       | Timeframe    | Expected Load              |
|---------------|-------------|----------------------------|
| Launch        | 0-3 months  | Baseline concurrent users   |
| Growth        | 3-12 months | 3-5x baseline              |
| Scale         | 1-3 years   | 10-50x baseline            |

Evaluate whether the proposed architecture can meet each horizon without
fundamental redesign.

### 3.4 Security Posture

- Data classification (PII, PHI, financial, public)
- Encryption requirements (at rest, in transit, end-to-end)
- Authentication and authorization model (OAuth 2.0, SAML, RBAC, ABAC)
- Compliance frameworks (SOC 2, HIPAA, GDPR, PCI-DSS)
- Vulnerability management and penetration testing approach

### 3.5 Technical Debt Considerations

- Will the proposed solution introduce significant technical debt?
- Is there existing technical debt that will impede implementation?
- What is the plan for managing debt over the project lifecycle?

### 3.6 Modern Technology Considerations

- **Cloud-Native Readiness**: As of 2024-2025, approximately 95% of new digital
  workloads are deployed on cloud-native platforms. Evaluate containerization,
  orchestration (Kubernetes), serverless, and managed services.
- **AI/ML Readiness**: If the solution involves machine learning, assess data
  pipeline maturity, model training infrastructure, inference serving, and
  MLOps capabilities.
- **Edge Computing**: For latency-sensitive or bandwidth-constrained workloads,
  evaluate edge deployment feasibility, device management, and OTA update
  strategies.

---

## 4. Economic and Financial Analysis

Economic feasibility determines whether the project makes financial sense. This
is often the most scrutinized dimension by executive stakeholders.

### 4.1 Total Cost of Ownership (TCO)

TCO should cover a 3-5 year horizon. A common mistake is focusing only on
development costs; maintenance and operations can account for up to 75% of the
total cost of ownership over the full lifecycle.

**Cost categories to include:**

| Category              | Examples                                                    |
|-----------------------|-------------------------------------------------------------|
| Development           | Engineering salaries, contractors, tools, licenses          |
| Infrastructure        | Cloud compute, storage, networking, CDN, DNS                |
| Operations            | DevOps, SRE, on-call, monitoring, incident response         |
| Maintenance           | Bug fixes, security patches, dependency updates             |
| Support               | Customer support, documentation, training                   |
| Compliance            | Audits, certifications, legal review                        |
| Opportunity Cost      | What else could these resources be working on?              |
| Decommissioning       | Data migration, contract termination, system sunset         |

### 4.2 Financial Metrics

**Return on Investment (ROI)**:

```
ROI = (Net Profit / Total Cost of Ownership) x 100%
```

Where Net Profit = Total Benefits - Total Costs over the analysis period.

**Net Present Value (NPV)**:

```
NPV = Sum from t=0 to n of [ Cash_Flow_t / (1 + r)^t ]
```

Where `r` is the discount rate (typically the company's cost of capital or a
hurdle rate) and `t` is the time period. A positive NPV indicates the project
adds value.

**Internal Rate of Return (IRR)**: The discount rate at which NPV equals zero.
Compare IRR against the company's hurdle rate. If IRR > hurdle rate, the project
is financially attractive.

**Payback Period**:

```
Payback Period = Total Investment / Annual Net Cash Flow
```

Shorter payback periods are preferred. Most organizations require payback within
2-3 years for technology investments.

### 4.3 Cost-Benefit Analysis Calculator

```python
"""
Cost-Benefit Analysis Calculator
Computes NPV, ROI, IRR, and Payback Period for a technology investment.
"""

from dataclasses import dataclass, field


@dataclass
class CostBenefitAnalysis:
    """Performs financial feasibility analysis for a technology project."""

    project_name: str
    initial_investment: float
    annual_costs: list[float]       # Ongoing costs per year
    annual_benefits: list[float]    # Revenue or savings per year
    discount_rate: float = 0.10     # 10% default discount rate

    def __post_init__(self):
        if len(self.annual_costs) != len(self.annual_benefits):
            raise ValueError("annual_costs and annual_benefits must have equal length")
        self.years = len(self.annual_costs)

    @property
    def net_cash_flows(self) -> list[float]:
        """Calculate net cash flow for each year, including initial investment."""
        flows = [-self.initial_investment]
        for i in range(self.years):
            flows.append(self.annual_benefits[i] - self.annual_costs[i])
        return flows

    def npv(self) -> float:
        """Net Present Value: sum of discounted cash flows."""
        total = 0.0
        for t, cash_flow in enumerate(self.net_cash_flows):
            total += cash_flow / ((1 + self.discount_rate) ** t)
        return round(total, 2)

    def roi(self) -> float:
        """Return on Investment as a percentage."""
        total_benefits = sum(self.annual_benefits)
        total_costs = self.initial_investment + sum(self.annual_costs)
        net_profit = total_benefits - total_costs
        return round((net_profit / total_costs) * 100, 2)

    def payback_period(self) -> float | None:
        """Years until cumulative cash flow turns positive."""
        cumulative = 0.0
        for t, cash_flow in enumerate(self.net_cash_flows):
            cumulative += cash_flow
            if cumulative >= 0:
                # Interpolate within the year for precision
                if t == 0:
                    return 0.0
                previous_cumulative = cumulative - cash_flow
                fraction = abs(previous_cumulative) / cash_flow
                return round(t - 1 + fraction, 2)
        return None  # Investment never pays back within the analysis period

    def irr(self, tolerance: float = 0.0001, max_iterations: int = 1000) -> float | None:
        """Internal Rate of Return using bisection method."""
        low, high = -0.5, 5.0
        flows = self.net_cash_flows
        for _ in range(max_iterations):
            mid = (low + high) / 2
            npv_mid = sum(cf / ((1 + mid) ** t) for t, cf in enumerate(flows))
            if abs(npv_mid) < tolerance:
                return round(mid * 100, 2)  # Return as percentage
            if npv_mid > 0:
                low = mid
            else:
                high = mid
        return None

    def summary(self) -> dict:
        """Generate a complete financial summary."""
        return {
            "project": self.project_name,
            "initial_investment": self.initial_investment,
            "analysis_period_years": self.years,
            "discount_rate": f"{self.discount_rate * 100:.1f}%",
            "npv": self.npv(),
            "roi": f"{self.roi():.1f}%",
            "irr": f"{self.irr():.1f}%" if self.irr() else "N/A",
            "payback_period": f"{self.payback_period():.1f} years" if self.payback_period() else "Never",
            "recommendation": self._recommendation(),
        }

    def _recommendation(self) -> str:
        npv_val = self.npv()
        irr_val = self.irr()
        if npv_val > 0 and irr_val and irr_val > self.discount_rate * 100:
            return "FINANCIALLY VIABLE - Positive NPV and IRR exceeds hurdle rate"
        elif npv_val > 0:
            return "MARGINALLY VIABLE - Positive NPV but IRR is below hurdle rate"
        else:
            return "NOT VIABLE - Negative NPV; project destroys value"


# --- Example Usage ---
if __name__ == "__main__":
    analysis = CostBenefitAnalysis(
        project_name="Cloud Migration - Legacy ERP to SaaS",
        initial_investment=500_000,
        annual_costs=[120_000, 130_000, 140_000, 150_000, 160_000],
        annual_benefits=[200_000, 280_000, 350_000, 400_000, 450_000],
        discount_rate=0.10,
    )
    summary = analysis.summary()
    for key, value in summary.items():
        print(f"  {key}: {value}")
```

---

## 5. Market Feasibility

Market feasibility determines whether there is sufficient demand for the
proposed solution and whether the organization can capture a viable share of
that demand.

### 5.1 TAM / SAM / SOM Sizing

| Metric | Definition                                   | Method               |
|--------|----------------------------------------------|----------------------|
| TAM    | Total Addressable Market                     | Top-down or bottom-up|
| SAM    | Serviceable Addressable Market               | TAM filtered by reach|
| SOM    | Serviceable Obtainable Market                | SAM filtered by share|

**Top-Down Approach**: Start from industry reports (Gartner, IDC, Statista) and
narrow down by geography, segment, and pricing.

**Bottom-Up Approach**: Start from unit economics -- number of potential
customers multiplied by average revenue per customer. This approach is generally
more credible to investors and stakeholders.

### 5.2 Competitive Landscape

Map competitors across four categories:

1. **Direct Competitors**: Same product, same market.
2. **Indirect Competitors**: Different product, same problem.
3. **Potential Competitors**: Not in the market today but could enter easily
   (e.g., adjacent products from large platforms).
4. **Substitutes**: Entirely different approaches to solving the same problem
   (including manual processes and the status quo).

For each competitor, evaluate:
- Feature parity and differentiation
- Pricing model and positioning
- Market share and growth trajectory
- Strengths and weaknesses
- Barriers to switching

### 5.3 Market Timing

- Is the market emerging, growing, mature, or declining?
- Are there regulatory or technological catalysts?
- What is the window of opportunity?
- First-mover advantage vs. fast-follower strategy considerations.

---

## 6. Operational Feasibility

Operational feasibility assesses whether the organization has the capacity and
capability to build, deploy, and sustain the proposed solution.

### 6.1 Resource Requirements

For each role needed, document:

- Number of FTEs required
- Duration of engagement
- Whether the role is filled internally or requires hiring/contracting
- Lead time to onboard

### 6.2 Team Capability Matrix

| Capability             | Required Level | Current Level | Gap    | Mitigation           |
|------------------------|---------------|---------------|--------|----------------------|
| Kubernetes Operations  | Advanced       | Intermediate  | Medium | Training + Consultant|
| ML Pipeline Design     | Expert         | Beginner      | High   | Hire ML Engineer     |
| React Frontend         | Advanced       | Advanced      | None   | N/A                  |
| PostgreSQL at Scale    | Advanced       | Intermediate  | Medium | Training program     |
| CI/CD Automation       | Intermediate   | Intermediate  | None   | N/A                  |

### 6.3 Organizational Readiness

- **Sponsorship**: Is there executive sponsorship with budget authority?
- **Alignment**: Does the project align with strategic objectives?
- **Culture**: Is the organization receptive to the proposed change?
- **Processes**: Are development and operational processes mature enough?
- **Change Management Capacity**: How many concurrent change initiatives can the
  organization absorb? Most organizations can handle 2-3 major changes at once.

---

## 7. Risk Assessment

### 7.1 Risk Categories

| Category   | Examples                                                         |
|------------|------------------------------------------------------------------|
| Technical  | Unproven technology, integration failures, scalability limits    |
| Resource   | Key person dependency, hiring difficulty, skill gaps             |
| Market     | Demand uncertainty, competitive response, market timing          |
| Financial  | Budget overrun, currency fluctuation, funding withdrawal         |
| Schedule   | Dependency delays, scope creep, regulatory approval timelines    |
| Operational| Process gaps, organizational resistance, support capacity        |

### 7.2 Probability-Impact Matrix (5x5)

```
Impact ->     Negligible(1)  Minor(2)  Moderate(3)  Major(4)  Critical(5)
Probability
Almost Certain(5)   5          10        15           20         25
Likely(4)           4           8        12           16         20
Possible(3)         3           6         9           12         15
Unlikely(2)         2           4         6            8         10
Rare(1)             1           2         3            4          5
```

**Risk Response Zones:**

| Score Range | Zone   | Color  | Response                                      |
|-------------|--------|--------|-----------------------------------------------|
| 1-4         | Low    | GREEN  | Accept -- monitor, no active mitigation needed |
| 5-12        | Medium | YELLOW | Mitigate -- develop and execute mitigation plan|
| 15-25       | High   | RED    | Immediate action -- escalate and resolve now    |

### 7.3 Risk Register Implementation

```python
"""
Risk Register with Probability-Impact Scoring
Supports risk categorization, scoring, and prioritized mitigation tracking.
"""

from dataclasses import dataclass, field
from enum import Enum


class RiskCategory(Enum):
    TECHNICAL = "Technical"
    RESOURCE = "Resource"
    MARKET = "Market"
    FINANCIAL = "Financial"
    SCHEDULE = "Schedule"
    OPERATIONAL = "Operational"


class RiskZone(Enum):
    GREEN = "Accept"
    YELLOW = "Mitigate"
    RED = "Immediate Action"


@dataclass
class Risk:
    """Represents a single identified risk."""

    id: str
    title: str
    description: str
    category: RiskCategory
    probability: int  # 1-5
    impact: int       # 1-5
    mitigation: str
    owner: str
    status: str = "Open"

    def __post_init__(self):
        if not (1 <= self.probability <= 5):
            raise ValueError(f"Probability must be 1-5, got {self.probability}")
        if not (1 <= self.impact <= 5):
            raise ValueError(f"Impact must be 1-5, got {self.impact}")

    @property
    def score(self) -> int:
        """Risk score = probability x impact."""
        return self.probability * self.impact

    @property
    def zone(self) -> RiskZone:
        """Determine risk response zone based on score."""
        if self.score <= 4:
            return RiskZone.GREEN
        elif self.score <= 12:
            return RiskZone.YELLOW
        else:
            return RiskZone.RED


@dataclass
class RiskRegister:
    """Manages a collection of risks for a feasibility study."""

    project_name: str
    risks: list[Risk] = field(default_factory=list)

    def add_risk(self, risk: Risk) -> None:
        self.risks.append(risk)

    def get_by_zone(self, zone: RiskZone) -> list[Risk]:
        return [r for r in self.risks if r.zone == zone]

    def get_by_category(self, category: RiskCategory) -> list[Risk]:
        return [r for r in self.risks if r.category == category]

    def top_risks(self, n: int = 5) -> list[Risk]:
        """Return the top N risks sorted by score descending."""
        return sorted(self.risks, key=lambda r: r.score, reverse=True)[:n]

    def risk_profile(self) -> dict:
        """Generate an overall risk profile summary."""
        total = len(self.risks)
        red = len(self.get_by_zone(RiskZone.RED))
        yellow = len(self.get_by_zone(RiskZone.YELLOW))
        green = len(self.get_by_zone(RiskZone.GREEN))
        avg_score = sum(r.score for r in self.risks) / total if total > 0 else 0

        if red > 0:
            overall = "HIGH - Critical risks require immediate attention"
        elif yellow > total * 0.5:
            overall = "MEDIUM - Multiple risks require active mitigation"
        else:
            overall = "LOW - Risks are manageable with standard monitoring"

        return {
            "project": self.project_name,
            "total_risks": total,
            "red_risks": red,
            "yellow_risks": yellow,
            "green_risks": green,
            "average_score": round(avg_score, 1),
            "overall_assessment": overall,
        }

    def print_register(self) -> None:
        """Print a formatted risk register."""
        print(f"\n{'='*80}")
        print(f"RISK REGISTER: {self.project_name}")
        print(f"{'='*80}")
        sorted_risks = sorted(self.risks, key=lambda r: r.score, reverse=True)
        for risk in sorted_risks:
            zone_label = risk.zone.value
            print(f"\n[{risk.id}] {risk.title} (Score: {risk.score} - {zone_label})")
            print(f"  Category:    {risk.category.value}")
            print(f"  Probability: {risk.probability}/5 | Impact: {risk.impact}/5")
            print(f"  Mitigation:  {risk.mitigation}")
            print(f"  Owner:       {risk.owner}")
            print(f"  Status:      {risk.status}")


# --- Example Usage ---
if __name__ == "__main__":
    register = RiskRegister(project_name="Cloud Migration Feasibility")

    register.add_risk(Risk(
        id="R-001",
        title="Legacy API Incompatibility",
        description="Legacy SOAP services may not integrate with new REST gateway",
        category=RiskCategory.TECHNICAL,
        probability=4, impact=4,
        mitigation="Build adapter layer; PoC integration in Sprint 1",
        owner="Tech Lead",
    ))
    register.add_risk(Risk(
        id="R-002",
        title="Key Engineer Departure",
        description="Single point of knowledge on legacy billing system",
        category=RiskCategory.RESOURCE,
        probability=3, impact=5,
        mitigation="Knowledge transfer sessions; document critical paths",
        owner="Engineering Manager",
    ))
    register.add_risk(Risk(
        id="R-003",
        title="Cloud Cost Overrun",
        description="Unpredictable scaling costs in first 6 months",
        category=RiskCategory.FINANCIAL,
        probability=3, impact=3,
        mitigation="Set billing alerts; use reserved instances; monthly reviews",
        owner="Finance Lead",
    ))
    register.add_risk(Risk(
        id="R-004",
        title="GDPR Data Residency",
        description="Customer data must remain in EU regions",
        category=RiskCategory.OPERATIONAL,
        probability=2, impact=5,
        mitigation="Configure EU-only regions; legal review of cloud provider DPA",
        owner="Compliance Officer",
    ))

    register.print_register()
    print("\nRisk Profile:")
    for key, value in register.risk_profile().items():
        print(f"  {key}: {value}")
```

---

## 8. Proof of Concept (PoC) Design

### 8.1 PoC vs Prototype vs MVP

| Attribute        | PoC                   | Prototype              | MVP                       |
|------------------|-----------------------|------------------------|---------------------------|
| Purpose          | Validate feasibility  | Demonstrate experience | Test market viability      |
| Audience         | Internal team         | Stakeholders/Users     | Real customers             |
| Fidelity         | Low (functional only) | Medium (look and feel) | High (production quality)  |
| Duration         | 2-4 weeks             | 4-8 weeks              | 8-16 weeks                |
| Success Criteria | Technical validation  | User feedback          | Market metrics             |
| Throwaway?       | Usually yes           | Sometimes              | No -- it evolves           |

### 8.2 PoC Design Principles

1. **Time-box strictly**: 2-4 weeks maximum. If you cannot validate the
   hypothesis in that time, the question may be too broad.
2. **Single hypothesis per PoC**: "Can our data pipeline process 10,000
   events/second with sub-100ms latency?" -- not "Can we build the whole
   system?"
3. **Define success criteria upfront**: Before writing a single line of code,
   document what "success" and "failure" look like in measurable terms.
4. **Minimize scope ruthlessly**: Strip away everything that is not directly
   related to validating the hypothesis. No UI polish, no error handling
   beyond the critical path, no observability.
5. **Document findings thoroughly**: The PoC code is disposable; the learnings
   are the deliverable.

### 8.3 When to Skip the PoC

- Working with proven technology in a familiar domain
- The team has direct prior experience with a very similar implementation
- The risk is primarily non-technical (market, financial, organizational)
- Time pressure makes even a 2-week PoC impractical -- in which case, clearly
  document the unvalidated assumptions and associated risks

---

## 9. Decision Matrices

Decision matrices provide structured, repeatable methods for evaluating
alternatives. They reduce cognitive bias and make the decision process
transparent and auditable.

### 9.1 Weighted Scoring Model

The most common approach for technology decisions. Each criterion is assigned
a weight (summing to 1.0), and each alternative is scored on every criterion.

### 9.2 Advanced Methods

- **AHP (Analytic Hierarchy Process)**: Uses pairwise comparisons to derive
  mathematically consistent weights. Preferred when stakeholders disagree on
  criterion importance.
- **TOPSIS (Technique for Order of Preference by Similarity to Ideal Solution)**:
  Ranks alternatives by their geometric distance from the ideal and anti-ideal
  solutions. Useful for complex multi-criteria decisions.
- **ELECTRE (Elimination and Choice Expressing Reality)**: Outranking method
  that handles criteria that cannot be easily compensated against each other.
- **Sensitivity Analysis**: After scoring, vary the weights by +/-10-20% to see
  if the ranking changes. If a small weight change flips the top choice, the
  decision is fragile and needs further investigation.

### 9.3 Decision Matrix Implementation

```python
"""
Decision Matrix with Weighted Scoring
Supports multiple alternatives, weighted criteria, and sensitivity analysis.
"""

from dataclasses import dataclass, field


@dataclass
class Criterion:
    """A single evaluation criterion."""

    name: str
    weight: float       # 0.0 to 1.0
    description: str = ""


@dataclass
class Alternative:
    """An option being evaluated."""

    name: str
    scores: dict[str, float] = field(default_factory=dict)  # criterion_name -> score (1-5)

    def set_score(self, criterion_name: str, score: float) -> None:
        if not (1 <= score <= 5):
            raise ValueError(f"Score must be 1-5, got {score}")
        self.scores[criterion_name] = score


@dataclass
class DecisionMatrix:
    """Weighted scoring decision matrix for comparing technology alternatives."""

    decision_name: str
    criteria: list[Criterion] = field(default_factory=list)
    alternatives: list[Alternative] = field(default_factory=list)

    def validate(self) -> bool:
        """Ensure weights sum to 1.0 and all scores are present."""
        total_weight = sum(c.weight for c in self.criteria)
        if abs(total_weight - 1.0) > 0.01:
            raise ValueError(f"Weights must sum to 1.0, got {total_weight:.2f}")
        criteria_names = {c.name for c in self.criteria}
        for alt in self.alternatives:
            missing = criteria_names - set(alt.scores.keys())
            if missing:
                raise ValueError(f"Alternative '{alt.name}' missing scores for: {missing}")
        return True

    def weighted_scores(self) -> dict[str, float]:
        """Calculate weighted score for each alternative."""
        self.validate()
        results = {}
        for alt in self.alternatives:
            total = sum(
                alt.scores[c.name] * c.weight
                for c in self.criteria
            )
            results[alt.name] = round(total, 3)
        return results

    def rank(self) -> list[tuple[str, float]]:
        """Return alternatives ranked by weighted score, descending."""
        scores = self.weighted_scores()
        return sorted(scores.items(), key=lambda x: x[1], reverse=True)

    def sensitivity_analysis(self, criterion_name: str,
                              delta: float = 0.1) -> dict[str, list[tuple[str, float]]]:
        """
        Test how ranking changes when a criterion weight is varied by +/- delta.
        Redistributes the weight change proportionally across other criteria.
        """
        target = next(c for c in self.criteria if c.name == criterion_name)
        original_weight = target.weight
        results = {}

        for direction, label in [(-delta, "decreased"), (delta, "increased")]:
            new_weight = max(0.0, min(1.0, original_weight + direction))
            adjustment = original_weight - new_weight  # amount redistributed
            other_total = sum(c.weight for c in self.criteria if c.name != criterion_name)

            # Temporarily adjust weights
            original_weights = {}
            for c in self.criteria:
                original_weights[c.name] = c.weight
                if c.name == criterion_name:
                    c.weight = new_weight
                elif other_total > 0:
                    c.weight = c.weight + (adjustment * c.weight / other_total)

            results[label] = self.rank()

            # Restore original weights
            for c in self.criteria:
                c.weight = original_weights[c.name]

        results["original"] = self.rank()
        return results

    def recommendation(self) -> str:
        """Generate a recommendation based on the weighted scores."""
        ranked = self.rank()
        if len(ranked) < 2:
            return f"Recommendation: {ranked[0][0]} (only option evaluated)"

        top_name, top_score = ranked[0]
        second_name, second_score = ranked[1]
        gap = top_score - second_score

        if gap > 0.5:
            strength = "strong"
        elif gap > 0.2:
            strength = "moderate"
        else:
            strength = "marginal"

        return (
            f"Recommendation: {top_name} ({top_score:.2f}) with {strength} advantage "
            f"over {second_name} ({second_score:.2f}). "
            f"Gap: {gap:.2f} points. "
            f"{'Perform sensitivity analysis to confirm.' if strength == 'marginal' else ''}"
        )

    def print_matrix(self) -> None:
        """Print a formatted decision matrix."""
        self.validate()
        print(f"\nDECISION MATRIX: {self.decision_name}")
        print("=" * 80)

        # Header
        header = f"{'Criterion':<25} {'Weight':>6}"
        for alt in self.alternatives:
            header += f" | {alt.name:>12}"
        print(header)
        print("-" * 80)

        # Rows
        for c in self.criteria:
            row = f"{c.name:<25} {c.weight:>6.2f}"
            for alt in self.alternatives:
                score = alt.scores[c.name]
                weighted = score * c.weight
                row += f" | {score:>4.1f} ({weighted:>4.2f})"
            print(row)

        # Totals
        print("-" * 80)
        scores = self.weighted_scores()
        totals = f"{'TOTAL':<25} {'1.00':>6}"
        for alt in self.alternatives:
            totals += f" | {scores[alt.name]:>11.2f}"
        print(totals)
        print(f"\n{self.recommendation()}")


# --- Example Usage ---
if __name__ == "__main__":
    matrix = DecisionMatrix(decision_name="Backend Framework Selection")

    matrix.criteria = [
        Criterion("Performance", 0.25, "Request throughput and latency"),
        Criterion("Developer Productivity", 0.20, "Speed of development"),
        Criterion("Ecosystem Maturity", 0.15, "Libraries, tools, community"),
        Criterion("Scalability", 0.20, "Horizontal and vertical scaling"),
        Criterion("Talent Availability", 0.10, "Ease of hiring"),
        Criterion("Operational Cost", 0.10, "Infrastructure and maintenance"),
    ]

    go_service = Alternative("Go + gRPC")
    go_service.set_score("Performance", 5.0)
    go_service.set_score("Developer Productivity", 3.0)
    go_service.set_score("Ecosystem Maturity", 3.5)
    go_service.set_score("Scalability", 5.0)
    go_service.set_score("Talent Availability", 3.0)
    go_service.set_score("Operational Cost", 4.5)

    node_service = Alternative("Node + Express")
    node_service.set_score("Performance", 3.0)
    node_service.set_score("Developer Productivity", 4.5)
    node_service.set_score("Ecosystem Maturity", 5.0)
    node_service.set_score("Scalability", 3.5)
    node_service.set_score("Talent Availability", 5.0)
    node_service.set_score("Operational Cost", 3.0)

    python_service = Alternative("Python + FastAPI")
    python_service.set_score("Performance", 3.5)
    python_service.set_score("Developer Productivity", 5.0)
    python_service.set_score("Ecosystem Maturity", 4.5)
    python_service.set_score("Scalability", 3.0)
    python_service.set_score("Talent Availability", 4.5)
    python_service.set_score("Operational Cost", 3.5)

    matrix.alternatives = [go_service, node_service, python_service]

    matrix.print_matrix()

    print("\nSensitivity Analysis (varying 'Performance' weight by +/-10%):")
    sensitivity = matrix.sensitivity_analysis("Performance", delta=0.10)
    for scenario, ranking in sensitivity.items():
        print(f"  {scenario}: {[(name, f'{score:.2f}') for name, score in ranking]}")
```

---

## 10. Stakeholder Analysis

### 10.1 Power-Interest Grid

Map stakeholders into four quadrants based on their power (ability to influence
the project) and interest (level of concern about the project):

```
                    High Power
                        |
    Keep Satisfied      |      Manage Closely
    (High Power,        |      (High Power,
     Low Interest)      |       High Interest)
                        |
  ----------------------+----------------------
                        |
    Monitor             |      Keep Informed
    (Low Power,         |      (Low Power,
     Low Interest)      |       High Interest)
                        |
                    Low Power
         Low Interest              High Interest
```

**Manage Closely** (High Power, High Interest): These are your key stakeholders.
Engage them in decision-making, provide regular updates, and ensure their
concerns are addressed.

**Keep Satisfied** (High Power, Low Interest): Keep them informed at a summary
level. Avoid overwhelming them with detail but ensure they are not surprised.

**Keep Informed** (Low Power, High Interest): Provide regular detailed updates.
These stakeholders can become advocates or detractors.

**Monitor** (Low Power, Low Interest): Minimal communication. Standard project
reports are sufficient.

### 10.2 RACI Matrix

For each major deliverable or decision in the feasibility study, assign roles:

| Deliverable             | Sponsor | Tech Lead | Architect | Finance | PM  |
|-------------------------|---------|-----------|-----------|---------|-----|
| Technical Assessment    | I       | A         | R         | I       | C   |
| Financial Analysis      | A       | C         | C         | R       | I   |
| Risk Assessment         | I       | R         | R         | C       | A   |
| Go/No-Go Recommendation| A       | C         | C         | C       | R   |
| PoC Execution           | I       | A         | R         | I       | C   |

- **R** = Responsible (does the work)
- **A** = Accountable (final decision authority; exactly one per deliverable)
- **C** = Consulted (provides input before the decision)
- **I** = Informed (notified after the decision)

### 10.3 Stakeholder Group Size

Keep the core feasibility team lean: **5-7 key stakeholders** maximum. Larger
groups lead to slower decisions, diffused accountability, and meeting fatigue.
Use the RACI matrix to determine who needs to be in the room versus who can
be informed asynchronously.

---

## 11. Go/No-Go Recommendations

### 11.1 Evidence-Based Decision Framework

A go/no-go recommendation must be grounded in evidence, not opinion. The
recommendation package should include:

1. **Feasibility Scorecard**: Weighted scores across all TELOS dimensions.
2. **Financial Summary**: NPV, ROI, IRR, payback period with sensitivity ranges.
3. **Risk Profile**: Risk register summary with top 5 risks and mitigation plans.
4. **Conditions**: If CONDITIONAL GO, enumerate specific conditions that must be
   met before full commitment (e.g., "PoC must demonstrate <100ms latency at
   10K concurrent users").

### 11.2 Scoring Thresholds

Using a weighted average across TELOS dimensions (each scored 1-5):

| Weighted Score | Recommendation  | Action                                       |
|----------------|-----------------|----------------------------------------------|
| >= 3.5         | GO              | Proceed to planning and execution             |
| 2.5 - 3.49     | CONDITIONAL GO  | Proceed with conditions and phase gates       |
| < 2.5          | NO-GO           | Do not proceed; document reasons and redirect |

The DEFER option is applied when the score is below threshold but conditions
are expected to change (e.g., technology is maturing, market is emerging,
regulatory clarity is pending).

### 11.3 Presenting the Recommendation

Structure the final presentation as:

1. **Executive Summary** (1 slide/page): Recommendation, headline metrics, key
   conditions.
2. **Feasibility Scorecard** (1 slide): Spider/radar chart of TELOS dimensions.
3. **Financial Case** (1-2 slides): NPV, ROI, payback, sensitivity ranges.
4. **Risk Overview** (1 slide): Top 5 risks with scores and mitigations.
5. **Conditions and Next Steps** (1 slide): What must happen next.
6. **Appendix**: Detailed analysis, methodology, assumptions, data sources.

---

## 12. Best Practices

1. **Start early**: Conduct the feasibility study when less than 10% of the
   total project budget has been committed. Earlier is cheaper.

2. **Time-box ruthlessly**: 2-6 weeks depending on project size. A feasibility
   study that takes longer than the PoC is a sign of analysis paralysis.

3. **Use multiple frameworks**: No single framework captures all dimensions.
   Combine TELOS for structure, financial metrics for economics, risk matrices
   for uncertainty, and decision matrices for alternatives.

4. **Engage stakeholders early and often**: Feasibility is not a back-room
   exercise. Stakeholder buy-in during the study translates to smoother
   execution later.

5. **Separate analysis from advocacy**: The feasibility team should be
   incentivized to find the truth, not to justify a predetermined conclusion.
   Consider including a "devil's advocate" role.

6. **PoC before commitment**: If the technical feasibility score is below 4.0
   or there are unvalidated assumptions, require a time-boxed PoC before
   granting a GO recommendation.

7. **Use 3-5 year TCO, not just development cost**: Short-term cost estimates
   systematically undervalue operational and maintenance burden.

8. **Apply sensitivity analysis**: Every financial projection is wrong. The
   question is how wrong it can be before the decision changes. Vary key
   assumptions by +/-20% and document the impact.

9. **Document assumptions explicitly**: Every model rests on assumptions. List
   them, tag them with confidence levels (high/medium/low), and identify which
   assumptions, if wrong, would change the recommendation.

10. **Version and archive**: The feasibility study is a living document during
    the study phase but becomes a historical artifact afterward. Archive it
    with clear versioning so future teams can learn from it.

---

## 13. Anti-Patterns

Recognizing and avoiding these common failure modes is as important as following
best practices.

### 13.1 Confirmation Bias Study

**What it looks like**: The study is conducted to justify a decision that has
already been made. Evidence that supports the decision is emphasized; evidence
against it is downplayed or omitted.

**How to avoid**: Include a devil's advocate. Require the team to document the
strongest arguments against proceeding. Have the feasibility study reviewed by
someone who was not involved in the original proposal.

### 13.2 Analysis Paralysis

**What it looks like**: The study drags on for months, consuming resources
without producing a decision. Every finding raises new questions. The scope
of the study keeps expanding.

**How to avoid**: Time-box the study strictly. Define the decision criteria and
thresholds upfront. Accept that uncertainty will remain and document it rather
than trying to eliminate it.

### 13.3 Tunnel Vision (Technical-Only Assessment)

**What it looks like**: The study focuses exclusively on whether the technology
works, ignoring market demand, operational capacity, financial viability, and
organizational readiness.

**How to avoid**: Use the full TELOS framework. Ensure the study team includes
non-technical stakeholders (finance, operations, business development).

### 13.4 Resume-Driven Development

**What it looks like**: Technology choices are driven by what the team wants to
learn or what looks good on a resume, rather than what best serves the project.

**How to avoid**: Require technology choices to be justified against evaluation
criteria in the decision matrix. Score "boring but proven" options alongside
"exciting but risky" ones.

### 13.5 Hockey Stick Projections

**What it looks like**: Financial projections show modest costs and explosive
revenue growth. Year 1 is flat, years 2-5 shoot upward at 50-100% annual growth
with no justification.

**How to avoid**: Require bottom-up revenue projections tied to specific customer
acquisition channels. Run scenarios with conservative (10%), moderate (25%), and
optimistic (50%) growth rates. Base the decision on the conservative scenario.

### 13.6 Sunk Cost Anchoring

**What it looks like**: "We have already spent $500K on this, so we must continue."
Past investment is used to justify future investment, regardless of whether the
future investment is independently justified.

**How to avoid**: Frame every decision as a fresh investment. The question is not
"should we continue?" but "if we were starting from scratch today with what we
know now, would we start this project?"

### 13.7 HiPPO Decisions

**What it looks like**: HiPPO stands for "Highest Paid Person's Opinion." The
feasibility study is overridden by an executive who "just knows" the answer.
The study becomes theater.

**How to avoid**: Establish upfront that the feasibility study recommendation
will be evidence-based and that overriding it requires explicitly documented
reasons. Make the decision criteria and thresholds transparent before the study
begins.

---

## 14. Legal Feasibility Considerations

While often underweighted, legal feasibility can be a project-killer:

- **Intellectual Property**: Patent landscape, open-source license compatibility
  (GPL vs MIT vs Apache), trade secrets.
- **Data Privacy Regulations**: GDPR (EU), CCPA/CPRA (California), LGPD
  (Brazil), PIPA (South Korea). Determine which regulations apply based on
  where users are located, not where servers are hosted.
- **Industry-Specific Regulations**: HIPAA (healthcare), PCI-DSS (payments),
  SOX (financial reporting), FedRAMP (US government).
- **Contractual Obligations**: Existing vendor agreements, exclusivity clauses,
  non-compete provisions.
- **Export Controls**: ITAR, EAR for technology with potential dual-use
  applications.

---

## 15. Scheduling Feasibility

Scheduling feasibility assesses whether the project can be delivered within
the required timeframe given resource and dependency constraints.

Key considerations:

- **Critical Path Analysis**: Identify the longest chain of dependent tasks.
  This determines the minimum possible timeline.
- **Resource Leveling**: Are the same people needed for multiple concurrent
  tasks? Resource contention extends timelines.
- **External Dependencies**: Vendor deliverables, regulatory approvals, partner
  integrations -- all outside your direct control.
- **Buffer and Contingency**: Add 20-30% schedule buffer for medium-complexity
  projects, 40-50% for high-complexity or novel technology.
- **Milestones and Phase Gates**: Define clear checkpoints where the project
  can be paused, pivoted, or terminated based on results.

---

## 16. Sources & References

The following resources provide additional depth on feasibility study
methodologies, frameworks, and techniques:

1. **Asana - How to Conduct a Feasibility Study**: Comprehensive overview of
   feasibility study structure and process.
   https://asana.com/resources/feasibility-study

2. **Galorath - Project Feasibility Analysis**: Detailed methodology for project
   feasibility estimation including cost modeling.
   https://galorath.com/project/feasibility/

3. **ScienceSoft - Software Development Feasibility Study**: Practical guide
   to feasibility studies specific to software development projects.
   https://www.scnsoft.com/software-development/feasibility-study

4. **Apriorit - Technical Feasibility Analysis**: In-depth treatment of
   technical feasibility assessment for software projects.
   https://www.apriorit.com/dev-blog/technical-feasibility-analysis

5. **MindTools - TELOS Feasibility Study**: Guide to the TELOS framework for
   multi-dimensional feasibility assessment.
   https://www.mindtools.com/afr89t8/how-to-do-a-telos-feasability-study/

6. **1000Minds - Multi-Criteria Decision Analysis**: Overview of MCDM/MCDA
   methods including AHP, TOPSIS, and ELECTRE.
   https://www.1000minds.com/decision-making/what-is-mcdm-mcda

---

*This skill document provides a structured, repeatable approach to feasibility
studies for software and technology projects. Apply the frameworks proportionally
to project size and risk -- a weekend hackathon does not need a full TELOS
analysis, but a multi-million dollar platform migration absolutely does.*
