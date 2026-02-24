---
name: researcher-web
description: Web research techniques — search strategy, source evaluation, OSINT, data extraction
---

# Web Research Techniques

Comprehensive guide to conducting effective web research for software projects, covering search strategy formulation, source evaluation, multi-source triangulation, and structured data extraction.

## Table of Contents

1. Search Strategy Formulation
2. Advanced Search Operators
3. Source Evaluation & Credibility
4. Multi-Source Triangulation
5. Academic & Technical Research
6. API Documentation Research
7. Competitive Intelligence
8. Open Source Intelligence (OSINT)
9. Data Extraction & Structuring
10. Best Practices
11. Anti-Patterns
12. Sources & References

---

## 1. Search Strategy Formulation

Effective research begins with a well-constructed search strategy. Define the research question, identify key concepts, and plan iterative refinement.

### Define the Research Question

Before searching, articulate:
- **What** specific information do you need?
- **Why** — what decision will this inform?
- **Scope** — how broad or narrow should the answer be?
- **Recency** — does the information need to be current (e.g., 2025-2026)?

### Keyword Decomposition

Break complex questions into searchable components:

```
Research question: "What is the best database for a real-time collaborative editor?"

Keywords:
  Primary:   real-time database, collaborative editing
  Secondary: CRDT, operational transform, conflict resolution
  Tertiary:  Yjs, Automerge, Firestore, Supabase Realtime
```

### Query Iteration Pattern

Start broad, then narrow based on initial results:

```
Round 1 (broad):     "real-time collaborative database 2025"
Round 2 (specific):  "CRDT database comparison Yjs Automerge performance"
Round 3 (targeted):  "Yjs vs Automerge latency benchmarks production"
Round 4 (expert):    site:github.com "yjs" "automerge" stars:>1000
```

### Boolean Query Construction

Combine terms strategically using Boolean operators:

```
# AND — narrow results (both terms required)
"collaborative editing" AND "conflict resolution"

# OR — broaden results (either term)
CRDT OR "operational transform"

# NOT — exclude irrelevant results
"real-time database" NOT gaming

# Parentheses — group operations
("collaborative editing" OR "real-time sync") AND (CRDT OR OT)

# Exact phrase — quotation marks
"operational transformation algorithm"
```

---

## 2. Advanced Search Operators

Master search engine operators to find precise information quickly.

### Google Search Operators

```
# Site-specific search
site:github.com "CRDT implementation"
site:stackoverflow.com [python] pandas groupby performance

# File type filtering
filetype:pdf "system design" "microservices" 2025
filetype:csv "benchmark results" database

# Title and URL filtering
intitle:"comparison" "React" "Vue" "Svelte" 2025
inurl:docs "getting started" supabase realtime

# Exclude domains
"CRDT implementation" -site:medium.com -site:dev.to

# Wildcard for unknown terms
"* is the best CRDT library for *"

# Number range
"database benchmark" TPS 10000..1000000

# Combine operators
site:github.com intitle:"awesome" "real-time" stars filetype:md
```

### GitHub-Specific Search

```
# Search repositories
language:python stars:>500 "machine learning" pushed:>2025-01-01

# Search code
"import torch" filename:requirements.txt language:python

# Search issues
is:issue is:open label:"good first issue" "CRDT"

# Search by topic
topic:crdt language:typescript stars:>100
```

### Stack Overflow Search

```
# Tagged search
[python] [pandas] "groupby" is:answer score:10

# Search within answers
inquestion:12345678 "performance"
```

---

## 3. Source Evaluation & Credibility

Not all sources are equal. Use systematic evaluation to assess reliability.

### The CRAAP Test

Evaluate every source against five criteria:

| Criterion | Questions to Ask | Red Flags |
|-----------|-----------------|-----------|
| **Currency** | When was it published/updated? | No date, >2 years old for tech |
| **Relevance** | Does it address your question directly? | Tangential, different context |
| **Authority** | Who wrote it? What are their credentials? | Anonymous, no bio, no org |
| **Accuracy** | Is it supported by evidence? Can you verify? | No sources, contradicts consensus |
| **Purpose** | Why does this exist? Inform, sell, persuade? | Affiliate links, vendor bias |

### Source Tier Classification

