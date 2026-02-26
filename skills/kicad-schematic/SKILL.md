---
name: kicad-schematic
description: KiCad 8.x schematic capture, PCB layout, symbol/footprint library management, hierarchical sheets, ERC/DRC, Gerber export, BOM generation, and KiCad Python scripting for hardware design workflows
---

# KiCad Schematic & PCB Design -- Hardware Engineer Patterns

Production-quality patterns for schematic capture, PCB layout, manufacturing output, and automation using KiCad 8.x. Covers the full design flow from project creation through Gerber export, including library management, design rule configuration for common fabrication houses, and scripting with the KiCad Python API.

## Table of Contents
1. [Project Setup and File Structure](#project-setup-and-file-structure)
2. [Symbol Library Management](#symbol-library-management)
3. [Schematic Capture and Hierarchical Sheets](#schematic-capture-and-hierarchical-sheets)
4. [Net Labels, Power Flags, and Global Connections](#net-labels-power-flags-and-global-connections)
5. [Electrical Rules Check (ERC)](#electrical-rules-check-erc)
6. [Footprint Assignment and Footprint Editor](#footprint-assignment-and-footprint-editor)
7. [PCB Layout and Copper Zones](#pcb-layout-and-copper-zones)
8. [Trace Width Calculation and Via Sizing](#trace-width-calculation-and-via-sizing)
9. [Design Rules Check (DRC) and Manufacturer Constraints](#design-rules-check-drc-and-manufacturer-constraints)
10. [Gerber, Drill, and Pick-and-Place Export](#gerber-drill-and-pick-and-place-export)
11. [BOM Export and Plugins](#bom-export-and-plugins)
12. [3D Model Viewer and STEP Export](#3d-model-viewer-and-step-export)
13. [KiCad CLI Tools](#kicad-cli-tools)
14. [KiCad Python Scripting API](#kicad-python-scripting-api)
15. [Version Control with KiCad Files](#version-control-with-kicad-files)
16. [Best Practices](#best-practices)
17. [Anti-Patterns](#anti-patterns)
18. [Sources & References](#sources--references)

---

## 1. Project Setup and File Structure

A KiCad 8.x project is anchored by a `.kicad_pro` file (JSON format) that references the schematic (`.kicad_sch`), PCB layout (`.kicad_pcb`), and project-local settings. Understanding the file structure is essential for both manual management and CI/CD automation.

### Core Project Files

| File | Purpose |
|------|---------|
| `project.kicad_pro` | Project settings, library table overrides, text variables |
| `project.kicad_sch` | Root schematic sheet (S-expression format) |
| `project.kicad_pcb` | PCB layout (S-expression format) |
| `project.kicad_prl` | Local preferences (window positions, layer visibility) |
| `fp-lib-table` | Project-local footprint library table |
| `sym-lib-table` | Project-local symbol library table |
| `*.kicad_dru` | Custom design rules (constraint language) |

### Creating a New Project from CLI

```bash
# Create project directory structure
mkdir -p ~/kicad-projects/power-supply
cd ~/kicad-projects/power-supply

# KiCad 8.x CLI can generate a new project skeleton
kicad-cli project create --name "power-supply" .

# Resulting files:
# power-supply.kicad_pro
# power-supply.kicad_sch
# power-supply.kicad_pcb

# Optionally create local library directories
mkdir -p libraries/symbols libraries/footprints libraries/3dmodels

# Add project-local symbol library table
cat > sym-lib-table <<'EOF'
(sym_lib_table
  (version 7)
  (lib (name "project-symbols")(type "KiCad")(uri "${KIPRJMOD}/libraries/symbols/project-symbols.kicad_sym")(options "")(descr "Project-local symbols"))
)
EOF

# Add project-local footprint library table
cat > fp-lib-table <<'EOF'
(fp_lib_table
  (version 7)
  (lib (name "project-footprints")(type "KiCad")(uri "${KIPRJMOD}/libraries/footprints/project-footprints.pretty")(options "")(descr "Project-local footprints"))
)
EOF
```

### Text Variables

Text variables defined in the `.kicad_pro` file are accessible throughout the schematic and PCB. They are commonly used for revision numbers, dates, and project metadata:

```json
{
  "text_variables": {
    "REVISION": "1.2",
    "COMPANY": "Acme Electronics",
    "DATE": "2026-02-26",
    "ENGINEER": "J. Smith"
  }
}
```

These can be referenced in title blocks and text fields as `${REVISION}`, `${COMPANY}`, etc.

---

## 2. Symbol Library Management

KiCad 8.x uses a two-tier library table system: a global table (`sym-lib-table` in the KiCad config directory) and a project-local table (`sym-lib-table` in the project root). Project-local libraries take precedence when names collide.

### Symbol File Format

Symbols are stored in `.kicad_sym` files using S-expression syntax. Each symbol defines:

- **Pin definitions**: name, number, electrical type (input, output, passive, power_in, power_out, bidirectional, tri_state, unspecified, open_collector, open_emitter, not_connected)
- **Graphics**: rectangles, circles, arcs, polylines, text
- **Properties**: Reference, Value, Footprint, Datasheet, plus custom fields
- **Units**: Multi-unit symbols (e.g., quad op-amp with units A through D plus a power unit)

### Creating a Custom Symbol

When creating custom symbols, follow these conventions:

- Pin 1 indicator: small dot or notch on the symbol body
- Input pins on the left, output pins on the right
- Power pins at top (VCC) and bottom (GND) when practical
- Pin length: 100 mil (2.54 mm) standard
- Grid: all pins must snap to the 50 mil (1.27 mm) grid
- Reference field: place above the symbol body
- Value field: place below the symbol body

### Pin Electrical Types and Their ERC Behavior

| Pin Type | Drives Net? | ERC Notes |
|----------|------------|-----------|
| `input` | No | Error if unconnected and no driver on the net |
| `output` | Yes | Error if two outputs on same net |
| `bidirectional` | Yes | Multiple allowed on same net |
| `tri_state` | Yes | Multiple allowed on same net |
| `passive` | No | No error if unconnected (use with caution) |
| `power_in` | No | Must have a power flag or power_out pin on the net |
| `power_out` | Yes | Drives power nets; used in power symbols |
| `open_collector` | Yes | Can share net with other open_collector/open_emitter |
| `open_emitter` | Yes | Can share net with other open_collector/open_emitter |
| `unspecified` | -- | ERC ignores; avoid in production designs |
| `not_connected` | -- | Pin is explicitly not connected |

---

## 3. Schematic Capture and Hierarchical Sheets

Hierarchical sheets allow breaking a complex design into manageable sub-circuits. KiCad 8.x supports multi-level hierarchy with proper net connectivity through hierarchical pins and labels.

### Hierarchical Sheet Structure

A hierarchical sheet in the root schematic is a reference to a child `.kicad_sch` file. The sheet symbol on the parent has hierarchical pins that map to hierarchical labels inside the child sheet.

**Parent sheet**: contains a sheet symbol with hierarchical pins (small flags on the sheet border).

**Child sheet**: contains hierarchical labels that match the pin names on the parent sheet symbol. The label names must match exactly (case-sensitive).

### Connection Types

| Method | Scope | Use Case |
|--------|-------|----------|
| Wire | Local to sheet | Direct point-to-point connection |
| Local label | Local to sheet | Connect distant points on the same sheet |
| Global label | All sheets | Signal that must be available everywhere (e.g., reset, enable) |
| Hierarchical label + pin | Parent-child | Structured inter-sheet connections |
| Power symbol | All sheets | Power rails (VCC, GND, +3V3, etc.) |

### Hierarchical Sheet Workflow

1. In the root schematic, place a hierarchical sheet symbol (`Place > Hierarchical Sheet`).
2. Assign the sheet a filename (e.g., `power_supply.kicad_sch`) and a sheet name.
3. Open the child sheet and place hierarchical labels for each signal that crosses the boundary.
4. Back in the parent, import the hierarchical pins from the child sheet to the sheet symbol.
5. Wire the hierarchical pins to nets in the parent sheet.

### Multi-Instance Sheets

KiCad 8.x supports placing the same child sheet multiple times in the parent (multi-instance). Each instance can have unique reference designators and values. This is useful for repeated sub-circuits like identical channel amplifiers.

When using multi-instance sheets, component annotations are per-instance. Run "Annotate Schematic" and select "Annotate entire schematic" to ensure unique references across all instances.

---

## 4. Net Labels, Power Flags, and Global Connections

### Net Labels

Net labels assign names to wires. Any two wires with the same local label on the same sheet are electrically connected. Labels are case-sensitive.

Naming conventions:
- Signal nets: `SPI_CLK`, `I2C_SDA`, `UART_TX`
- Bus nets: `D[0..7]`, `ADDR[0..15]` (bus syntax with square brackets)
- Active-low signals: `~{RESET}`, `~{CS}` (KiCad uses `~{}` for overbar notation)

### Power Flags

Power flags are special symbols that tell the ERC a net is intentionally driven as a power rail. Without a power flag, any net connected only to `power_in` pins will trigger an ERC error: "Pin not driven (Net has no driver)."

**When to add a power flag:**
- On any net connected to a connector pin that supplies power (e.g., USB VBUS coming from a connector).
- On any net that is a power rail but has no regulator output (`power_out` pin) on it in the current schematic scope.

**When NOT to add a power flag:**
- When a voltage regulator output pin (typed as `power_out`) is already on the net.
- On ground nets that already have a GND power symbol (KiCad's built-in GND symbol has a `power_out` pin).

### Power Symbols

KiCad's built-in power symbols (VCC, GND, +3V3, +5V, etc.) are global by nature. Placing a `+3V3` symbol on any sheet connects that point to the global `+3V3` net. Power symbols contain a single hidden `power_out` pin, which serves as both the net driver and the power flag.

### Custom Power Symbols

For non-standard rails (e.g., `+1V8_CORE`, `VBAT`), create a custom power symbol:

1. Create a new symbol with a single pin.
2. Set the pin type to `power_out`.
3. Mark the pin as hidden.
4. Set the pin name to the desired net name (e.g., `+1V8_CORE`).
5. Check the "Define as power symbol" checkbox in symbol properties.
6. Set the reference field prefix to `#PWR`.

---

## 5. Electrical Rules Check (ERC)

The ERC validates the schematic for electrical correctness. It checks pin compatibility, unconnected pins, duplicate references, missing power drivers, and more.

### Common ERC Errors and Resolutions

| Error | Cause | Resolution |
|-------|-------|------------|
| "Pin not driven" | power_in pin with no driver | Add a power flag or connect a power_out source |
| "Conflicting pin types" | Two output pins on the same net | Change one to tri_state or open_collector if appropriate |
| "Unconnected pin" | Pin left floating | Add a no-connect flag (X) or wire it |
| "Duplicate reference" | Two components with same RefDes | Re-annotate the schematic |
| "Missing power flag" | Power net without a driver | Place a `PWR_FLAG` symbol on the net |
| "Different net names" | Wire connects two differently-named labels | Resolve the naming conflict or use a net tie |
| "Pin not connected" on power pins | Hidden power pins not connected | Ensure the symbol's power pins are correctly typed |

### ERC Configuration

The ERC severity matrix can be customized per pin-type pair. In the schematic editor, go to `Inspect > Electrical Rules Checker > Options` to adjust severities. For example, you may want to downgrade the "input-to-input" warning to "ignore" when you have legitimate input-only nets (e.g., test points).

### Suppressing Individual ERC Violations

For intentional violations (e.g., a known-good configuration), you can:
- Place a "no connect" flag on intentionally unconnected pins.
- Add an ERC exclusion comment in the schematic (right-click the ERC marker > Exclude).
- Mark specific pins as `not_connected` type in the symbol.

Never suppress ERC errors globally to hide real problems. Fix the root cause first.

---

## 6. Footprint Assignment and Footprint Editor

### Footprint Assignment Workflow

After completing the schematic, assign footprints to all symbols:

1. Open the "Assign Footprints" tool (`Tools > Assign Footprints`).
2. The left pane shows available footprint libraries; the middle pane shows schematic symbols; the right pane shows footprints in the selected library.
3. Double-click a symbol to assign a footprint, or use filters to find appropriate packages.

### Footprint Naming Convention

KiCad's standard libraries follow the IPC naming convention:
- `Package_SO:SOIC-8_3.9x4.9mm_P1.27mm`
- `Package_QFP:LQFP-48_7x7mm_P0.5mm`
- `Resistor_SMD:R_0402_1005Metric`
- `Capacitor_SMD:C_0805_2012Metric`

### Custom Footprint Creation

When creating footprints in the Footprint Editor:

- Use the manufacturer's recommended land pattern (from the datasheet).
- Set the grid to match pad pitch.
- Place pads with correct shape (rectangle for pin 1, oval/round for others).
- Add courtyard on `F.Courtyard` layer (0.25 mm clearance from pads for IPC Nominal density).
- Add fabrication layer outline on `F.Fab` with component body dimensions.
- Add silkscreen on `F.SilkS` with reference designator `%R`.
- Add a 3D model path in the footprint properties using `${KICAD8_3DMODEL_DIR}` or `${KIPRJMOD}`.

### Pad Stack Configuration

| Pad Type | Use Case | Layers |
|----------|----------|--------|
| SMD | Surface mount components | Single copper layer + paste + mask |
| Through-hole | THT components | All copper layers + mask |
| NPTH | Mounting holes (non-plated) | All copper layers (no pad) |
| Via | Layer transitions | Defined copper layer pairs |

---

## 7. PCB Layout and Copper Zones

### Layer Stack Configuration

A typical 2-layer board:
- `F.Cu` -- Top copper (signal + power)
- `B.Cu` -- Bottom copper (ground plane + routing)

A typical 4-layer board:
- `F.Cu` -- Top copper (signals)
- `In1.Cu` -- Inner layer 1 (ground plane)
- `In2.Cu` -- Inner layer 2 (power plane)
- `B.Cu` -- Bottom copper (signals)

Configure the stack in `Board Setup > Board Stackup > Physical Stackup`.

### Copper Zone Fills

Copper zones (pours) are used for ground planes, power planes, and thermal management.

**Creating a ground plane:**
1. Select the copper layer (e.g., `B.Cu`).
2. Draw a zone outline (`Place > Zone`).
3. In the zone properties dialog: assign the net (e.g., `GND`), set clearance, set minimum width.
4. Set zone priority (higher number = higher priority for overlapping zones).
5. Set thermal relief or solid connection for pads.

**Zone fill settings:**
- **Clearance**: Minimum gap between the zone copper and other nets. Match your DRC clearance (e.g., 0.2 mm for JLCPCB).
- **Minimum width**: Minimum copper web width within the zone. Typically 0.2-0.25 mm.
- **Thermal relief gap**: Gap in the thermal relief spoke pattern (typically 0.3-0.5 mm).
- **Thermal relief spoke width**: Width of the spokes connecting pads to the zone (typically 0.3-0.5 mm).
- **Pad connection**: "Thermal relief" for most pads; "Solid" for high-current pads; "None" for pads that should not connect.

### Zone Priority

When two zones overlap on the same layer (e.g., a +3V3 island inside a GND plane), the zone with higher priority takes precedence. The lower-priority zone fills around the higher-priority zone with the specified clearance.

### Teardrops

KiCad 8.x supports teardrop generation for pad-to-trace and via-to-trace junctions. Enable teardrops in `Board Setup > Design Rules > Teardrops`. Teardrops improve manufacturability by reducing the risk of trace-to-pad disconnection during etching.

---

## 8. Trace Width Calculation and Via Sizing

### Trace Width for Current Capacity

Use IPC-2221 guidelines for trace width calculation. The required width depends on current, acceptable temperature rise, copper weight, and whether the trace is on an outer or inner layer.

**IPC-2221 formula (simplified):**

```
Area [mils^2] = (I / (k * dT^b))^(1/c)
Width [mils] = Area / (Thickness * 1.378)
```

Where:
- `I` = current in Amps
- `dT` = temperature rise in degrees C
- `k`, `b`, `c` = constants (outer layer: k=0.048, b=0.44, c=0.725; inner layer: k=0.024, b=0.44, c=0.725)
- `Thickness` = copper thickness in oz (1 oz = 1.378 mils = 35 um)

**Common trace widths for 1 oz copper, 10 degC rise (outer layer):**

| Current | Trace Width (mm) | Trace Width (mils) |
|---------|------------------|--------------------|
| 0.5 A | 0.25 | 10 |
| 1.0 A | 0.50 | 20 |
| 2.0 A | 1.20 | 47 |
| 3.0 A | 2.00 | 79 |
| 5.0 A | 4.50 | 177 |

For high-current paths, consider using polygon pours instead of traces.

### Via Sizing

Via current capacity depends on the via diameter, plating thickness, and barrel length (board thickness).

**Common via sizes:**

| Via Type | Drill | Annular Ring | Finished Hole | Current Capacity (approx) |
|----------|-------|--------------|---------------|---------------------------|
| Standard | 0.3 mm | 0.15 mm | 0.3 mm | ~0.5 A |
| Standard | 0.4 mm | 0.2 mm | 0.4 mm | ~1 A |
| Power | 0.6 mm | 0.25 mm | 0.6 mm | ~2 A |
| Power | 0.8 mm | 0.3 mm | 0.8 mm | ~3 A |

For high-current paths, use multiple vias in parallel. A common rule: use at least 1 via per 0.5 A.

### Impedance-Controlled Traces

For high-speed signals (USB, Ethernet, DDR), use controlled-impedance traces. Common targets:
- Single-ended: 50 ohm
- Differential (USB 2.0): 90 ohm
- Differential (Ethernet): 100 ohm

Use the manufacturer's stackup calculator (e.g., JLCPCB impedance calculator) to determine trace width and spacing for the specific stackup.

---

## 9. Design Rules Check (DRC) and Manufacturer Constraints

### JLCPCB Design Rules (Standard Process)

Configure these in `Board Setup > Design Rules > Constraints`:

| Parameter | JLCPCB Minimum | Recommended |
|-----------|---------------|-------------|
| Track width | 0.127 mm (5 mil) | 0.15-0.2 mm |
| Track spacing | 0.127 mm (5 mil) | 0.15-0.2 mm |
| Via drill | 0.3 mm (12 mil) | 0.3 mm |
| Via annular ring | 0.13 mm | 0.15 mm |
| Via diameter (pad) | 0.56 mm | 0.6 mm |
| Min hole size | 0.3 mm | 0.3 mm |
| PTH annular ring | 0.13 mm | 0.2 mm |
| NPTH to track | 0.254 mm | 0.3 mm |
| Silkscreen width | 0.15 mm | 0.2 mm |
| Silkscreen clearance | 0.15 mm | 0.2 mm |
| Board edge clearance | 0.3 mm | 0.5 mm |
| Solder mask min width | 0.1 mm | 0.15 mm |

### Custom Design Rule File (.kicad_dru)

KiCad 8.x supports a constraint scripting language for advanced DRC rules:

```
(version 1)

# Minimum clearance for all nets
(rule "Default Clearance"
  (condition "A.Type == 'track' || A.Type == 'via' || A.Type == 'pad'")
  (constraint clearance (min 0.15mm))
)

# High voltage clearance for mains-referenced nets
(rule "High Voltage Clearance"
  (condition "A.NetClass == 'HV' || B.NetClass == 'HV'")
  (constraint clearance (min 2.5mm))
)

# Wider annular ring for mounting holes
(rule "Mounting Hole Annular Ring"
  (condition "A.Pad_Type == 'NPTH, mechanical'")
  (constraint annular_width (min 0.3mm))
)

# Differential pair spacing for USB
(rule "USB Diff Pair"
  (condition "A.NetClass == 'USB' && B.NetClass == 'USB'")
  (constraint clearance (min 0.15mm))
  (constraint track_width (min 0.22mm) (max 0.22mm))
)

# Board edge keepout
(rule "Board Edge Clearance"
  (condition "A.Type == 'track' && B.Type == 'board_edge'")
  (constraint clearance (min 0.5mm))
)
```

### Net Classes

Define net classes in `Board Setup > Net Classes` to group nets with similar electrical requirements:

| Net Class | Track Width | Clearance | Via Size | Use |
|-----------|------------|-----------|----------|-----|
| Default | 0.2 mm | 0.2 mm | 0.6 mm | General signals |
| Power | 0.5 mm | 0.25 mm | 0.8 mm | Power rails |
| USB | 0.22 mm | 0.15 mm | 0.6 mm | USB diff pairs |
| HV | 0.3 mm | 2.5 mm | 0.8 mm | High voltage |

Assign nets to net classes in the schematic (right-click net > Set Net Class) or in `Board Setup > Net Classes > Net Class Assignments`.

---

## 10. Gerber, Drill, and Pick-and-Place Export

### Gerber Export Settings

Navigate to `File > Fabrication Outputs > Gerbers (.gbr)` in the PCB editor.

**Layer mapping (standard JLCPCB naming):**

| KiCad Layer | Gerber Suffix | Description |
|-------------|---------------|-------------|
| F.Cu | `-F_Cu.gbr` | Front copper |
| B.Cu | `-B_Cu.gbr` | Back copper |
| F.SilkS | `-F_Silkscreen.gbr` | Front silkscreen |
| B.SilkS | `-B_Silkscreen.gbr` | Back silkscreen |
| F.Mask | `-F_Mask.gbr` | Front solder mask |
| B.Mask | `-B_Mask.gbr` | Back solder mask |
| F.Paste | `-F_Paste.gbr` | Front solder paste |
| B.Paste | `-B_Paste.gbr` | Back solder paste |
| Edge.Cuts | `-Edge_Cuts.gbr` | Board outline |
| In1.Cu | `-In1_Cu.gbr` | Inner copper 1 (if 4+ layers) |
| In2.Cu | `-In2_Cu.gbr` | Inner copper 2 (if 4+ layers) |

**Gerber settings:**
- Format: Gerber X2 (preferred) or RS-274X (legacy compatibility)
- Coordinate format: 4.6 (unit: mm)
- Check "Use Protel filename extensions" if the manufacturer requires `.gtl`, `.gbl`, etc.
- Check "Subtract soldermask from silkscreen" to avoid silkscreen on exposed pads.

### Drill File Export

Navigate to `File > Fabrication Outputs > Drill Files (.drl)`.

**Settings:**
- Drill file format: Excellon
- Drill units: Millimeters
- Zeros format: Decimal format
- Map file format: Gerber X2 (or PostScript for visual inspection)
- Generate separate files for plated and non-plated holes.

### Pick-and-Place (Position) File

Navigate to `File > Fabrication Outputs > Component Placement (.pos)`.

**Settings:**
- Format: CSV
- Units: Millimeters
- Side: Both (or separate files for top/bottom)

The output file contains columns: Reference, Value, Package, PosX, PosY, Rotation, Side. JLCPCB expects specific column names; you may need to adjust the header or use their conversion tool.

---

## 11. BOM Export and Plugins

### Built-in BOM Export

KiCad 8.x includes a built-in BOM export in the schematic editor (`Tools > Edit Symbol Fields` for bulk editing, and `File > Export > BOM`).

### KiBOM and Interactive BOM

**KiBOM** is a popular BOM plugin that generates grouped, filtered BOMs in CSV/HTML/XML format.

**Interactive HTML BOM (ibom)** generates an interactive HTML page showing component placement overlaid on the PCB, useful for hand assembly.

Install via the KiCad Plugin and Content Manager (PCM) or manually:

```bash
# Install InteractiveHtmlBom via pip (for CLI usage)
pip install InteractiveHtmlBom

# Generate interactive BOM from command line
generate_interactive_bom \
  --dest-dir ./output \
  --include-tracks \
  --include-nets \
  --blacklist "MH*,TP*" \
  project.kicad_pcb

# KiCad 8.x built-in CLI BOM export
kicad-cli sch export bom \
  --output project_bom.csv \
  --fields "Reference,Value,Footprint,${QUANTITY},MPN,Manufacturer" \
  --group-by "Value,Footprint,MPN" \
  --sort-field "Reference" \
  project.kicad_sch
```

### JLCPCB BOM Format

JLCPCB requires a specific BOM format with these columns:
- `Comment` (component value)
- `Designator` (reference designators, comma-separated for grouped)
- `Footprint` (package name)
- `LCSC Part #` (LCSC component number, e.g., `C14663`)

Add a custom field `LCSC` to your schematic symbols and populate it with the LCSC part number for each component.

---

## 12. 3D Model Viewer and STEP Export

### 3D Model Assignment

Each footprint can reference a 3D model (STEP, WRL, or VRML format). The model path is specified in the footprint properties under the "3D Models" tab.

KiCad environment variables for 3D model paths:
- `${KICAD8_3DMODEL_DIR}` -- KiCad's built-in 3D model library
- `${KIPRJMOD}` -- Project root directory

### STEP Export for Mechanical Integration

Export the entire board as a STEP file for integration with mechanical CAD:

`File > Export > STEP` in the PCB editor.

Settings:
- Board origin: Grid origin or Drill/place file origin
- Include components: yes (unless you only need the bare board)
- Substitute models: yes (replaces missing models with bounding boxes)

### 3D Viewer Features (KiCad 8.x)

- Raytracing mode for realistic renders
- Clip planes for inspecting internal layers
- Component visibility toggle
- Measurement tool for clearance checks
- Export to PNG/JPEG for documentation

---

## 13. KiCad CLI Tools

KiCad 8.x ships with `kicad-cli`, a command-line interface for batch operations and CI/CD integration.

### Common CLI Commands

```bash
# Export schematic to PDF
kicad-cli sch export pdf \
  --output schematic.pdf \
  project.kicad_sch

# Export schematic to SVG (per-page)
kicad-cli sch export svg \
  --output ./svg-output/ \
  project.kicad_sch

# Run ERC from command line
kicad-cli sch erc \
  --output erc-report.rpt \
  --severity-all \
  project.kicad_sch

# Export netlist
kicad-cli sch export netlist \
  --output project.net \
  project.kicad_sch

# Export BOM
kicad-cli sch export bom \
  --output bom.csv \
  --fields "Reference,Value,Footprint,MPN" \
  project.kicad_sch

# Export PCB to Gerber
kicad-cli pcb export gerbers \
  --output ./gerbers/ \
  --layers "F.Cu,B.Cu,F.SilkS,B.SilkS,F.Mask,B.Mask,Edge.Cuts" \
  project.kicad_pcb

# Export drill files
kicad-cli pcb export drill \
  --output ./gerbers/ \
  --format excellon \
  --excellon-units mm \
  project.kicad_pcb

# Run DRC from command line
kicad-cli pcb drc \
  --output drc-report.rpt \
  --severity-all \
  project.kicad_pcb

# Export PCB to STEP
kicad-cli pcb export step \
  --output board.step \
  --subst-models \
  project.kicad_pcb

# Export pick-and-place file
kicad-cli pcb export pos \
  --output placement.csv \
  --format csv \
  --units mm \
  --side both \
  project.kicad_pcb

# Export PCB to SVG
kicad-cli pcb export svg \
  --output board.svg \
  --layers "F.Cu,B.Cu,Edge.Cuts" \
  project.kicad_pcb
```

These CLI commands are essential for CI/CD pipelines (e.g., GitHub Actions) that automatically generate manufacturing outputs and run checks on every commit.

---

## 14. KiCad Python Scripting API

KiCad 8.x embeds a Python 3 interpreter with access to the `pcbnew` module for PCB manipulation and the `kicad_sch` module for schematic access.

### Accessing the PCB via Python

```python
import pcbnew

# Load a PCB file
board = pcbnew.LoadBoard("/path/to/project.kicad_pcb")

# Iterate over all footprints
for footprint in board.GetFootprints():
    ref = footprint.GetReference()
    val = footprint.GetValue()
    pos = footprint.GetPosition()
    # Position is in nanometers internally; convert to mm
    x_mm = pcbnew.ToMM(pos.x)
    y_mm = pcbnew.ToMM(pos.y)
    print(f"{ref}: {val} at ({x_mm:.2f}, {y_mm:.2f}) mm")

# Iterate over all tracks
for track in board.GetTracks():
    if isinstance(track, pcbnew.PCB_VIA):
        drill = pcbnew.ToMM(track.GetDrillValue())
        diameter = pcbnew.ToMM(track.GetWidth())
        print(f"Via: drill={drill:.2f}mm, diameter={diameter:.2f}mm")
    elif isinstance(track, pcbnew.PCB_TRACK):
        width = pcbnew.ToMM(track.GetWidth())
        net = track.GetNet().GetNetname()
        print(f"Track: width={width:.2f}mm, net={net}")

# Get all nets
netinfo = board.GetNetInfo()
for net in netinfo.NetsByName():
    print(f"Net: {net}")

# Modify a footprint position
for fp in board.GetFootprints():
    if fp.GetReference() == "U1":
        new_pos = pcbnew.VECTOR2I(pcbnew.FromMM(50.0), pcbnew.FromMM(30.0))
        fp.SetPosition(new_pos)
        break

# Add a via programmatically
via = pcbnew.PCB_VIA(board)
via.SetPosition(pcbnew.VECTOR2I(pcbnew.FromMM(25.0), pcbnew.FromMM(25.0)))
via.SetDrill(pcbnew.FromMM(0.3))
via.SetWidth(pcbnew.FromMM(0.6))
via.SetLayerPair(pcbnew.F_Cu, pcbnew.B_Cu)
via.SetNet(board.FindNet("GND"))
board.Add(via)

# Save the modified board
board.Save(board.GetFileName())

# Zone operations
for zone in board.Zones():
    net = zone.GetNet().GetNetname()
    layer = zone.GetLayerName()
    print(f"Zone: net={net}, layer={layer}")

# Refill all zones
filler = pcbnew.ZONE_FILLER(board)
filler.Fill(board.Zones())
board.Save(board.GetFileName())
```

### Running Scripts

- **From KiCad scripting console**: Open `Tools > Scripting Console` in the PCB editor.
- **Standalone**: Run with the Python bundled with KiCad, or ensure `pcbnew.so` / `pcbnew.pyd` is on the Python path.
- **Action plugins**: Place Python scripts in `~/.local/share/kicad/8.0/scripting/plugins/` (Linux) or the equivalent platform path to make them available in the PCB editor's `Tools > External Plugins` menu.

---

## 15. Version Control with KiCad Files

### File Format Considerations

KiCad 8.x uses S-expression text format for `.kicad_sch`, `.kicad_pcb`, and `.kicad_sym` files. These are human-readable and diff-friendly compared to binary formats. The `.kicad_pro` file is JSON. The `.kicad_prl` file (local preferences) should NOT be version-controlled.

### Recommended .gitignore

```
# KiCad backup and autosave files
*~
*.bak
*-backups/
_autosave-*

# Local preferences (window layout, layer visibility)
*.kicad_prl

# Generated outputs (regenerate from source)
gerbers/
output/
*.rpt

# Lock files
*.lck

# OS files
.DS_Store
Thumbs.db
```

### Diffing KiCad Files

**kidiff** is a visual diff tool for KiCad schematics and PCBs. It generates side-by-side or overlay images of changes between two git revisions.

For text-based diffs, the S-expression format works reasonably well with `git diff`, but reordering of elements (e.g., zone fill data) can produce noisy diffs.

**Strategies to reduce diff noise:**
- Run "Refill all zones" before committing (zone fill data is deterministic when done from the same state).
- Avoid opening and saving files without making intentional changes (KiCad may reformat or reorder some elements).
- Use `.gitattributes` to set merge strategy:

```
*.kicad_sch merge=union
*.kicad_pcb merge=union
```

Note: `merge=union` is a heuristic and will not correctly resolve all conflicts. Manual review is always required for KiCad merge conflicts.

### Branching Workflow

Due to the complexity of PCB file merges, a recommended workflow is:
1. One person works on the schematic while another works on the PCB (avoid concurrent edits to the same file).
2. Use short-lived feature branches with frequent merges to main.
3. Review diffs visually using kidiff or KiCad's built-in "Compare" feature before merging.
4. Never force-push changes to shared branches.

---

## 16. Best Practices

- **Always run ERC before PCB layout.** Fix all errors; do not suppress warnings without understanding them. A clean ERC ensures the netlist driving the PCB is correct.
- **Always run DRC before generating manufacturing outputs.** Fix all errors. DRC catches clearance violations, unconnected nets, and rule violations that will cause manufacturing defects.
- **Use hierarchical sheets for designs with more than 30 components.** This improves readability, enables reuse, and simplifies review.
- **Assign footprints early in the design process.** This avoids surprises when transitioning from schematic to PCB and ensures the BOM is complete.
- **Use net classes to manage trace width and clearance rules.** This is more maintainable than manually setting widths per trace.
- **Place decoupling capacitors as close as possible to IC power pins.** Route the capacitor to the IC pin first, then to the power plane via. Use short, wide traces or direct pad-to-pad connections.
- **Use a ground plane on at least one layer.** An unbroken ground plane provides a low-impedance return path and reduces EMI.
- **Keep high-speed signal traces short and direct.** Avoid right-angle bends (use 45-degree or curved traces). Match trace lengths for differential pairs.
- **Add test points for critical signals during prototyping.** Test points (exposed pads or vias) allow probing with oscilloscopes and multimeters.
- **Use design review checklists before ordering PCBs.** Review power delivery, signal integrity, thermal management, mechanical fit, and manufacturing constraints.
- **Refill all zones before exporting Gerbers.** Stale zone fills may not reflect the current routing.
- **Generate and visually inspect Gerber files before submitting.** Use a Gerber viewer (KiCad's built-in viewer, gerbv, or the manufacturer's online viewer) to verify every layer.
- **Add fiducial markers for pick-and-place assembly.** Place at least 3 fiducials (2 on the same edge, 1 diagonal) for machine vision alignment.
- **Document design decisions in schematic text notes.** Add text boxes explaining non-obvious choices (e.g., "R12 selected for 100mA LED current at 3.3V forward drop").
- **Use consistent naming conventions for nets, references, and files.** This improves collaboration and reduces errors.

---

## 17. Anti-Patterns

- **Skipping ERC and relying on "it looks right."** Missing power flags, unconnected pins, and conflicting drivers will cause hard-to-debug failures in fabricated boards.
- **Using `unspecified` pin type to silence ERC errors.** This hides real connectivity issues. Always assign the correct electrical pin type.
- **Routing traces under QFN/BGA thermal pads without vias.** The exposed pad needs thermal vias to the ground plane for heat dissipation.
- **Using a single via for high-current paths.** One standard via can handle approximately 0.5-1 A. Always use multiple vias in parallel for power nets.
- **Ignoring copper zone fill settings.** Default thermal relief settings may create inadequate connections for power-hungry components. Verify thermal relief spoke width and count.
- **Placing all components on one side of a 2-layer board without a ground plane.** Route signals on the top layer and use the bottom as a continuous ground plane whenever possible.
- **Manually managing trace widths instead of using net classes.** Manual widths are error-prone and hard to update when design rules change.
- **Committing `.kicad_prl` files to version control.** These contain local UI preferences (window size, layer visibility) and cause unnecessary merge conflicts.
- **Editing KiCad files with a text editor while KiCad has them open.** KiCad may overwrite your changes or corrupt the file. Always close KiCad before external edits.
- **Using Protel filename extensions with JLCPCB without checking their current requirements.** JLCPCB accepts both Gerber X2 and RS-274X; verify the preferred format before export.
- **Copying footprints from unknown sources without verifying pad dimensions.** Always cross-check footprint pad sizes, pitch, and courtyard against the manufacturer's datasheet recommended land pattern.
- **Ignoring DRC "courtyard overlap" warnings.** Courtyard overlaps indicate components that may physically collide or be too close for assembly equipment.
- **Using the default 0.25 mm trace width for all signals.** Power traces, high-speed signals, and controlled-impedance lines all have different width requirements.
- **Not adding solder mask between fine-pitch pads.** For QFP/BGA with pitch below 0.5 mm, verify solder mask webbing meets manufacturer minimums or use solder mask defined (SMD) pads.
- **Creating hierarchical sheets without consistent label naming.** Mismatched label names between parent and child sheets cause silent disconnections.

---

## 18. Sources & References

- [KiCad 8.0 Official Documentation](https://docs.kicad.org/8.0/) -- Comprehensive reference for all KiCad features, file formats, and editor workflows.
- [KiCad Python Scripting Reference (pcbnew)](https://docs.kicad.org/doxygen/namespacepython.html) -- API documentation for the pcbnew Python module, including class references and usage examples.
- [JLCPCB PCB Manufacturing Capabilities](https://jlcpcb.com/capabilities/pcb-capabilities) -- Detailed specification sheet for JLCPCB's standard and advanced PCB manufacturing processes, including minimum trace widths, drill sizes, and tolerances.
- [IPC-2221B Generic Standard on Printed Board Design](https://www.ipc.org/TOC/IPC-2221B.pdf) -- Industry standard for PCB design covering trace width calculations, via sizing, clearance requirements, and thermal management guidelines.
- [KiCad CLI Reference (kicad-cli)](https://docs.kicad.org/8.0/en/cli/cli.html) -- Documentation for the KiCad command-line interface, including all available export and check commands.
- [Interactive HTML BOM Plugin (GitHub)](https://github.com/openscopeproject/InteractiveHtmlBom) -- Source repository and documentation for the Interactive HTML BOM plugin for KiCad.
- [Saturn PCB Toolkit](https://saturnpcb.com/saturn-pcb-toolkit/) -- Free PCB design calculator for trace width, via current capacity, differential impedance, and thermal calculations.
- [KiCad Library Conventions (KLC)](https://klc.kicad.org/) -- Official guidelines for creating symbols, footprints, and 3D models that conform to KiCad library standards.
