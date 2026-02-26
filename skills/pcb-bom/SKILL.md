---
name: pcb-bom
description: PCB manufacturing and BOM management -- KiCad BOM export, JLCPCB/LCSC sourcing, MPN management, Gerber review, DFM rules, and production testing
---

# PCB Manufacturing & BOM Management -- Hardware Engineer Patterns

Production-ready workflows for BOM generation from KiCad, component sourcing through JLCPCB/LCSC, Digi-Key, Mouser, and Octopart, manufacturer part number (MPN) management, cost optimization, Gerber file review, pick-and-place file generation, DFM compliance, and production testing strategies including ICT and flying probe.

## Table of Contents
1. [KiCad BOM Export with Custom Fields](#kicad-bom-export-with-custom-fields)
2. [JLCPCB BOM and CPL File Format](#jlcpcb-bom-and-cpl-file-format)
3. [Component Sourcing and MPN Management](#component-sourcing-and-mpn-management)
4. [BOM Consolidation and Cost Optimization](#bom-consolidation-and-cost-optimization)
5. [Component Lifecycle and Second-Source Qualification](#component-lifecycle-and-second-source-qualification)
6. [Gerber File Review and Verification](#gerber-file-review-and-verification)
7. [DFM Rules and PCB Stackup Selection](#dfm-rules-and-pcb-stackup-selection)
8. [Surface Finish Options and Assembly Requirements](#surface-finish-options-and-assembly-requirements)
9. [Panelization and Stencil Design](#panelization-and-stencil-design)
10. [Production Testing -- ICT and Flying Probe](#production-testing--ict-and-flying-probe)
11. [Best Practices](#best-practices)
12. [Anti-Patterns](#anti-patterns)
13. [Sources & References](#sources--references)

---

## 1. KiCad BOM Export with Custom Fields

### Setting Up Custom Fields in KiCad Schematic

KiCad 7+ supports user-defined fields on schematic symbols. For manufacturing-ready BOMs, every component should carry the following custom fields:

| Field Name       | Purpose                              | Example Value          |
|------------------|--------------------------------------|------------------------|
| `MPN`            | Manufacturer Part Number             | `RC0402FR-0710KL`     |
| `Manufacturer`   | Component manufacturer               | `Yageo`               |
| `LCSC`           | LCSC/JLCPCB part number             | `C25744`              |
| `DigiKey`        | Digi-Key ordering code               | `311-10.0KLRCT-ND`   |
| `Mouser`         | Mouser ordering code                 | `603-RC0402FR-0710KL` |
| `Tolerance`      | Component tolerance                  | `1%`                  |
| `Voltage`        | Rated voltage (caps/resistors)       | `16V`                 |
| `Package`        | Physical package size                | `0402`                |
| `DNP`            | Do Not Place flag                    | `yes` or leave blank  |
| `Alternate_MPN`  | Second-source part number            | `CRCW040210K0FKED`   |

### Exporting BOM Using KiCad Python Scripting

KiCad ships with a built-in BOM export tool accessible via **Tools > Generate BOM**. For automated pipelines, use the Python BOM plugin interface:

```python
#!/usr/bin/env python3
"""
kicad_bom_export.py -- Export KiCad schematic BOM to CSV with custom fields.
Place in KiCad BOM plugin directory or invoke via CLI.

Usage:
    python3 kicad_bom_export.py input.xml output.csv
"""

import csv
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict


def parse_kicad_xml(xml_path):
    """Parse KiCad intermediate XML netlist for BOM data."""
    tree = ET.parse(xml_path)
    root = tree.getroot()
    components = []

    for comp in root.iter("comp"):
        ref = comp.get("ref", "")
        value_el = comp.find("value")
        footprint_el = comp.find("footprint")
        fields = {}

        for field in comp.iter("field"):
            field_name = field.get("name", "")
            fields[field_name] = field.text or ""

        components.append({
            "Reference": ref,
            "Value": value_el.text if value_el is not None else "",
            "Footprint": footprint_el.text if footprint_el is not None else "",
            "MPN": fields.get("MPN", ""),
            "Manufacturer": fields.get("Manufacturer", ""),
            "LCSC": fields.get("LCSC", ""),
            "DigiKey": fields.get("DigiKey", ""),
            "Mouser": fields.get("Mouser", ""),
            "DNP": fields.get("DNP", ""),
            "Alternate_MPN": fields.get("Alternate_MPN", ""),
            "Package": fields.get("Package", ""),
        })
    return components


def consolidate_bom(components):
    """
    Merge components with identical Value + MPN + Footprint into single rows.
    Concatenate reference designators (e.g., R1, R2, R5).
    """
    groups = defaultdict(list)
    for comp in components:
        if comp["DNP"].lower() in ("yes", "true", "1"):
            continue
        key = (comp["Value"], comp["MPN"], comp["Footprint"])
        groups[key].append(comp)

    consolidated = []
    for (value, mpn, footprint), group in sorted(groups.items()):
        refs = sorted(group, key=lambda c: c["Reference"])
        ref_str = ", ".join(c["Reference"] for c in refs)
        first = group[0]
        consolidated.append({
            "Reference": ref_str,
            "Quantity": len(group),
            "Value": value,
            "Footprint": footprint,
            "MPN": mpn,
            "Manufacturer": first["Manufacturer"],
            "LCSC": first["LCSC"],
            "DigiKey": first["DigiKey"],
            "Mouser": first["Mouser"],
            "Package": first["Package"],
            "Alternate_MPN": first["Alternate_MPN"],
        })
    return consolidated


def write_csv(consolidated, output_path):
    """Write consolidated BOM to CSV."""
    fieldnames = [
        "Reference", "Quantity", "Value", "Footprint", "MPN",
        "Manufacturer", "LCSC", "DigiKey", "Mouser", "Package",
        "Alternate_MPN",
    ]
    with open(output_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(consolidated)
    print(f"Wrote {len(consolidated)} lines to {output_path}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 kicad_bom_export.py <input.xml> <output.csv>")
        sys.exit(1)

    xml_path = sys.argv[1]
    csv_path = sys.argv[2]

    components = parse_kicad_xml(xml_path)
    consolidated = consolidate_bom(components)
    write_csv(consolidated, csv_path)
```

### KiCad CLI BOM Generation (KiCad 7+)

```bash
# Generate intermediate XML netlist from schematic
kicad-cli sch export netlist --output project.xml project.kicad_sch

# Run the custom BOM script
python3 kicad_bom_export.py project.xml bom_output.csv

# Alternatively, use the built-in CSV BOM exporter
kicad-cli sch export bom --output bom_raw.csv project.kicad_sch

# Export pick-and-place (CPL) file from PCB layout
kicad-cli pcb export pos --output cpl_output.csv --format csv --units mm project.kicad_pcb

# Export Gerber files
kicad-cli pcb export gerbers --output ./gerbers/ project.kicad_pcb

# Export drill files
kicad-cli pcb export drill --output ./gerbers/ --format excellon project.kicad_pcb
```

---

## 2. JLCPCB BOM and CPL File Format

### Required BOM Format for JLCPCB SMT Assembly

JLCPCB requires a specific CSV format. The column headers must match exactly:

```csv
Comment,Designator,Footprint,LCSC Part #
10K,R1,R_0402_1005Metric,C25744
100nF,"C1, C2, C3",C_0402_1005Metric,C1525
STM32F103C8T6,U1,LQFP-48_7x7mm_P0.5mm,C8304
LED_Green,"D1, D2",LED_0402_1005Metric,C2297
4.7uF,"C4, C5",C_0402_1005Metric,C23733
AP2112K-3.3,U2,SOT-23-5,C51118
USB-C-Receptacle,J1,USB_C_Receptacle_HRO_TYPE-C-31-M-12,C165948
100uH,L1,IND_4x4mm,C281117
ESD Protection,U3,SOT-23-6,C7519
Crystal_8MHz,Y1,Crystal_SMD_3215-2Pin_3.2x1.5mm,C32346
```

### Required CPL (Pick-and-Place) Format

The CPL file tells the pick-and-place machine where to position each component:

| Column           | Description                        |
|------------------|------------------------------------|
| `Designator`     | Reference designator (R1, C1, U1) |
| `Mid X`          | X coordinate in mm                 |
| `Mid Y`          | Y coordinate in mm                 |
| `Rotation`       | Component rotation in degrees      |
| `Layer`          | `top` or `bottom`                  |

### Footprint-to-LCSC Part Mapping

Common KiCad footprints need to be mapped to LCSC basic parts for cost savings. JLCPCB categorizes parts as **Basic** (no extended fee) and **Extended** ($3 per unique extended part):

| KiCad Footprint                  | Typical LCSC Basic Part | Notes                        |
|----------------------------------|-------------------------|------------------------------|
| `R_0402_1005Metric`             | `C25744` (10K 1%)      | Most standard values basic   |
| `R_0603_1608Metric`             | `C22935` (10K 1%)      | Wider selection of values    |
| `C_0402_1005Metric`             | `C1525` (100nF 16V)    | X5R/X7R preferred            |
| `C_0603_1608Metric`             | `C14663` (100nF 50V)   | Higher voltage ratings avail |
| `LED_0402_1005Metric`           | `C2297` (Green)        | Basic color options          |
| `SOT-23`                        | Varies by function      | Many regulators available    |
| `LQFP-48_7x7mm_P0.5mm`        | `C8304` (STM32F103)    | Popular MCU, often basic     |

### CPL Rotation Offset Correction

JLCPCB often requires rotation corrections because KiCad and JLCPCB use different pin-1 orientations for certain packages. Common corrections:

| Package Type       | KiCad Rotation | JLCPCB Correction | Final Rotation |
|--------------------|----------------|--------------------|----------------|
| SOT-23             | 0              | -180               | -180           |
| QFP / LQFP        | 0              | -270               | -270           |
| SOIC-8             | 0              | -90                | -90            |
| SOT-23-5           | 0              | -180               | -180           |
| QFN                | 0              | -270               | -270           |
| USB Type-C         | 0              | Verify visually    | Varies         |

Always verify the first article or use JLCPCB's CPL preview tool before confirming a production order.

---

## 3. Component Sourcing and MPN Management

### Multi-Distributor Sourcing Strategy

A robust sourcing strategy uses at least two distributors per component. The typical hierarchy:

1. **LCSC/JLCPCB** -- Lowest cost for high-volume standard parts; limited specialty parts. Best for prototyping with JLCPCB assembly.
2. **Digi-Key** -- Widest catalog, excellent parametric search, US warehouse, fast shipping. Best for urgent NPI (New Product Introduction).
3. **Mouser** -- Similar to Digi-Key; strong European distribution. Frequently better pricing on passives at volume.
4. **Octopart** -- Aggregator that searches across all distributors. Use for price comparison and availability checks across the supply chain.
5. **Arrow / Avnet** -- For production volumes (1K+ units); direct manufacturer relationships yield better pricing.

### MPN Naming Conventions

Understanding MPN encoding saves time during part selection:

**Resistor example (Yageo RC series):**
`RC0402FR-0710KL`
- `RC` = Series
- `0402` = Package size (imperial)
- `F` = Tolerance (F = 1%)
- `R` = Packaging (R = tape & reel)
- `07` = Characteristic (standard)
- `10K` = Resistance value
- `L` = Lead-free designation

**Capacitor example (Samsung CL series):**
`CL05B104KO5NNNC`
- `CL` = Series (multilayer ceramic)
- `05` = Size code (0402 imperial)
- `B` = Dielectric (B = X7R)
- `104` = Capacitance (100nF)
- `K` = Tolerance (K = 10%)
- `O5` = Voltage (O5 = 16V)
- `NNN` = Packaging
- `C` = Lead-free

### Octopart API for Automated Sourcing

```python
#!/usr/bin/env python3
"""
bom_sourcing.py -- Query Octopart/Nexar API for BOM pricing and availability.
Requires a Nexar API key (https://nexar.com/api).

Usage:
    python3 bom_sourcing.py bom_output.csv sourced_bom.csv
"""

import csv
import json
import sys
import time
import urllib.request
import urllib.error

NEXAR_API_URL = "https://api.nexar.com/graphql"
# Set your token via environment variable or replace below
NEXAR_TOKEN = ""  # Replace with your Nexar/Octopart API token


def query_octopart(mpn, token):
    """Query Nexar/Octopart GraphQL API for a single MPN."""
    query = """
    query ($mpn: String!) {
      supSearchMpn(q: $mpn, limit: 3) {
        results {
          part {
            mpn
            manufacturer { name }
            bestDatasheet { url }
            sellers {
              company { name }
              offers {
                inventoryLevel
                prices { quantity price currency }
                moq
              }
            }
          }
        }
      }
    }
    """
    payload = json.dumps({"query": query, "variables": {"mpn": mpn}}).encode()
    req = urllib.request.Request(
        NEXAR_API_URL,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {token}",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        print(f"  API error for {mpn}: {e.code}")
        return None


def find_best_price(api_result, target_qty=100):
    """Extract best unit price at target quantity from API result."""
    if not api_result or "data" not in api_result:
        return None, None, None
    results = api_result["data"]["supSearchMpn"]["results"]
    if not results:
        return None, None, None

    best_price = float("inf")
    best_seller = None
    best_stock = 0

    for result in results:
        part = result["part"]
        for seller in part.get("sellers", []):
            for offer in seller.get("offers", []):
                stock = offer.get("inventoryLevel", 0) or 0
                for price_break in offer.get("prices", []):
                    if price_break["currency"] != "USD":
                        continue
                    qty_break = price_break["quantity"]
                    unit_price = price_break["price"]
                    if qty_break <= target_qty and unit_price < best_price:
                        best_price = unit_price
                        best_seller = seller["company"]["name"]
                        best_stock = stock

    if best_price == float("inf"):
        return None, None, None
    return best_price, best_seller, best_stock


def main():
    if len(sys.argv) != 3:
        print("Usage: python3 bom_sourcing.py <input_bom.csv> <output_bom.csv>")
        sys.exit(1)

    input_csv = sys.argv[1]
    output_csv = sys.argv[2]

    with open(input_csv, "r") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    print(f"Querying pricing for {len(rows)} BOM lines...")
    for row in rows:
        mpn = row.get("MPN", "")
        if not mpn:
            row["Unit_Price_USD"] = ""
            row["Best_Seller"] = ""
            row["Stock"] = ""
            continue

        print(f"  Querying: {mpn}")
        result = query_octopart(mpn, NEXAR_TOKEN)
        price, seller, stock = find_best_price(result, target_qty=100)
        row["Unit_Price_USD"] = f"{price:.4f}" if price else "N/A"
        row["Best_Seller"] = seller or "N/A"
        row["Stock"] = str(stock) if stock else "N/A"
        time.sleep(0.5)  # Rate limiting

    fieldnames = list(rows[0].keys())
    with open(output_csv, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote sourced BOM to {output_csv}")


if __name__ == "__main__":
    main()
```

---

## 4. BOM Consolidation and Cost Optimization

### Consolidation Rules

BOM consolidation reduces the number of unique line items by merging rows that share the same value, MPN, and footprint. This directly reduces:

- **Extended part fees** on JLCPCB ($3 per unique extended part).
- **Setup time** at the assembly house (fewer unique feeder slots).
- **Procurement overhead** (fewer purchase orders).

Steps for effective consolidation:

1. **Standardize resistance/capacitance values** -- Prefer E24 series values (1.0, 1.2, 1.5, ..., 8.2) over arbitrary values. If a design calls for 9.76K, evaluate whether 10K with 1% tolerance meets the requirement.
2. **Unify package sizes** -- If possible, use a single passive size throughout the design (e.g., 0402 for all resistors and small caps). This reduces feeder changes.
3. **Merge duplicate values** -- Components with identical Value + MPN + Footprint must be on a single BOM row with concatenated reference designators.
4. **Flag DNP components** -- Components marked Do Not Place should be excluded from the assembly BOM but retained in the full engineering BOM.

### Cost-Per-Board Calculation

```
Total Board Cost = PCB Fabrication + Component Cost + Assembly Cost + Shipping + Testing

Where:
  Component Cost = SUM(unit_price_i * quantity_i) for all BOM lines
  Assembly Cost  = Setup Fee + (per-component-fee * total_placements) + extended_part_fees
  PCB Fabrication = base_price(layer_count, area, qty) + surface_finish_surcharge
```

Example breakdown for a 4-layer, 50x50mm board at 100 units (JLCPCB):

| Cost Element            | Per Board  | Total (100 pcs) |
|-------------------------|------------|-----------------|
| PCB Fabrication (4L)    | $0.82      | $82.00          |
| Components (45 unique)  | $2.15      | $215.00         |
| SMT Assembly            | $0.48      | $48.00          |
| Extended Part Fees (8)  | $0.24      | $24.00          |
| Stencil                 | $0.15      | $15.00          |
| Shipping (DHL)          | $0.35      | $35.00          |
| **Total**               | **$4.19**  | **$419.00**     |

### Lead Time Tracking

Track lead times for every component in the BOM. A single long-lead-time part can delay an entire production run:

| Risk Level   | Lead Time       | Action Required                          |
|--------------|-----------------|------------------------------------------|
| Low          | In stock / <7d  | No action; order normally                |
| Medium       | 7-28 days       | Pre-order; consider safety stock         |
| High         | 28-90 days      | Qualify alternate immediately            |
| Critical     | >90 days / NRND | Redesign with available alternate        |

---

## 5. Component Lifecycle and Second-Source Qualification

### Lifecycle Status Categories

Component lifecycle stages per IPC/JEDEC standards:

| Status              | Meaning                                  | Action                                    |
|---------------------|------------------------------------------|-------------------------------------------|
| **Active**          | In full production                       | Safe to design in                         |
| **NRND**            | Not Recommended for New Designs          | Use existing stock; find alternate         |
| **Last Time Buy**   | Final order window open                  | Place lifetime buy or switch now           |
| **Obsolete**        | No longer manufactured                   | Must replace immediately                  |
| **EOL Announced**   | End-of-life date published               | Begin qualification of replacement         |

### Second-Source Qualification Workflow

1. **Identify electrical equivalence** -- Same key specs (voltage, current, tolerance, package, pinout).
2. **Check footprint compatibility** -- The alternate must share the same land pattern. Even within the same nominal package (e.g., SOT-23), different manufacturers may have slightly different pad recommendations.
3. **Verify thermal characteristics** -- Derating curves, junction-to-ambient thermal resistance, and operating temperature range must meet design requirements.
4. **Test on prototype** -- Build at least 5 units with the alternate component. Run full functional and environmental tests.
5. **Update BOM** -- Add the alternate MPN to the `Alternate_MPN` field. Document qualification results.
6. **Communicate to CM** -- Notify the contract manufacturer that both primary and alternate MPNs are approved.

### Monitoring Tools

- **Octopart Alerts** -- Set lifecycle and stock alerts for every MPN in your BOM.
- **SiliconExpert** -- Enterprise-grade component lifecycle and compliance monitoring (RoHS, REACH, conflict minerals).
- **Z2Data** -- Supply chain risk analytics with geographic risk assessment.
- **IHS Markit (now part of S&P Global)** -- Predictive obsolescence data.

---

## 6. Gerber File Review and Verification

### Standard Gerber File Set

A complete Gerber package for a 4-layer PCB consists of:

| File             | Layer                        | Extension (KiCad) |
|------------------|------------------------------|--------------------|
| Front Copper     | Top signal layer             | `.F_Cu.gtl`       |
| Inner 1          | First inner copper           | `.In1_Cu.g2`      |
| Inner 2          | Second inner copper          | `.In2_Cu.g3`      |
| Back Copper      | Bottom signal layer          | `.B_Cu.gbl`       |
| Front Solder Mask| Top solder mask              | `.F_Mask.gts`     |
| Back Solder Mask | Bottom solder mask           | `.B_Mask.gbs`     |
| Front Silkscreen | Top silkscreen               | `.F_SilkS.gto`   |
| Back Silkscreen  | Bottom silkscreen            | `.B_SilkS.gbo`   |
| Front Paste      | Top solder paste stencil     | `.F_Paste.gtp`    |
| Back Paste       | Bottom solder paste stencil  | `.B_Paste.gbp`    |
| Edge Cuts        | Board outline                | `.Edge_Cuts.gm1`  |
| Drill (PTH)      | Plated through-hole drill    | `.drl`            |
| Drill (NPTH)     | Non-plated through-hole drill| `-NPTH.drl`       |

### Gerber Viewer Verification Checklist

Before submitting to any fabrication house, verify the following in a Gerber viewer (KiCad's built-in Gerber viewer, gerbv, or an online viewer):

1. **Board outline** -- Edge Cuts layer forms a closed polygon. No gaps or overlapping segments.
2. **Copper layers alignment** -- Zoom into vias and pads to confirm all layers register correctly.
3. **Solder mask openings** -- Mask openings are slightly larger than pads (typically 0.05mm expansion per side).
4. **Silkscreen clearance** -- No silkscreen overlapping exposed copper pads. Text is readable and correctly oriented.
5. **Paste layer** -- Paste openings match pad shapes. For QFN thermal pads, verify paste is subdivided into a grid pattern (typically 50-70% paste coverage).
6. **Drill file** -- Verify hole counts match schematic (all through-hole components, mounting holes, vias). Check plated vs. non-plated designation.
7. **Board dimensions** -- Measure board outline against mechanical drawings.
8. **Fiducials** -- If using automated assembly, verify at least 3 fiducial markers are present on the board (2 global + 1 local per fine-pitch IC).
9. **Copper pour** -- No isolated copper islands (antenna effects). Ground pours are properly connected.
10. **Keepout zones** -- Antenna areas, high-voltage clearances, and mechanical exclusion zones are respected.

---

## 7. DFM Rules and PCB Stackup Selection

### JLCPCB and PCBWay DFM Constraints

| Parameter                    | JLCPCB Standard     | JLCPCB Advanced     | PCBWay Standard     | IPC Class 2       | IPC Class 3       |
|------------------------------|----------------------|----------------------|---------------------|--------------------|--------------------|
| Min trace width              | 0.127mm (5 mil)     | 0.09mm (3.5 mil)    | 0.1mm (4 mil)      | 0.1mm             | 0.075mm           |
| Min trace spacing            | 0.127mm (5 mil)     | 0.09mm (3.5 mil)    | 0.1mm (4 mil)      | 0.1mm             | 0.075mm           |
| Min via drill                | 0.3mm               | 0.15mm               | 0.2mm              | 0.25mm            | 0.2mm             |
| Min via annular ring         | 0.15mm              | 0.1mm                | 0.15mm             | 0.125mm           | 0.1mm             |
| Min hole-to-hole             | 0.254mm             | 0.2mm                | 0.25mm             | 0.25mm            | 0.2mm             |
| Min copper-to-edge           | 0.3mm               | 0.2mm                | 0.25mm             | 0.25mm            | 0.25mm            |
| Min solder mask dam          | 0.1mm               | 0.075mm              | 0.1mm              | 0.1mm             | 0.075mm           |
| Board thickness tolerance    | +/- 10%             | +/- 10%              | +/- 10%            | +/- 10%           | +/- 8%            |

### IPC Class 2 vs. Class 3

- **IPC Class 2 (Dedicated Service Electronics)** -- Standard for consumer electronics, industrial equipment, and most commercial products. Allows minor cosmetic defects that do not affect reliability. This is the default for JLCPCB and most low-cost fabricators.
- **IPC Class 3 (High Reliability Electronics)** -- Required for medical devices, aerospace, military, and automotive safety-critical systems. Tighter tolerances, stricter inspection criteria, and zero tolerance for cosmetic defects. Expect 2-5x cost increase.

### Standard PCB Stackup Configurations

**2-Layer Stackup (low complexity):**
```
Layer 1: Signal (Top)
         FR-4 Core (1.6mm typical)
Layer 2: Signal (Bottom)
```

**4-Layer Stackup (recommended for most designs):**
```
Layer 1: Signal + Components (Top)
         Prepreg (0.2mm)
Layer 2: Ground Plane (GND)
         FR-4 Core (0.8mm)
Layer 3: Power Plane (VCC)
         Prepreg (0.2mm)
Layer 4: Signal + Components (Bottom)

Total: ~1.6mm
Impedance: ~50 ohm single-ended (trace width ~0.15mm on prepreg)
```

**6-Layer Stackup (high-speed / dense):**
```
Layer 1: Signal (Top)
         Prepreg (0.1mm)
Layer 2: Ground Plane
         Core (0.3mm)
Layer 3: Signal (Inner 1)
         Prepreg (0.4mm)
Layer 4: Signal (Inner 2)
         Core (0.3mm)
Layer 5: Power Plane
         Prepreg (0.1mm)
Layer 6: Signal (Bottom)

Total: ~1.6mm
```

### Impedance Control

For controlled-impedance traces (USB, Ethernet, RF), specify impedance requirements in the fabrication notes:

| Signal Type           | Target Impedance | Trace Width (4L, 0.2mm prepreg) | Pair Spacing |
|-----------------------|------------------|---------------------------------|--------------|
| USB 2.0 Differential | 90 ohm diff      | 0.15mm                          | 0.15mm       |
| USB 3.0 Differential | 90 ohm diff      | 0.12mm                          | 0.18mm       |
| Ethernet 100BASE-TX  | 100 ohm diff     | 0.12mm                          | 0.2mm        |
| Single-ended (GPIO)  | 50 ohm SE        | 0.15mm                          | N/A          |
| LVDS                  | 100 ohm diff     | 0.1mm                           | 0.15mm       |

---

## 8. Surface Finish Options and Assembly Requirements

### Surface Finish Comparison

| Finish   | Full Name                              | Shelf Life | Cost    | Lead-Free | Fine Pitch | Notes                                      |
|----------|----------------------------------------|------------|---------|-----------|------------|---------------------------------------------|
| **HASL** | Hot Air Solder Leveling                | 12 months  | Lowest  | No*       | Poor       | Uneven surface; not for BGA or QFN          |
| **LF-HASL** | Lead-Free HASL                     | 12 months  | Low     | Yes       | Poor       | Higher temps may warp thin boards           |
| **ENIG** | Electroless Nickel Immersion Gold      | 12 months  | Medium  | Yes       | Excellent  | Best for BGA, QFN; risk of black pad       |
| **OSP**  | Organic Solderability Preservative     | 6 months   | Lowest  | Yes       | Good       | Short shelf life; single reflow only        |
| **Imm Sn** | Immersion Tin                       | 6 months   | Low     | Yes       | Good       | Tin whisker risk; handle with gloves        |
| **Imm Ag** | Immersion Silver                    | 6 months   | Medium  | Yes       | Good       | Tarnishes easily; store in sealed bags      |
| **ENEPIG**| Electroless Nickel Electroless Palladium Immersion Gold | 12 months | High | Yes | Excellent | Best for wire bonding + soldering combo |
| **Hard Gold** | Electrolytic Hard Gold             | 24 months  | Highest | Yes       | Good       | For edge connectors and high-wear contacts  |

**Recommendation by application:**
- **Prototyping** -- LF-HASL or OSP (lowest cost).
- **Consumer electronics** -- ENIG (reliable, good shelf life, fine-pitch compatible).
- **Mixed assembly (BGA + connector)** -- ENIG or ENEPIG.
- **Edge connectors (PCIe, memory slots)** -- Hard Gold on connector fingers, ENIG elsewhere.

### Assembly House Requirements Checklist

When submitting to a contract manufacturer (CM) for assembly, provide:

1. **Gerber files** -- Complete set with drill files (see Section 6).
2. **BOM** -- CSV format with Reference, Quantity, Value, MPN, and distributor part numbers.
3. **CPL / Pick-and-Place file** -- Designator, X, Y, Rotation, Layer.
4. **Assembly drawings** -- PDF showing component placement, polarity markers, pin-1 indicators.
5. **Special instructions** -- Conformal coating areas, selective soldering requirements, hand-solder exceptions.
6. **Test requirements** -- ICT fixtures, functional test procedures, acceptance criteria.
7. **Approved vendor list (AVL)** -- If alternates are allowed, document which MPNs are pre-qualified.

---

## 9. Panelization and Stencil Design

### Panel Design Guidelines

Panelization groups multiple PCBs into a single panel for efficient fabrication and assembly:

- **V-score** -- Straight-line scoring for rectangular boards. Minimum board dimension 50mm. Score depth typically 1/3 board thickness from each side. Not suitable for boards with components near the edge (<3mm).
- **Tab routing (mouse bites)** -- Routed separation with perforated tabs (0.5mm holes at 0.8mm pitch). Better for irregular shapes. Leaves small nubs on the board edge that may require filing.
- **Breakaway rails** -- Add 5mm rails on two or four sides of the panel for conveyor handling in SMT lines. Include tooling holes (diameter 2.0mm or 3.0mm) at panel corners.
- **Fiducials on rails** -- Place panel-level fiducial markers on the breakaway rails (not on the individual PCBs) for panel alignment.

**Standard panel sizes for JLCPCB assembly:**
- Maximum panel size: 380mm x 250mm
- Minimum individual PCB size: 15mm x 15mm (for SMT assembly)
- Rail width: 5mm minimum
- Tooling hole diameter: 2.0mm standard

### Stencil Design for Solder Paste

Solder paste stencils are laser-cut from stainless steel sheets. Key parameters:

| Parameter              | Standard         | Fine Pitch (< 0.5mm) | BGA/QFN Pads        |
|------------------------|------------------|-----------------------|----------------------|
| Stencil thickness      | 0.12mm (5 mil)   | 0.10mm (4 mil)        | 0.10mm (4 mil)      |
| Aperture-to-pad ratio  | 1:1              | 0.9:1 to 0.95:1      | 0.8:1 to 0.9:1      |
| Aspect ratio (W/T)     | > 1.5            | > 1.5                 | > 1.5               |
| Area ratio (A_pad/A_wall) | > 0.66        | > 0.66                | > 0.66              |

**QFN thermal pad stencil design:**
- Never use a single large aperture for QFN exposed pads -- this causes solder voiding and component floating.
- Subdivide into a grid of smaller rectangles with 0.3-0.5mm gaps.
- Target 50-70% paste coverage of the total pad area.
- Example: A 3x3mm thermal pad might use a 3x3 grid of 0.8mm x 0.8mm apertures.

### Stencil Ordering Notes

- **Framed stencils** -- Used in production SMT lines. Mounted in a frame (typically 450mm x 550mm or 550mm x 650mm). Required for high-volume assembly.
- **Frameless stencils** -- Lower cost, suitable for prototyping and manual stencil printing. Use with a stencil jig or manual alignment frame.
- JLCPCB provides a free stencil with assembly orders. Standalone stencil orders cost approximately $6-15 depending on size.

---

## 10. Production Testing -- ICT and Flying Probe

### In-Circuit Test (ICT)

ICT uses a bed-of-nails fixture to make electrical contact with test points on the assembled PCB. It is the fastest method for high-volume production testing.

**What ICT Tests:**
- Open and short circuits
- Resistor, capacitor, and inductor values
- Diode polarity and forward voltage
- Transistor gain
- IC presence (boundary scan / JTAG)
- Solder joint integrity

**ICT Design Guidelines:**
- Place test points on the bottom side of the board where possible (fixture pins press up from below).
- Minimum test point pad diameter: 1.0mm (0.9mm for high-density).
- Minimum test point spacing (center-to-center): 2.3mm (IPC standard) or 1.8mm (high-density fixtures).
- Every net that requires testing must have a dedicated test point. Do not rely on component pads alone.
- Keep test points at least 2mm from board edges and 1mm from other components.

**Cost considerations:**
- ICT fixture cost: $1,000 - $10,000+ depending on board complexity and fixture vendor.
- Amortized over production volume. Not economical for runs under 500 units.
- Test time per board: 5-30 seconds typical.

### Flying Probe Test

Flying probe testers use motorized probes that move to test points without a custom fixture. Ideal for prototyping and low-to-mid volume production.

**Advantages over ICT:**
- No fixture cost (setup is software-only).
- Quick changeover between board designs.
- Can reach test points with tighter spacing (probes are more precise than bed-of-nails pins).

**Disadvantages:**
- Slower than ICT (30 seconds to several minutes per board depending on test count).
- Limited to electrical tests (no powered functional testing).
- Higher per-unit test cost at volume.

**When to use which:**

| Production Volume | Recommended Test   | Reasoning                                |
|-------------------|--------------------|------------------------------------------|
| < 100 units       | Flying Probe       | No fixture cost; fast setup              |
| 100 - 500 units   | Flying Probe or ICT| Evaluate fixture amortization vs. unit cost |
| 500 - 5,000 units | ICT                | Fixture cost amortized; faster throughput |
| > 5,000 units     | ICT + Functional   | Full test coverage; maximize yield       |

### Functional Test (FCT)

Beyond ICT/flying probe, functional testing powers the board and verifies system-level behavior:

- Power supply voltage and current consumption within specification.
- Communication interfaces operational (UART, SPI, I2C, USB, Ethernet).
- Sensor readings within calibration range.
- LED indicators and display output correct.
- Firmware flash and boot verification.
- RF output power and sensitivity (for wireless products).

Functional test fixtures and software are custom per product. Budget 2-8 weeks for test development on a new product.

---

## 11. Best Practices

1. **Always assign MPNs at schematic capture time** -- Do not defer component selection to layout or procurement. Every symbol should have MPN, Manufacturer, LCSC, and Package fields populated before PCB layout begins.

2. **Use a single source of truth for the BOM** -- The KiCad schematic is the master. All BOM exports should be generated from the schematic, not maintained in a separate spreadsheet. If pricing or sourcing data is needed, augment the export programmatically (see Section 3).

3. **Standardize on the E24/E96 value series** -- Reduce unique BOM lines by using standard resistance and capacitance values. Consolidation reduces cost and simplifies procurement.

4. **Design with LCSC basic parts whenever possible** -- JLCPCB charges $3 per unique extended part. Designing around basic parts saves significant money at prototype volumes.

5. **Include second sources for every critical component** -- Any IC, connector, or specialty part should have at least one qualified alternate in the BOM. Passives with standard values from multiple manufacturers are inherently multi-sourced.

6. **Run DRC and DFM checks before every Gerber export** -- KiCad's DRC catches electrical and spacing violations. Additionally, upload Gerbers to the fab house's online DFM checker before ordering.

7. **Version control your KiCad project and BOM outputs** -- Use Git to track schematic, layout, BOM, and Gerber files. Tag releases corresponding to each fabrication order.

8. **Verify Gerbers in an independent viewer** -- Never trust the PCB editor's screen output alone. Open Gerbers in KiCad's Gerber viewer, gerbv, or an online viewer and walk through the verification checklist (Section 6).

9. **Design test points into the PCB from the start** -- Adding test points after layout is difficult. Plan ICT or flying probe access during schematic and layout phases.

10. **Maintain a component lifecycle watchlist** -- Set up automated alerts via Octopart or SiliconExpert for NRND and EOL notifications on every MPN in your active BOMs.

11. **Document stackup and impedance requirements in fab notes** -- Do not assume the fabricator will guess your impedance requirements. Include a stackup drawing and impedance table in the fabrication package.

12. **Use thermal relief on ground plane connections** -- Pads connected to large copper pours should use thermal relief patterns to ensure solderability. Direct connections to ground planes act as heat sinks and cause cold solder joints.

---

## 12. Anti-Patterns

1. **Maintaining the BOM in a standalone spreadsheet** -- Disconnecting the BOM from the schematic leads to version drift. Component values change in the schematic but not in the spreadsheet, causing wrong parts to be ordered. Always generate the BOM from the schematic.

2. **Using generic part numbers instead of specific MPNs** -- Specifying "10K 0402 resistor" without an MPN allows the assembly house to substitute any part, potentially with incompatible tolerance, power rating, or temperature coefficient.

3. **Ignoring the DNP field** -- Components intended for optional features or debugging must be marked DNP. Failing to do so results in unnecessary assembly costs and potential functional issues from populated debug headers.

4. **Skipping Gerber review** -- Trusting the PCB editor's output without independent Gerber verification leads to missing layers, incorrect drill files, or misaligned solder mask. Fabrication houses work from Gerbers, not from native KiCad files.

5. **Designing with obsolete or NRND parts** -- Starting a new design with a component that is already in lifecycle decline guarantees a future redesign. Always check lifecycle status before selecting a part.

6. **Using HASL finish for BGA or fine-pitch components** -- HASL produces an uneven surface that prevents reliable solder joint formation on BGA and QFN packages. Use ENIG or OSP for fine-pitch work.

7. **Single-source critical components** -- Relying on a single manufacturer or distributor for a key IC creates supply chain risk. If that part goes on allocation, the entire product is blocked.

8. **Ignoring CPL rotation offsets** -- KiCad and JLCPCB use different rotation conventions for many packages. Submitting uncorrected CPL files results in components placed at wrong orientations, requiring manual rework or scrapping the entire batch.

9. **No test points in the design** -- Omitting test points makes production testing impossible or forces expensive functional-test-only strategies. Every net that needs verification must have a dedicated, accessible test point.

10. **Over-specifying PCB class** -- Requesting IPC Class 3 fabrication for a consumer product wastes money (2-5x cost increase) without meaningful reliability benefit. Match the IPC class to the actual product reliability requirement.

11. **Large QFN thermal pad without stencil subdivision** -- Using a single stencil aperture for QFN exposed pads causes excessive solder paste, leading to voiding, tombstoning, and component floating during reflow.

12. **Panelizing without assembly house consultation** -- Different assembly houses have different panel size limits, rail width requirements, and tooling hole specifications. Always confirm panel requirements with the CM before finalizing panel design.

---

## 13. Sources & References

- KiCad Official Documentation -- BOM Export and Custom Fields: [https://docs.kicad.org/7.0/en/eeschema/eeschema.html#generating_a_bill_of_materials](https://docs.kicad.org/7.0/en/eeschema/eeschema.html#generating_a_bill_of_materials)
- JLCPCB SMT Assembly Guide -- BOM and CPL File Requirements: [https://jlcpcb.com/help/article/how-to-generate-the-bom-and-centroid-file-from-kicad](https://jlcpcb.com/help/article/how-to-generate-the-bom-and-centroid-file-from-kicad)
- JLCPCB PCB Capabilities -- DFM Specifications and Constraints: [https://jlcpcb.com/capabilities/pcb-capabilities](https://jlcpcb.com/capabilities/pcb-capabilities)
- Nexar (Octopart) API Documentation -- Component Search and Pricing: [https://nexar.com/api](https://nexar.com/api)
- IPC-A-610 -- Acceptability of Electronic Assemblies (Class 2 and Class 3 Criteria): [https://www.ipc.org/TOC/IPC-A-610H.pdf](https://www.ipc.org/TOC/IPC-A-610H.pdf)
- IPC-7351 -- Generic Requirements for Surface Mount Land Pattern Design: [https://www.ipc.org/TOC/IPC-7351C.pdf](https://www.ipc.org/TOC/IPC-7351C.pdf)
- PCBWay DFM and Manufacturing Capabilities: [https://www.pcbway.com/capabilities.html](https://www.pcbway.com/capabilities.html)
- Digi-Key BOM Manager and Component Sourcing Tools: [https://www.digikey.com/en/resources/bom-manager](https://www.digikey.com/en/resources/bom-manager)
- SiliconExpert Component Lifecycle and Risk Management: [https://www.siliconexpert.com/](https://www.siliconexpert.com/)
- KiCad CLI Reference (KiCad 7+): [https://docs.kicad.org/7.0/en/cli/cli.html](https://docs.kicad.org/7.0/en/cli/cli.html)