```
Tier 1 (Highest trust):
  - Official documentation (docs.python.org, react.dev)
  - Peer-reviewed papers (arXiv with citations, IEEE, ACM)
  - RFCs and specifications (IETF, W3C, ECMA)

Tier 2 (High trust):
  - Established tech blogs (engineering.fb.com, netflixtechblog.com)
  - Reputable publishers (O'Reilly, Pragmatic, Manning)
  - Conference talks with proceedings (PyCon, JSConf, KubeCon)

Tier 3 (Moderate trust):
  - Well-maintained GitHub repos (high stars, recent commits)
  - Stack Overflow accepted answers (high votes)
  - Curated community resources (awesome-* lists)

Tier 4 (Verify independently):
  - Personal blogs and Medium articles
  - Social media posts and forum discussions
  - AI-generated content without citations
```

### Vendor Bias Detection

When evaluating vendor-produced content:
- Check if the conclusion always favors their product
- Look for "compared to" sections that use outdated competitor versions
- Verify benchmark methodology and reproducibility
- Cross-reference with independent reviews

---

## 4. Multi-Source Triangulation

Never rely on a single source. Cross-reference to build confidence.

### Triangulation Strategy

```
Claim: "Framework X is 3x faster than Framework Y"

Source 1: Official benchmark (vendor) → Check methodology
Source 2: Independent benchmark (third party) → Compare results
Source 3: Community experience (GitHub issues, forums) → Real-world validation

Confidence Assessment:
  - All 3 agree → High confidence
  - 2 of 3 agree → Medium confidence, note discrepancy
  - All disagree → Low confidence, report range of findings
```

### Contradiction Resolution

When sources disagree:
1. Check dates — newer information may supersede older
2. Check context — benchmarks may use different configurations
3. Check methodology — different test conditions produce different results
4. Report all findings with context rather than picking a "winner"

---

## 5. Academic & Technical Research

Leverage academic databases for rigorous, peer-reviewed information.

### Key Academic Sources

| Database | URL | Best For |
|----------|-----|----------|
| arXiv | arxiv.org | CS, ML, physics preprints |
| Google Scholar | scholar.google.com | Cross-discipline papers |
| Semantic Scholar | semanticscholar.org | AI-powered paper discovery |
| ACM Digital Library | dl.acm.org | Computer science papers |
| IEEE Xplore | ieeexplore.ieee.org | Engineering & CS papers |
| DBLP | dblp.uni-trier.de | CS bibliography |

### Searching arXiv Programmatically

```python
import arxiv

client = arxiv.Client()

# Search for recent papers on a topic
search = arxiv.Search(
    query="CRDT collaborative editing",
    max_results=10,
    sort_by=arxiv.SortCriterion.SubmittedDate
)

for result in client.results(search):
    print(f"Title: {result.title}")
    print(f"Authors: {', '.join(a.name for a in result.authors)}")
    print(f"Published: {result.published.strftime('%Y-%m-%d')}")
    print(f"URL: {result.entry_id}")
    print(f"Summary: {result.summary[:200]}...")
    print("---")
```

### Reading Papers Efficiently

Use the **IMRAD** method for scanning papers:
1. **Introduction** — What problem does it solve?
2. **Methods** — How did they approach it?
3. **Results** — What did they find?
4. **Discussion** — What does it mean? What are limitations?

Focus on the abstract, figures, and conclusion first. Only deep-dive into methodology if the paper is directly relevant.

---

## 6. API Documentation Research

Evaluating APIs and their documentation quality.

### API Documentation Checklist

Before recommending an API, verify:
- **Authentication**: Clear docs on auth flow (API key, OAuth, JWT)
- **Rate limits**: Documented limits and how to handle 429s
- **Versioning**: API version policy and deprecation timeline
- **Error handling**: Documented error codes with examples
- **SDKs**: Official client libraries for target languages
- **Changelog**: History of breaking changes
- **Status page**: Uptime history and incident reports

### Evaluating API Maturity

```
Level 1 — Experimental:
  No versioning, sparse docs, no SLA, breaking changes common

Level 2 — Beta:
  Versioned, basic docs, no SLA, breaking changes possible

Level 3 — Production:
  Semantic versioning, comprehensive docs, SLA, deprecation policy

Level 4 — Enterprise:
  Level 3 + dedicated support, SOC2/ISO compliance, SLA guarantees
```

### Testing APIs Before Recommending

```bash
# Quick API health check
curl -s -o /dev/null -w "%{http_code} %{time_total}s" \
  "https://api.example.com/v1/health"

# Check response structure
curl -s "https://api.example.com/v1/resource" \
  -H "Authorization: Bearer $TOKEN" | jq '.data | keys'

# Measure latency from multiple calls
for i in {1..5}; do
  curl -s -o /dev/null -w "%{time_total}\n" \
    "https://api.example.com/v1/resource"
done
```

---

## 7. Competitive Intelligence

Gather information about competing products, tools, or approaches ethically.

### Competitive Analysis Framework

```
For each competitor, document:

1. Product Overview
   - What does it do? Target audience? Pricing model?

2. Technical Stack
   - Languages, frameworks, infrastructure (check job postings, tech blogs)

3. Strengths & Weaknesses
   - Based on user reviews, GitHub issues, community feedback

4. Market Position
   - User base size, funding, growth trajectory

5. Differentiation
   - What unique value does it provide vs alternatives?
```

### Ethical Information Sources

- Public company blogs and engineering posts
- Job postings (reveal tech stack, priorities, team size)
- Open source repositories and contributions
- Conference talks and published presentations
- Product changelogs and release notes
- User reviews on G2, Capterra, Product Hunt
- SEC filings for public companies (financials, risk factors)
- Patent filings (reveals R&D direction)

### Comparison Matrix Template

```markdown
| Feature       | Tool A | Tool B | Tool C | Weight |
|--------------|--------|--------|--------|--------|
| Performance  | 4/5    | 3/5    | 5/5    | 0.25   |
| Ease of Use  | 5/5    | 4/5    | 3/5    | 0.20   |
| Documentation| 4/5    | 5/5    | 3/5    | 0.15   |
| Community    | 3/5    | 5/5    | 2/5    | 0.15   |
| Pricing      | 4/5    | 3/5    | 5/5    | 0.15   |
| Maintenance  | 4/5    | 4/5    | 3/5    | 0.10   |
| **Weighted** | **4.05** | **3.85** | **3.65** | |
```

---

## 8. Open Source Intelligence (OSINT)

Techniques for gathering publicly available information systematically.

### OSINT Categories

| Category | Sources | Use Cases |
|----------|---------|-----------|
| **Web** | Search engines, cached pages, archives | Historical data, deleted content |
| **Social** | GitHub profiles, LinkedIn, Twitter/X | Team expertise, company culture |
| **Technical** | DNS records, WHOIS, SSL certs | Infrastructure analysis |
| **Code** | Public repos, package registries | Dependency analysis, security |
| **Business** | SEC filings, press releases | Company health, strategy |

### GitHub OSINT for Tech Due Diligence

```bash
# Analyze a repository's health
gh api repos/owner/repo --jq '{
  stars: .stargazers_count,
  forks: .forks_count,
  open_issues: .open_issues_count,
  last_push: .pushed_at,
  license: .license.spdx_id,
  language: .language
}'

# Check contributor activity (bus factor)
gh api repos/owner/repo/contributors --jq '
  [.[] | {login, contributions}] | sort_by(-.contributions) | .[0:5]'

# Analyze issue response time
gh api repos/owner/repo/issues?state=closed\&per_page=10 --jq '
  [.[] | {
    number,
    created: .created_at,
    closed: .closed_at,
    days_open: (((.closed_at | fromdateiso8601) - (.created_at | fromdateiso8601)) / 86400 | floor)
  }]'
```

### Wayback Machine for Historical Research

```python
import requests

def get_snapshots(url, year="2025"):
    """Get archived snapshots of a URL from the Wayback Machine."""
    api_url = f"https://web.archive.org/cdx/search/cdx"
    params = {
        "url": url,
        "output": "json",
        "from": f"{year}0101",
        "to": f"{year}1231",
        "limit": 10
    }
    response = requests.get(api_url, params=params, timeout=10)
    response.raise_for_status()
    data = response.json()

    if len(data) <= 1:
        return []

    headers = data[0]
    return [dict(zip(headers, row)) for row in data[1:]]
```

---

## 9. Data Extraction & Structuring

Transform unstructured web data into structured, analyzable formats.

### Web Scraping with BeautifulSoup

```python
import requests
from bs4 import BeautifulSoup
import json

def extract_structured_data(url):
    """Extract JSON-LD structured data from a web page."""
    headers = {"User-Agent": "ResearchBot/1.0 (research purposes)"}
    response = requests.get(url, headers=headers, timeout=10)
    response.raise_for_status()

    soup = BeautifulSoup(response.text, "html.parser")

    # Extract JSON-LD structured data
    structured = []
    for script in soup.find_all("script", type="application/ld+json"):
        try:
            data = json.loads(script.string)
            structured.append(data)
        except json.JSONDecodeError:
            continue

    # Extract meta tags
    meta = {}
    for tag in soup.find_all("meta"):
        name = tag.get("name") or tag.get("property", "")
        content = tag.get("content", "")
        if name and content:
            meta[name] = content

    return {"structured_data": structured, "meta": meta}
```

### Converting Research to Structured Output

```python
import csv
import json
from dataclasses import dataclass, asdict
from typing import Optional

@dataclass
class ResearchFinding:
    claim: str
    source_url: str
    source_tier: int  # 1-4
    confidence: str   # high, medium, low
    date_found: str
    notes: Optional[str] = None

def export_findings(findings: list[ResearchFinding], fmt: str = "json"):
    """Export research findings in multiple formats."""
    if fmt == "json":
        return json.dumps([asdict(f) for f in findings], indent=2)

    elif fmt == "csv":
        import io
        output = io.StringIO()
        writer = csv.DictWriter(output, fieldnames=ResearchFinding.__dataclass_fields__.keys())
        writer.writeheader()
        for f in findings:
            writer.writerow(asdict(f))
        return output.getvalue()

    elif fmt == "markdown":
        lines = ["| Claim | Source | Tier | Confidence |",
                 "|-------|--------|------|------------|"]
        for f in findings:
            lines.append(f"| {f.claim} | [link]({f.source_url}) | {f.source_tier} | {f.confidence} |")
        return "\n".join(lines)
```

---

## 10. Best Practices

- **Start with a research plan** — define questions, scope, and deliverables before searching
- **Use at least 3 independent sources** for any factual claim
- **Prefer primary sources** — official docs, papers, specifications over blog summaries
- **Date-check everything** — technology information older than 2 years may be outdated
- **Track your sources** as you go — retroactively finding a URL wastes time
- **Use source tiers** to weight conflicting information
- **Search in multiple languages** when researching international tools or markets
- **Check the "About" page** of any website before trusting its content
- **Use cached/archived versions** when original pages are unavailable
- **Document your methodology** so research can be reproduced or updated
- **Set time boxes** for research phases — diminishing returns after 80% coverage
- **Distinguish facts from opinions** — label each finding explicitly
- **Test claims when possible** — run a benchmark rather than trusting someone else's
- **Save raw data** alongside your analysis — future researchers may need it

---

## 11. Anti-Patterns

- **Confirmation bias searching** — only searching for evidence that supports a predetermined conclusion. Always search for counter-evidence too
- **Single-source reliance** — basing conclusions on one blog post or one benchmark. Triangulate
- **Recency bias** — assuming newest = best. Older, battle-tested solutions may be superior
- **Authority bias** — accepting claims from famous developers without evidence. Even experts can be wrong
- **Vendor benchmark trust** — using vendor-published benchmarks without independent verification. Vendors cherry-pick favorable scenarios
- **Copy-paste research** — reporting findings without understanding them. Always verify you understand what you're reporting
- **Scope creep** — following interesting tangents instead of answering the original question. Stay focused
- **Ignoring negative results** — not reporting when something doesn't work or doesn't exist. Negative findings are valuable
- **Outdated source blindness** — citing a 2019 blog post for a 2025 technology decision without checking if information is still valid
- **Search engine bubble** — using only one search engine. Try different engines for diverse results

---

## 12. Sources & References

- https://ahrefs.com/blog/google-advanced-search-operators/ — Complete guide to Google search operators (44 advanced operators)
- https://developers.google.com/search/docs/monitor-debug/search-operators — Official Google search operators documentation
- https://info.arxiv.org/help/api/user-manual.html — arXiv API User's Manual for programmatic paper search
- https://guides.lib.uiowa.edu/c.php?g=849536&p=6077647 — University of Iowa guide on evaluating bias and disinformation online
- https://libguides.mit.edu/c.php?g=175963&p=1158594 — MIT Libraries guide on Boolean operators for database searching
- https://lukasschwab.me/arxiv.py/arxiv.html — arxiv.py Python library documentation for arXiv API
- https://docs.github.com/en/search-github — GitHub search documentation for code and repository search
- https://cacm.acm.org/research/bias-on-the-web-2/ — Communications of the ACM research on bias in web information
- https://web.archive.org/web/ — Wayback Machine for accessing historical web snapshots
- https://webscraping.ai/faq/beautiful-soup/how-do-i-parse-and-extract-data-from-json-ld-or-structured-data-using-beautiful-soup — BeautifulSoup structured data extraction guide
