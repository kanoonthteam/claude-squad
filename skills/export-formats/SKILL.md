---
name: export-formats
description: Export and integration patterns for Dart applications covering PDF generation with package:pdf, PPTX/OpenXML slide creation, PNG screenshot capture via RepaintBoundary and dart:ui, SVG rendering with XML builders, batch multi-format export pipelines, ZIP asset bundling, resolution scaling, export configuration, metadata embedding, and memory management for large exports
---

# Export Formats & Integration Patterns

Comprehensive guide for an Export/Integration Engineer working with Dart. Covers generating PDFs, PPTX slides, PNG screenshots, and SVG graphics from application data. Includes batch export pipelines, asset bundling, resolution handling, configuration management, metadata embedding, and memory-safe patterns for large-scale exports.

## Table of Contents

1. [PDF Document Generation](#pdf-document-generation)
2. [PDF Styling and Layout](#pdf-styling-and-layout)
3. [Multi-Page PDF with Headers and Footers](#multi-page-pdf-with-headers-and-footers)
4. [PPTX and OpenXML Generation](#pptx-and-openxml-generation)
5. [PNG Screenshot Export](#png-screenshot-export)
6. [Image Scaling and Resolution Handling](#image-scaling-and-resolution-handling)
7. [SVG Generation](#svg-generation)
8. [SVG ViewBox and Coordinate Systems](#svg-viewbox-and-coordinate-systems)
9. [Batch Export Pipeline](#batch-export-pipeline)
10. [Asset Bundling into ZIP Archives](#asset-bundling-into-zip-archives)
11. [Export Configuration](#export-configuration)
12. [Export Metadata Embedding](#export-metadata-embedding)
13. [Memory Management for Large Exports](#memory-management-for-large-exports)
14. [Best Practices](#best-practices)
15. [Anti-Patterns](#anti-patterns)
16. [Sources & References](#sources--references)

---

## PDF Document Generation

The `package:pdf` library provides a widget-based API for constructing PDF documents in pure Dart, without requiring Flutter. The core abstractions are `Document`, `Page`, and a tree of `pw.Widget` instances that mirror Flutter's layout model.

### Core Concepts

- **Document**: The top-level container. Holds pages, metadata, and global theme.
- **Page**: Represents a single page with a defined `pageFormat`, `orientation`, and `build` callback.
- **Widget tree**: `pw.Column`, `pw.Row`, `pw.Container`, `pw.Text`, `pw.Table`, `pw.Image`, and many others compose the page content.

### Basic PDF Creation

```dart
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Generates a simple single-page PDF invoice and saves it to [outputPath].
Future<File> generateInvoicePdf({
  required String customerName,
  required List<InvoiceLineItem> items,
  required String outputPath,
}) async {
  final pdf = pw.Document(
    title: 'Invoice',
    author: 'ExportService',
    creator: 'MyApp v2.1.0',
    producer: 'package:pdf',
  );

  final totalAmount = items.fold<double>(
    0,
    (sum, item) => sum + item.quantity * item.unitPrice,
  );

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      orientation: pw.PageOrientation.portrait,
      margin: const pw.EdgeInsets.all(40),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Invoice',
              style: pw.TextStyle(
                fontSize: 28,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Text('Customer: $customerName'),
            pw.SizedBox(height: 24),
            _buildItemsTable(items),
            pw.Divider(thickness: 1),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Total: \$${totalAmount.toStringAsFixed(2)}',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  final file = File(outputPath);
  await file.writeAsBytes(await pdf.save());
  return file;
}

pw.Widget _buildItemsTable(List<InvoiceLineItem> items) {
  return pw.TableHelper.fromTextArray(
    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
    headerDecoration: const pw.BoxDecoration(
      color: PdfColors.grey300,
    ),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    headers: ['Description', 'Qty', 'Unit Price', 'Amount'],
    data: items.map((item) {
      final amount = item.quantity * item.unitPrice;
      return [
        item.description,
        '${item.quantity}',
        '\$${item.unitPrice.toStringAsFixed(2)}',
        '\$${amount.toStringAsFixed(2)}',
      ];
    }).toList(),
  );
}
```

### Page Format Options

Common page formats available in `PdfPageFormat`:

| Format        | Width (pt) | Height (pt) | Common Use              |
|---------------|-----------|-------------|-------------------------|
| `a4`          | 595.28    | 841.89      | International standard  |
| `letter`      | 612       | 792         | US standard             |
| `legal`       | 612       | 1008        | US legal documents      |
| `a3`          | 841.89    | 1190.55     | Large format prints     |
| `a5`          | 419.53    | 595.28      | Booklets, flyers        |

Custom formats can be constructed:

```
const customFormat = PdfPageFormat(
  72 * 8.5, // width in points (8.5 inches)
  72 * 14,  // height in points (14 inches)
  marginAll: 72 * 0.5, // 0.5 inch margins
);
```

---

## PDF Styling and Layout

### Fonts

`package:pdf` supports TrueType and OpenType fonts. Fonts can be loaded from assets, files, or bundled as byte data. Always load fonts asynchronously before building the document.

```
final fontData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
final roboto = pw.Font.ttf(fontData);

final boldData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
final robotoBold = pw.Font.ttf(boldData);
```

Apply fonts via `pw.TextStyle` or register them in a `pw.ThemeData`:

```
final theme = pw.ThemeData.withFont(
  base: roboto,
  bold: robotoBold,
  italic: robotoItalic,
  boldItalic: robotoBoldItalic,
);

final pdf = pw.Document(theme: theme);
```

### Colors

PDF colors use `PdfColor` or the predefined `PdfColors` constants:

```
const brandBlue = PdfColor.fromHex('#1A73E8');
const backgroundGrey = PdfColors.grey100;
```

Use colors in containers, text styles, and decorations:

```
pw.Container(
  padding: const pw.EdgeInsets.all(12),
  decoration: pw.BoxDecoration(
    color: backgroundGrey,
    border: pw.Border.all(color: brandBlue, width: 1.5),
    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
  ),
  child: pw.Text(
    'Highlighted Section',
    style: pw.TextStyle(color: brandBlue, fontSize: 14),
  ),
)
```

### Tables

Tables are a core building block for data-heavy exports. Use `pw.Table` for full control or `pw.TableHelper.fromTextArray` for quick construction from string data.

For complex tables with merged cells, custom borders, and per-cell styling:

```
pw.Table(
  border: pw.TableBorder.all(color: PdfColors.grey400),
  columnWidths: {
    0: const pw.FlexColumnWidth(2),
    1: const pw.FlexColumnWidth(1),
    2: const pw.FlexColumnWidth(1),
  },
  children: [
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.blue50),
      children: [
        _cell('Product', bold: true),
        _cell('Price', bold: true),
        _cell('Status', bold: true),
      ],
    ),
    for (final product in products)
      pw.TableRow(children: [
        _cell(product.name),
        _cell('\$${product.price.toStringAsFixed(2)}'),
        _cell(product.status.label),
      ]),
  ],
)
```

### Images in PDFs

Embed raster images (PNG, JPEG) or SVG:

```
final imageBytes = await File('logo.png').readAsBytes();
final pdfImage = pw.MemoryImage(imageBytes);

pw.Image(pdfImage, width: 120, height: 40, fit: pw.BoxFit.contain)
```

For SVG content within a PDF:

```
final svgString = await File('diagram.svg').readAsString();
final svgImage = pw.SvgImage(svg: svgString);

pw.Container(width: 200, height: 150, child: svgImage)
```

---

## Multi-Page PDF with Headers and Footers

For documents that span multiple pages, use `pw.MultiPage` instead of `pw.Page`. It automatically handles page breaks and renders header/footer on every page.

```dart
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

/// Generates a multi-page report with consistent headers, footers,
/// page numbers, and automatic page-break handling.
Future<File> generateMultiPageReport({
  required ReportData report,
  required String outputPath,
  PdfPageFormat pageFormat = PdfPageFormat.a4,
}) async {
  final pdf = pw.Document(
    title: report.title,
    author: report.author,
    subject: report.subject,
  );

  final logoBytes = await File(report.logoPath).readAsBytes();
  final logo = pw.MemoryImage(logoBytes);
  final generatedDate = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

  pdf.addPage(
    pw.MultiPage(
      pageFormat: pageFormat,
      orientation: pw.PageOrientation.portrait,
      margin: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 36),
      maxPages: 200,
      header: (pw.Context context) {
        return pw.Container(
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
            ),
          ),
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Image(logo, width: 80, height: 28),
              pw.Text(
                report.title,
                style: pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          ),
        );
      },
      footer: (pw.Context context) {
        return pw.Container(
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
            ),
          ),
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Generated: $generatedDate',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey),
              ),
            ],
          ),
        );
      },
      build: (pw.Context context) {
        return [
          // Title section
          pw.Header(
            level: 0,
            child: pw.Text(
              report.title,
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Paragraph(text: report.summary),
          pw.SizedBox(height: 16),

          // Data sections -- each section may cause page breaks
          for (final section in report.sections) ...[
            pw.Header(
              level: 1,
              child: pw.Text(
                section.heading,
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue800,
                ),
              ),
            ),
            pw.Paragraph(text: section.body),
            if (section.tableData != null)
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                ),
                cellPadding: const pw.EdgeInsets.all(6),
                headers: section.tableData!.headers,
                data: section.tableData!.rows,
              ),
            pw.SizedBox(height: 12),
          ],
        ];
      },
    ),
  );

  final file = File(outputPath);
  await file.writeAsBytes(await pdf.save());
  return file;
}
```

### Page Break Control

Force page breaks or keep widgets together:

```
// Force a page break before a section
pw.NewPage(),

// Keep a widget group from splitting across pages
pw.Wrap(
  children: [headerWidget, contentWidget],
),

// Partition content to avoid orphaned lines
pw.Partitions(
  children: [
    pw.Partition(child: leftColumn, width: 250),
    pw.Partition(child: rightColumn),
  ],
),
```

---

## PPTX and OpenXML Generation

Dart does not have a mature high-level PPTX library comparable to Python's `python-pptx`. The approach is to construct the OpenXML package manually: a PPTX file is a ZIP archive containing XML files that follow the Office Open XML (OOXML) specification.

### PPTX File Structure

```
presentation.pptx (ZIP)
├── [Content_Types].xml
├── _rels/
│   └── .rels
├── ppt/
│   ├── presentation.xml
│   ├── _rels/
│   │   └── presentation.xml.rels
│   ├── slideMasters/
│   │   └── slideMaster1.xml
│   ├── slideLayouts/
│   │   └── slideLayout1.xml
│   ├── slides/
│   │   ├── slide1.xml
│   │   ├── slide2.xml
│   │   └── _rels/
│   │       ├── slide1.xml.rels
│   │       └── slide2.xml.rels
│   ├── theme/
│   │   └── theme1.xml
│   └── media/
│       ├── image1.png
│       └── image2.jpg
└── docProps/
    ├── app.xml
    └── core.xml
```

### Slide XML Construction

Each slide is an XML document with shape trees containing text boxes, images, and shapes. Use `package:xml` to build these structures.

```dart
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Represents a single PPTX slide with a title and body text.
class PptxSlide {
  final String title;
  final String body;
  final List<int>? imageBytes;

  const PptxSlide({
    required this.title,
    required this.body,
    this.imageBytes,
  });
}

/// Builds a minimal PPTX file from a list of slides.
///
/// This generates valid Office Open XML that can be opened in
/// PowerPoint, Google Slides, and LibreOffice Impress.
Future<List<int>> buildPptx({
  required List<PptxSlide> slides,
  required String presentationTitle,
}) async {
  final archive = Archive();

  // [Content_Types].xml
  archive.addFile(_archiveFile(
    '[Content_Types].xml',
    _buildContentTypesXml(slides.length),
  ));

  // Top-level relationships
  archive.addFile(_archiveFile('_rels/.rels', _buildTopRels()));

  // Presentation core files
  archive.addFile(_archiveFile(
    'ppt/presentation.xml',
    _buildPresentationXml(slides.length),
  ));
  archive.addFile(_archiveFile(
    'ppt/_rels/presentation.xml.rels',
    _buildPresentationRels(slides.length),
  ));

  // Slide master and layout (minimal stubs)
  archive.addFile(_archiveFile(
    'ppt/slideMasters/slideMaster1.xml',
    _buildSlideMasterXml(),
  ));
  archive.addFile(_archiveFile(
    'ppt/slideLayouts/slideLayout1.xml',
    _buildSlideLayoutXml(),
  ));

  // Theme
  archive.addFile(_archiveFile('ppt/theme/theme1.xml', _buildThemeXml()));

  // Individual slides
  for (var i = 0; i < slides.length; i++) {
    final slideIndex = i + 1;
    archive.addFile(_archiveFile(
      'ppt/slides/slide$slideIndex.xml',
      _buildSlideXml(slides[i]),
    ));
    archive.addFile(_archiveFile(
      'ppt/slides/_rels/slide$slideIndex.xml.rels',
      _buildSlideRels(slideIndex, slides[i].imageBytes != null),
    ));

    // Embed image if present
    if (slides[i].imageBytes != null) {
      archive.addFile(ArchiveFile(
        'ppt/media/image$slideIndex.png',
        slides[i].imageBytes!.length,
        slides[i].imageBytes!,
      ));
    }
  }

  // Document properties
  archive.addFile(_archiveFile(
    'docProps/core.xml',
    _buildCorePropertiesXml(presentationTitle),
  ));

  return ZipEncoder().encode(archive)!;
}

ArchiveFile _archiveFile(String name, String xmlContent) {
  final bytes = utf8.encode(xmlContent);
  return ArchiveFile(name, bytes.length, bytes);
}

/// Builds the slide XML with a title text box and a body text box.
/// Uses EMU (English Metric Units): 1 inch = 914400 EMU.
String _buildSlideXml(PptxSlide slide) {
  const nsP = 'http://schemas.openxmlformats.org/presentationml/2006/main';
  const nsA = 'http://schemas.openxmlformats.org/drawingml/2006/main';
  const nsR = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

  final builder = XmlBuilder();
  builder.processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"');
  builder.element('p:sld', namespaces: {nsP: 'p', nsA: 'a', nsR: 'r'}, nest: () {
    builder.element('p:cSld', nest: () {
      builder.element('p:spTree', nest: () {
        // Group shape properties (required)
        builder.element('p:nvGrpSpPr', nest: () {
          builder.element('p:cNvPr', attributes: {'id': '1', 'name': ''});
          builder.element('p:cNvGrpSpPr');
          builder.element('p:nvPr');
        });
        builder.element('p:grpSpPr');

        // Title text box
        _addTextBox(
          builder,
          id: '2',
          name: 'Title',
          x: 457200,   // 0.5 inch from left
          y: 274638,   // 0.3 inch from top
          cx: 8229600, // ~9 inches wide
          cy: 1143000, // ~1.25 inches tall
          text: slide.title,
          fontSize: 3200, // in hundredths of a point
          bold: true,
        );

        // Body text box
        _addTextBox(
          builder,
          id: '3',
          name: 'Body',
          x: 457200,
          y: 1600200,
          cx: 8229600,
          cy: 4525963,
          text: slide.body,
          fontSize: 1800,
          bold: false,
        );
      });
    });
  });

  return builder.buildDocument().toXmlString(pretty: true);
}

void _addTextBox(
  XmlBuilder builder, {
  required String id,
  required String name,
  required int x,
  required int y,
  required int cx,
  required int cy,
  required String text,
  required int fontSize,
  required bool bold,
}) {
  const nsA = 'http://schemas.openxmlformats.org/drawingml/2006/main';

  builder.element('p:sp', nest: () {
    builder.element('p:nvSpPr', nest: () {
      builder.element('p:cNvPr', attributes: {'id': id, 'name': name});
      builder.element('p:cNvSpPr');
      builder.element('p:nvPr');
    });
    builder.element('p:spPr', nest: () {
      builder.element('a:xfrm', nest: () {
        builder.element('a:off', attributes: {'x': '$x', 'y': '$y'});
        builder.element('a:ext', attributes: {'cx': '$cx', 'cy': '$cy'});
      });
      builder.element('a:prstGeom', attributes: {'prst': 'rect'}, nest: () {
        builder.element('a:avLst');
      });
    });
    builder.element('p:txBody', nest: () {
      builder.element('a:bodyPr');
      builder.element('a:lstStyle');
      builder.element('a:p', nest: () {
        builder.element('a:r', nest: () {
          builder.element('a:rPr', attributes: {
            'lang': 'en-US',
            'sz': '$fontSize',
            if (bold) 'b': '1',
          });
          builder.element('a:t', nest: text);
        });
      });
    });
  });
}
```

### OOXML Coordinate System

PPTX uses English Metric Units (EMU):

| Unit   | EMU Value |
|--------|-----------|
| 1 inch | 914400    |
| 1 cm   | 360000    |
| 1 pt   | 12700     |
| 1 px   | 9525      |

Standard slide dimensions (widescreen 16:9):
- Width: 12192000 EMU (13.333 inches)
- Height: 6858000 EMU (7.5 inches)

Standard slide dimensions (4:3):
- Width: 9144000 EMU (10 inches)
- Height: 6858000 EMU (7.5 inches)

---

## PNG Screenshot Export

### Flutter Widget Capture with RepaintBoundary

In a Flutter application, the primary mechanism for capturing a widget as an image is `RepaintBoundary` combined with `dart:ui` APIs.

```dart
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Captures a widget tree wrapped in a [RepaintBoundary] as a PNG image.
///
/// The [boundaryKey] must be attached to a [RepaintBoundary] widget
/// that is currently mounted in the widget tree.
///
/// The [pixelRatio] controls the output resolution:
/// - 1.0 = 1x (standard)
/// - 2.0 = 2x (retina)
/// - 3.0 = 3x (high-DPI)
Future<Uint8List> captureWidgetAsPng({
  required GlobalKey boundaryKey,
  double pixelRatio = 2.0,
  ui.ImageByteFormat format = ui.ImageByteFormat.png,
}) async {
  final boundary = boundaryKey.currentContext!.findRenderObject()
      as RenderRepaintBoundary;

  // Capture the image at the specified pixel ratio
  final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);

  // Encode to PNG bytes
  final ByteData? byteData = await image.toByteData(format: format);
  image.dispose(); // Release GPU memory immediately

  if (byteData == null) {
    throw ExportException('Failed to encode image to PNG');
  }

  return byteData.buffer.asUint8List();
}

/// Saves the captured PNG to a file on disk.
Future<File> saveWidgetScreenshot({
  required GlobalKey boundaryKey,
  required String outputPath,
  double pixelRatio = 2.0,
}) async {
  final pngBytes = await captureWidgetAsPng(
    boundaryKey: boundaryKey,
    pixelRatio: pixelRatio,
  );

  final file = File(outputPath);
  await file.create(recursive: true);
  await file.writeAsBytes(pngBytes, flush: true);
  return file;
}
```

### Widget Setup for Capture

The widget tree must include a `RepaintBoundary` with a `GlobalKey`:

```
class ExportableChart extends StatelessWidget {
  final GlobalKey captureKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: captureKey,
      child: Container(
        width: 800,
        height: 600,
        color: Colors.white,
        child: const MyChartWidget(),
      ),
    );
  }
}
```

### Headless Canvas Rendering (Non-Flutter Dart)

For server-side or CLI Dart applications without Flutter, use `dart:ui` directly to render onto a canvas:

```
import 'dart:ui' as ui;

Future<Uint8List> renderCanvasToPng({
  required int width,
  required int height,
  required void Function(ui.Canvas canvas, ui.Size size) painter,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
  );

  painter(canvas, Size(width.toDouble(), height.toDouble()));

  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();

  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();

  return byteData!.buffer.asUint8List();
}
```

---

## Image Scaling and Resolution Handling

### Device Pixel Ratios

When exporting images, the pixel ratio determines the output resolution relative to the logical pixel size:

| Scale | DPI (approx) | Use Case                    | File Size Impact |
|-------|-------------|------------------------------|------------------|
| 1x    | 72          | Web thumbnails, previews     | Baseline         |
| 2x    | 144         | Retina displays, print-ready | ~4x baseline     |
| 3x    | 216         | High-DPI mobile screens      | ~9x baseline     |
| 4x    | 288         | Ultra-high quality archival   | ~16x baseline    |

### Multi-Resolution Export

```
/// Exports a widget at multiple resolutions for different use cases.
Future<Map<String, Uint8List>> exportMultiResolution({
  required GlobalKey boundaryKey,
  List<double> scales = const [1.0, 2.0, 3.0],
}) async {
  final results = <String, Uint8List>{};

  for (final scale in scales) {
    final bytes = await captureWidgetAsPng(
      boundaryKey: boundaryKey,
      pixelRatio: scale,
    );
    results['${scale.toInt()}x'] = bytes;
  }

  return results;
}
```

### Resolution-Aware File Naming

Follow platform conventions for multi-resolution assets:

```
/// Generates resolution-aware file paths.
///
/// Returns paths like:
///   chart.png       (1x)
///   chart@2x.png    (2x)
///   chart@3x.png    (3x)
String resolvedFileName(String baseName, double scale) {
  final ext = path.extension(baseName);
  final name = path.basenameWithoutExtension(baseName);

  if (scale == 1.0) return '$name$ext';
  return '$name@${scale.toInt()}x$ext';
}
```

### Memory Considerations for High-Resolution Exports

A 1920x1080 image at 3x becomes 5760x3240 pixels. At 4 bytes per pixel (RGBA), that is approximately 74.6 MB of raw pixel data. Always dispose images promptly and consider sequential processing for high-resolution batch exports.

---

## SVG Generation

SVG (Scalable Vector Graphics) is an XML-based format ideal for diagrams, charts, and illustrations that must remain crisp at any zoom level. In Dart, construct SVG documents using `package:xml` or simple string interpolation for basic cases.

### XML Builder Approach

```dart
import 'package:xml/xml.dart';

/// Generates an SVG document representing a bar chart.
///
/// Each bar is drawn as a `<rect>` element with a label `<text>` below.
/// The chart auto-scales to fit the provided [viewBoxWidth] and [viewBoxHeight].
String generateBarChartSvg({
  required List<ChartDataPoint> data,
  double viewBoxWidth = 600,
  double viewBoxHeight = 400,
  String backgroundColor = '#FFFFFF',
  String barColor = '#4285F4',
  String textColor = '#333333',
  double barSpacing = 8,
}) {
  if (data.isEmpty) {
    throw ArgumentError('Data must not be empty');
  }

  final maxValue = data.map((d) => d.value).reduce(
    (a, b) => a > b ? a : b,
  );

  final chartPadding = 60.0;
  final chartWidth = viewBoxWidth - chartPadding * 2;
  final chartHeight = viewBoxHeight - chartPadding * 2;
  final barWidth = (chartWidth - barSpacing * (data.length - 1)) / data.length;

  final builder = XmlBuilder();
  builder.processing('xml', 'version="1.0" encoding="UTF-8"');

  builder.element('svg', attributes: {
    'xmlns': 'http://www.w3.org/2000/svg',
    'viewBox': '0 0 $viewBoxWidth $viewBoxHeight',
    'width': '${viewBoxWidth}px',
    'height': '${viewBoxHeight}px',
  }, nest: () {
    // Metadata
    builder.element('title', nest: 'Bar Chart');
    builder.element('desc', nest: 'Generated by ExportService');

    // Style definitions
    builder.element('defs', nest: () {
      builder.element('style', attributes: {'type': 'text/css'}, nest: () {
        builder.text('''
          .bar { fill: $barColor; transition: opacity 0.2s; }
          .bar:hover { opacity: 0.8; }
          .label { font-family: Arial, sans-serif; font-size: 12px; fill: $textColor; text-anchor: middle; }
          .value-label { font-family: Arial, sans-serif; font-size: 10px; fill: $textColor; text-anchor: middle; }
          .axis { stroke: #CCCCCC; stroke-width: 1; }
        ''');
      });
    });

    // Background
    builder.element('rect', attributes: {
      'width': '$viewBoxWidth',
      'height': '$viewBoxHeight',
      'fill': backgroundColor,
    });

    // X-axis line
    builder.element('line', attributes: {
      'class': 'axis',
      'x1': '$chartPadding',
      'y1': '${chartPadding + chartHeight}',
      'x2': '${chartPadding + chartWidth}',
      'y2': '${chartPadding + chartHeight}',
    });

    // Bars and labels
    for (var i = 0; i < data.length; i++) {
      final point = data[i];
      final barHeight = (point.value / maxValue) * chartHeight;
      final x = chartPadding + i * (barWidth + barSpacing);
      final y = chartPadding + chartHeight - barHeight;

      // Bar rectangle
      builder.element('rect', attributes: {
        'class': 'bar',
        'x': '${x.toStringAsFixed(2)}',
        'y': '${y.toStringAsFixed(2)}',
        'width': '${barWidth.toStringAsFixed(2)}',
        'height': '${barHeight.toStringAsFixed(2)}',
        'rx': '3',
        'ry': '3',
      });

      // Value label above bar
      builder.element('text', attributes: {
        'class': 'value-label',
        'x': '${(x + barWidth / 2).toStringAsFixed(2)}',
        'y': '${(y - 6).toStringAsFixed(2)}',
      }, nest: '${point.value.toStringAsFixed(1)}');

      // Category label below axis
      builder.element('text', attributes: {
        'class': 'label',
        'x': '${(x + barWidth / 2).toStringAsFixed(2)}',
        'y': '${(chartPadding + chartHeight + 20).toStringAsFixed(2)}',
      }, nest: point.label);
    }
  });

  return builder.buildDocument().toXmlString(pretty: true);
}

class ChartDataPoint {
  final String label;
  final double value;

  const ChartDataPoint({required this.label, required this.value});
}
```

### SVG Path Data

Complex shapes use SVG path commands. Build paths programmatically:

```
/// Builds an SVG path string for a smooth line through data points.
String buildSmoothLinePath(List<Point<double>> points) {
  if (points.isEmpty) return '';
  if (points.length == 1) return 'M ${points[0].x} ${points[0].y}';

  final buffer = StringBuffer('M ${points[0].x} ${points[0].y}');

  for (var i = 1; i < points.length; i++) {
    final prev = points[i - 1];
    final curr = points[i];

    // Cubic bezier with control points at 1/3 intervals
    final cp1x = prev.x + (curr.x - prev.x) / 3;
    final cp1y = prev.y;
    final cp2x = curr.x - (curr.x - prev.x) / 3;
    final cp2y = curr.y;

    buffer.write(' C $cp1x,$cp1y $cp2x,$cp2y ${curr.x},${curr.y}');
  }

  return buffer.toString();
}
```

### SVG Text Elements

Text in SVG supports positioning, anchoring, rotation, and basic styling:

```
builder.element('text', attributes: {
  'x': '100',
  'y': '50',
  'font-family': 'Arial, Helvetica, sans-serif',
  'font-size': '16',
  'fill': '#333333',
  'text-anchor': 'start',        // start | middle | end
  'dominant-baseline': 'middle',  // auto | middle | hanging
  'transform': 'rotate(-45, 100, 50)', // rotate around (100,50)
}, nest: 'Rotated Label');
```

---

## SVG ViewBox and Coordinate Systems

### Understanding viewBox

The `viewBox` attribute defines the internal coordinate system of the SVG. It decouples the drawing coordinates from the physical display size.

```
<!-- viewBox="minX minY width height" -->
<svg viewBox="0 0 800 600" width="400px" height="300px">
  <!-- All coordinates are in the 800x600 space -->
  <!-- The browser scales to fit 400x300 physical pixels -->
</svg>
```

### Coordinate System Mapping

When the viewBox aspect ratio differs from the element dimensions, `preserveAspectRatio` controls scaling:

| Value              | Behavior                                       |
|--------------------|-------------------------------------------------|
| `xMidYMid meet`    | Scale uniformly to fit; center in both axes     |
| `xMidYMid slice`   | Scale uniformly to fill; crop overflow          |
| `none`             | Stretch non-uniformly to fill                   |
| `xMinYMin meet`    | Fit, align to top-left                          |
| `xMaxYMax meet`    | Fit, align to bottom-right                      |

### Dynamic viewBox Calculation

```
/// Calculates a viewBox that tightly fits all elements with padding.
String calculateViewBox({
  required List<Rect> elementBounds,
  double padding = 20,
}) {
  if (elementBounds.isEmpty) return '0 0 100 100';

  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;

  for (final rect in elementBounds) {
    minX = min(minX, rect.left);
    minY = min(minY, rect.top);
    maxX = max(maxX, rect.right);
    maxY = max(maxY, rect.bottom);
  }

  final x = minX - padding;
  final y = minY - padding;
  final width = (maxX - minX) + padding * 2;
  final height = (maxY - minY) + padding * 2;

  return '${x.toStringAsFixed(2)} ${y.toStringAsFixed(2)} '
      '${width.toStringAsFixed(2)} ${height.toStringAsFixed(2)}';
}
```

### Transforms and Nested Coordinate Spaces

SVG elements can establish nested coordinate systems using `<g>` groups with `transform` attributes:

```
// Translate, scale, and rotate a group of shapes
builder.element('g', attributes: {
  'transform': 'translate(100, 50) scale(1.5) rotate(15)',
}, nest: () {
  // Child elements use the transformed coordinate space
  builder.element('circle', attributes: {
    'cx': '0', 'cy': '0', 'r': '20', 'fill': '#FF5722',
  });
});
```

---

## Batch Export Pipeline

A batch export pipeline generates multiple formats from a single data source in one pass. This avoids redundant processing and keeps exports consistent.

### Pipeline Architecture

```dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Defines the available export formats.
enum ExportFormat { pdf, pptx, png, svg }

/// Configuration for a single export target.
class ExportTarget {
  final ExportFormat format;
  final String fileName;
  final ExportOptions options;

  const ExportTarget({
    required this.format,
    required this.fileName,
    this.options = const ExportOptions(),
  });
}

/// Result of a single export operation.
sealed class ExportResult {
  final ExportTarget target;
  final Duration elapsed;

  const ExportResult({required this.target, required this.elapsed});
}

final class ExportSuccess extends ExportResult {
  final File outputFile;
  final int fileSizeBytes;

  const ExportSuccess({
    required super.target,
    required super.elapsed,
    required this.outputFile,
    required this.fileSizeBytes,
  });
}

final class ExportFailure extends ExportResult {
  final String error;
  final StackTrace? stackTrace;

  const ExportFailure({
    required super.target,
    required super.elapsed,
    required this.error,
    this.stackTrace,
  });
}

/// Orchestrates multi-format batch exports with progress reporting,
/// error isolation, and memory-bounded concurrency.
class BatchExportPipeline {
  final String outputDirectory;
  final int maxConcurrency;
  final void Function(double progress, String message)? onProgress;

  BatchExportPipeline({
    required this.outputDirectory,
    this.maxConcurrency = 2,
    this.onProgress,
  });

  /// Runs all export targets and returns results for each.
  ///
  /// Failures in one format do not block other formats.
  /// Concurrency is bounded by [maxConcurrency] to manage memory.
  Future<List<ExportResult>> execute({
    required ExportData data,
    required List<ExportTarget> targets,
  }) async {
    await Directory(outputDirectory).create(recursive: true);

    final results = <ExportResult>[];
    final semaphore = _Semaphore(maxConcurrency);
    var completed = 0;

    final futures = targets.map((target) async {
      await semaphore.acquire();
      try {
        final stopwatch = Stopwatch()..start();
        final outputPath = '$outputDirectory/${target.fileName}';

        final bytes = await switch (target.format) {
          ExportFormat.pdf => _exportPdf(data, target.options),
          ExportFormat.pptx => _exportPptx(data, target.options),
          ExportFormat.png => _exportPng(data, target.options),
          ExportFormat.svg => _exportSvg(data, target.options),
        };

        final file = File(outputPath);
        await file.writeAsBytes(bytes, flush: true);
        stopwatch.stop();

        completed++;
        onProgress?.call(
          completed / targets.length,
          'Completed ${target.format.name}: ${target.fileName}',
        );

        return ExportSuccess(
          target: target,
          elapsed: stopwatch.elapsed,
          outputFile: file,
          fileSizeBytes: bytes.length,
        );
      } catch (e, st) {
        completed++;
        onProgress?.call(
          completed / targets.length,
          'Failed ${target.format.name}: $e',
        );

        return ExportFailure(
          target: target,
          elapsed: Duration.zero,
          error: e.toString(),
          stackTrace: st,
        );
      } finally {
        semaphore.release();
      }
    });

    for (final future in futures) {
      results.add(await future);
    }

    return results;
  }

  Future<Uint8List> _exportPdf(ExportData data, ExportOptions options) async {
    // Delegate to PDF generator (see PDF section above)
    throw UnimplementedError('Wire up PDF generation');
  }

  Future<List<int>> _exportPptx(ExportData data, ExportOptions options) async {
    // Delegate to PPTX builder (see PPTX section above)
    throw UnimplementedError('Wire up PPTX generation');
  }

  Future<Uint8List> _exportPng(ExportData data, ExportOptions options) async {
    // Delegate to PNG capture (see PNG section above)
    throw UnimplementedError('Wire up PNG capture');
  }

  Future<List<int>> _exportSvg(ExportData data, ExportOptions options) async {
    // Delegate to SVG generator (see SVG section above)
    final svgString = generateBarChartSvg(data: data.chartData);
    return utf8.encode(svgString);
  }
}

/// Simple counting semaphore for bounding concurrency.
class _Semaphore {
  final int maxCount;
  int _current = 0;
  final _waiters = <Completer<void>>[];

  _Semaphore(this.maxCount);

  Future<void> acquire() async {
    if (_current < maxCount) {
      _current++;
      return;
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    await completer.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    } else {
      _current--;
    }
  }
}
```

### Pipeline Usage

```
final pipeline = BatchExportPipeline(
  outputDirectory: '/tmp/exports/report-2024',
  maxConcurrency: 2,
  onProgress: (progress, message) {
    print('${(progress * 100).toInt()}% - $message');
  },
);

final results = await pipeline.execute(
  data: reportData,
  targets: [
    ExportTarget(
      format: ExportFormat.pdf,
      fileName: 'report.pdf',
      options: ExportOptions(pageSize: PageSize.a4, quality: 0.95),
    ),
    ExportTarget(
      format: ExportFormat.pptx,
      fileName: 'report.pptx',
    ),
    ExportTarget(
      format: ExportFormat.png,
      fileName: 'report-preview.png',
      options: ExportOptions(pixelRatio: 2.0),
    ),
    ExportTarget(
      format: ExportFormat.svg,
      fileName: 'report-chart.svg',
    ),
  ],
);

for (final result in results) {
  switch (result) {
    case ExportSuccess(:final outputFile, :final fileSizeBytes, :final elapsed):
      print('OK: ${outputFile.path} (${fileSizeBytes} bytes, ${elapsed.inMilliseconds}ms)');
    case ExportFailure(:final error, :final target):
      print('FAIL: ${target.fileName} - $error');
  }
}
```

---

## Asset Bundling into ZIP Archives

When an export produces multiple files (images, stylesheets, data files), bundle them into a single ZIP for delivery.

### ZIP Creation with package:archive

```dart
import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';

/// Bundles multiple export artifacts into a single ZIP archive.
///
/// The [manifest] maps archive paths to their content.
/// Supports both binary files (Uint8List) and text files (String).
Future<File> bundleExportsToZip({
  required String outputPath,
  required Map<String, Object> manifest,
  ExportMetadata? metadata,
}) async {
  final archive = Archive();

  // Add each file to the archive
  for (final entry in manifest.entries) {
    final archivePath = entry.key;
    final content = entry.value;

    final List<int> bytes;
    if (content is String) {
      bytes = utf8.encode(content);
    } else if (content is List<int>) {
      bytes = content;
    } else {
      throw ArgumentError(
        'Unsupported content type for $archivePath: ${content.runtimeType}',
      );
    }

    archive.addFile(ArchiveFile(archivePath, bytes.length, bytes));
  }

  // Add metadata manifest if provided
  if (metadata != null) {
    final metadataJson = jsonEncode(metadata.toJson());
    final metadataBytes = utf8.encode(metadataJson);
    archive.addFile(
      ArchiveFile('META/export-manifest.json', metadataBytes.length, metadataBytes),
    );
  }

  // Encode and write
  final zipBytes = ZipEncoder().encode(archive);
  if (zipBytes == null) {
    throw ExportException('Failed to encode ZIP archive');
  }

  final file = File(outputPath);
  await file.create(recursive: true);
  await file.writeAsBytes(zipBytes, flush: true);
  return file;
}

/// Example usage: bundle a full export package.
Future<File> createExportBundle({
  required String reportTitle,
  required List<int> pdfBytes,
  required List<int> pptxBytes,
  required Map<String, List<int>> pngAssets,
  required String svgContent,
}) async {
  final manifest = <String, Object>{
    'report/$reportTitle.pdf': pdfBytes,
    'report/$reportTitle.pptx': pptxBytes,
    'report/charts/chart.svg': svgContent,
  };

  // Add all PNG assets with their resolution suffixes
  for (final entry in pngAssets.entries) {
    manifest['report/images/${entry.key}'] = entry.value;
  }

  return bundleExportsToZip(
    outputPath: '/tmp/exports/$reportTitle-bundle.zip',
    manifest: manifest,
    metadata: ExportMetadata(
      version: '2.1.0',
      generatedAt: DateTime.now(),
      generator: 'MyApp ExportService',
      fileCount: manifest.length,
    ),
  );
}
```

### Streaming ZIP for Large Archives

For archives that exceed available memory, write entries incrementally:

```
/// Streams files into a ZIP without holding the entire archive in memory.
Future<void> streamZipToFile({
  required String outputPath,
  required Stream<ZipEntry> entries,
}) async {
  final output = File(outputPath).openWrite();
  final encoder = ZipEncoder();

  // Use OutputStreamBase for streaming writes
  final archive = Archive();

  await for (final entry in entries) {
    archive.addFile(
      ArchiveFile(entry.path, entry.bytes.length, entry.bytes),
    );
  }

  final encoded = encoder.encode(archive);
  if (encoded != null) {
    output.add(encoded);
  }

  await output.flush();
  await output.close();
}
```

---

## Export Configuration

### Unified Configuration Model

A single configuration object controls all export parameters. Use sealed classes or enums for type-safe format-specific options.

```
/// Page size presets for PDF and PPTX exports.
enum PageSize {
  a4(595.28, 841.89),
  a3(841.89, 1190.55),
  letter(612, 792),
  legal(612, 1008),
  slide16x9(960, 540),
  slide4x3(720, 540);

  final double width;
  final double height;

  const PageSize(this.width, this.height);
}

/// Page orientation.
enum Orientation { portrait, landscape }

/// Comprehensive export configuration.
class ExportOptions {
  /// Page size for paginated formats (PDF, PPTX).
  final PageSize pageSize;

  /// Page orientation.
  final Orientation orientation;

  /// Margins in points (PDF) or EMU (PPTX).
  final EdgeInsets margins;

  /// Image quality for raster outputs (0.0 to 1.0).
  final double quality;

  /// Pixel ratio for PNG exports.
  final double pixelRatio;

  /// Whether to embed fonts in PDF output.
  final bool embedFonts;

  /// Whether to compress images within PDFs.
  final bool compressImages;

  /// Maximum width for embedded images (pixels).
  final int? maxImageWidth;

  /// Background color (hex string).
  final String backgroundColor;

  /// Whether to include metadata in output files.
  final bool includeMetadata;

  /// Custom metadata key-value pairs.
  final Map<String, String> customMetadata;

  const ExportOptions({
    this.pageSize = PageSize.a4,
    this.orientation = Orientation.portrait,
    this.margins = const EdgeInsets.all(40),
    this.quality = 0.92,
    this.pixelRatio = 2.0,
    this.embedFonts = true,
    this.compressImages = true,
    this.maxImageWidth,
    this.backgroundColor = '#FFFFFF',
    this.includeMetadata = true,
    this.customMetadata = const {},
  });

  /// Creates a copy with overridden values.
  ExportOptions copyWith({
    PageSize? pageSize,
    Orientation? orientation,
    EdgeInsets? margins,
    double? quality,
    double? pixelRatio,
    bool? embedFonts,
    bool? compressImages,
    int? maxImageWidth,
    String? backgroundColor,
    bool? includeMetadata,
    Map<String, String>? customMetadata,
  }) {
    return ExportOptions(
      pageSize: pageSize ?? this.pageSize,
      orientation: orientation ?? this.orientation,
      margins: margins ?? this.margins,
      quality: quality ?? this.quality,
      pixelRatio: pixelRatio ?? this.pixelRatio,
      embedFonts: embedFonts ?? this.embedFonts,
      compressImages: compressImages ?? this.compressImages,
      maxImageWidth: maxImageWidth ?? this.maxImageWidth,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      includeMetadata: includeMetadata ?? this.includeMetadata,
      customMetadata: customMetadata ?? this.customMetadata,
    );
  }

  /// Effective page dimensions accounting for orientation.
  (double width, double height) get effectiveDimensions {
    return switch (orientation) {
      Orientation.portrait => (pageSize.width, pageSize.height),
      Orientation.landscape => (pageSize.height, pageSize.width),
    };
  }
}
```

### Format-Specific Options

```
/// PDF-specific options extending base configuration.
class PdfExportOptions extends ExportOptions {
  /// PDF version (1.4, 1.5, 1.7, 2.0).
  final String pdfVersion;

  /// Whether to linearize (optimize for web viewing).
  final bool linearize;

  /// Whether to encrypt the PDF.
  final bool encrypt;

  /// User password for encrypted PDFs.
  final String? userPassword;

  const PdfExportOptions({
    super.pageSize,
    super.orientation,
    super.margins,
    super.quality,
    super.embedFonts,
    super.compressImages,
    super.includeMetadata,
    this.pdfVersion = '1.7',
    this.linearize = false,
    this.encrypt = false,
    this.userPassword,
  });
}

/// PNG-specific options extending base configuration.
class PngExportOptions extends ExportOptions {
  /// Whether to use transparent background.
  final bool transparent;

  /// PNG compression level (0-9, higher = smaller file, slower).
  final int compressionLevel;

  const PngExportOptions({
    super.pixelRatio,
    super.backgroundColor,
    super.includeMetadata,
    this.transparent = false,
    this.compressionLevel = 6,
  });
}
```

---

## Export Metadata Embedding

### Metadata Model

```
/// Represents metadata embedded in export files.
class ExportMetadata {
  final String version;
  final DateTime generatedAt;
  final String generator;
  final int? fileCount;
  final String? sourceId;
  final String? sourceChecksum;
  final Map<String, String> custom;

  const ExportMetadata({
    required this.version,
    required this.generatedAt,
    required this.generator,
    this.fileCount,
    this.sourceId,
    this.sourceChecksum,
    this.custom = const {},
  });

  Map<String, dynamic> toJson() => {
    'version': version,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'generator': generator,
    if (fileCount != null) 'fileCount': fileCount,
    if (sourceId != null) 'sourceId': sourceId,
    if (sourceChecksum != null) 'sourceChecksum': sourceChecksum,
    if (custom.isNotEmpty) 'custom': custom,
  };

  factory ExportMetadata.fromJson(Map<String, dynamic> json) {
    return ExportMetadata(
      version: json['version'] as String,
      generatedAt: DateTime.parse(json['generatedAt'] as String),
      generator: json['generator'] as String,
      fileCount: json['fileCount'] as int?,
      sourceId: json['sourceId'] as String?,
      sourceChecksum: json['sourceChecksum'] as String?,
      custom: (json['custom'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v.toString())) ??
          const {},
    );
  }
}
```

### Embedding Metadata in PDFs

`package:pdf` supports document-level metadata via the `Document` constructor:

```
final pdf = pw.Document(
  title: metadata.sourceId ?? 'Export',
  author: metadata.generator,
  creator: '${metadata.generator} v${metadata.version}',
  producer: 'package:pdf',
  subject: 'Generated at ${metadata.generatedAt.toIso8601String()}',
  keywords: 'export, generated, ${metadata.version}',
);
```

### Embedding Metadata in SVGs

Add metadata as XML comments, `<metadata>` elements, or Dublin Core entries:

```
builder.element('metadata', nest: () {
  builder.element('rdf:RDF', namespaces: {
    'http://www.w3.org/1999/02/22-rdf-syntax-ns#': 'rdf',
    'http://purl.org/dc/elements/1.1/': 'dc',
  }, nest: () {
    builder.element('rdf:Description', nest: () {
      builder.element('dc:title', nest: metadata.sourceId ?? 'Export');
      builder.element('dc:creator', nest: metadata.generator);
      builder.element('dc:date', nest: metadata.generatedAt.toIso8601String());
      builder.element('dc:description',
        nest: 'Version: ${metadata.version}');
    });
  });
});
```

### Embedding Metadata in PPTX

PPTX uses OPC core properties in `docProps/core.xml`:

```
String _buildCorePropertiesXml(String title) {
  const nsCp = 'http://schemas.openxmlformats.org/package/2006/metadata/core-properties';
  const nsDc = 'http://purl.org/dc/elements/1.1/';
  const nsDcTerms = 'http://purl.org/dc/terms/';

  return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="$nsCp" xmlns:dc="$nsDc" xmlns:dcterms="$nsDcTerms">
  <dc:title>$title</dc:title>
  <dc:creator>ExportService</dc:creator>
  <dcterms:created>${DateTime.now().toUtc().toIso8601String()}</dcterms:created>
  <dcterms:modified>${DateTime.now().toUtc().toIso8601String()}</dcterms:modified>
  <cp:revision>1</cp:revision>
</cp:coreProperties>''';
}
```

### Embedding Metadata in PNG

PNG files support `tEXt` chunks for key-value metadata. After generating the raw bytes, inject text chunks before writing:

```
/// Injects metadata text chunks into PNG byte data.
///
/// PNG tEXt chunks store simple Latin-1 key-value pairs.
/// Common keys: Title, Author, Description, Creation Time, Software.
Uint8List injectPngMetadata(Uint8List pngBytes, ExportMetadata metadata) {
  // In practice, use a PNG manipulation library or implement
  // tEXt chunk insertion according to the PNG specification.
  // The tEXt chunk format is:
  //   - 4 bytes: data length
  //   - 4 bytes: chunk type ("tEXt")
  //   - N bytes: keyword + null separator + text
  //   - 4 bytes: CRC32
  //
  // For production code, consider using package:image which provides
  // PngEncoder with metadata support.
  return pngBytes; // Placeholder
}
```

---

## Memory Management for Large Exports

### The Problem

Export operations are memory-intensive. A multi-page PDF with embedded images can easily consume hundreds of megabytes. PNG captures at 3x resolution create massive pixel buffers. Processing multiple formats simultaneously can cause out-of-memory crashes.

### Strategy 1: Sequential Processing with Explicit Disposal

Process exports one at a time and dispose intermediate results immediately:

```
/// Processes exports sequentially to keep peak memory low.
Future<void> exportWithMemoryBounds({
  required ExportData data,
  required List<ExportTarget> targets,
  required String outputDir,
}) async {
  for (final target in targets) {
    // Process one format at a time
    final bytes = await _generateExport(data, target);

    // Write to disk immediately to free the byte buffer
    final file = File('$outputDir/${target.fileName}');
    await file.writeAsBytes(bytes, flush: true);

    // Help the GC by nullifying large references
    // (In Dart, the GC handles this, but clearing references
    // to large byte arrays promptly is still beneficial.)
  }
}
```

### Strategy 2: Chunked Image Processing

For documents with many images, process them in batches:

```
/// Processes images in chunks to avoid loading all into memory at once.
Future<List<pw.MemoryImage>> loadImagesChunked({
  required List<String> imagePaths,
  int chunkSize = 5,
  int? maxWidth,
}) async {
  final result = <pw.MemoryImage>[];

  for (var i = 0; i < imagePaths.length; i += chunkSize) {
    final chunk = imagePaths.sublist(
      i,
      (i + chunkSize).clamp(0, imagePaths.length),
    );

    final images = await Future.wait(
      chunk.map((path) async {
        var bytes = await File(path).readAsBytes();

        // Downscale if needed to reduce memory
        if (maxWidth != null) {
          bytes = await _resizeImage(bytes, maxWidth: maxWidth);
        }

        return pw.MemoryImage(bytes);
      }),
    );

    result.addAll(images);

    // Give the GC a chance to collect between chunks
    await Future<void>.delayed(Duration.zero);
  }

  return result;
}
```

### Strategy 3: Stream-Based PDF Generation

For extremely large documents, generate pages incrementally. While `package:pdf` builds the document in memory, you can minimize the widget tree size by building pages lazily:

```
/// Generates a large PDF by adding pages incrementally and
/// keeping only the current page's widget tree in memory.
Future<File> generateLargePdf({
  required List<PageData> pages,
  required String outputPath,
}) async {
  final pdf = pw.Document();

  for (var i = 0; i < pages.length; i++) {
    final pageData = pages[i];

    // Build only this page's widget tree
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => _buildPageContent(pageData),
      ),
    );

    // Log progress for monitoring
    if ((i + 1) % 50 == 0) {
      print('Generated page ${i + 1} of ${pages.length}');
    }
  }

  final bytes = await pdf.save();
  final file = File(outputPath);
  await file.writeAsBytes(bytes, flush: true);
  return file;
}
```

### Strategy 4: Dispose UI Resources Promptly

When capturing Flutter widgets as images, always dispose `ui.Image` objects:

```
Future<Uint8List> captureAndDispose(RenderRepaintBoundary boundary) async {
  final image = await boundary.toImage(pixelRatio: 2.0);
  try {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  } finally {
    image.dispose(); // Always dispose, even if encoding fails
  }
}
```

### Memory Monitoring

Track memory usage during export operations:

```
/// Logs current memory usage for debugging export memory issues.
void logMemoryUsage(String phase) {
  // ProcessInfo is available in dart:io
  final rss = ProcessInfo.currentRss;
  final rssMb = (rss / 1024 / 1024).toStringAsFixed(1);
  print('[$phase] RSS: ${rssMb}MB');
}
```

---

## Best Practices

### General Export Principles

1. **Validate inputs before generating exports.** Check that data is non-empty, required assets exist, and output directories are writable before starting any generation work. Fail fast with clear error messages.

2. **Use a unified configuration model.** A single `ExportOptions` class (with format-specific subclasses) ensures consistency across formats and makes it easy to serialize/deserialize export settings.

3. **Embed metadata in every export.** Include version, timestamp, generator name, and source identifier. This enables traceability and debugging when exports are shared or archived.

4. **Isolate format-specific logic.** Each export format (PDF, PPTX, PNG, SVG) should have its own generator class. The batch pipeline orchestrates them but does not contain format-specific code.

5. **Report progress for long-running exports.** Use callbacks or streams to report completion percentage and current operation. This enables UI progress bars and logging.

6. **Test exports with round-trip validation.** After generating a PDF, open it with a PDF parser to verify structure. After generating an SVG, parse the XML to verify well-formedness. After generating a PPTX, unzip and validate the XML.

### PDF Best Practices

7. **Always load fonts before building the document.** Font loading is asynchronous. Load all required fonts, then construct the Document with a ThemeData that references them.

8. **Use MultiPage for data-driven documents.** Single `Page` is appropriate for fixed-content exports like certificates. `MultiPage` handles automatic page breaks, headers, and footers.

9. **Prefer vector content over raster.** Use `SvgImage` for logos and icons within PDFs when possible. Vector content scales without quality loss and produces smaller files.

10. **Set appropriate PDF metadata for accessibility.** Title, author, and subject fields help screen readers and document management systems categorize exports.

### PNG Best Practices

11. **Default to 2x pixel ratio.** This provides a good balance of quality and file size for most use cases. Offer 1x for thumbnails and 3x for print.

12. **Always dispose ui.Image after encoding.** GPU-backed images consume significant memory. Use try/finally to ensure disposal even on errors.

13. **Use a white or opaque background unless transparency is needed.** Transparent PNGs are larger and may render differently across viewers.

### SVG Best Practices

14. **Always include a viewBox attribute.** Without viewBox, the SVG cannot scale properly. The viewBox defines the internal coordinate system independent of display size.

15. **Use CSS classes for styling instead of inline attributes.** This keeps the SVG smaller and easier to restyle after export.

16. **Include descriptive `<title>` and `<desc>` elements.** These improve accessibility for screen readers and provide context when SVGs are embedded in web pages.

### PPTX Best Practices

17. **Use EMU (English Metric Units) for all coordinates.** PPTX elements are positioned in EMUs. Define constants for common conversions (inches, centimeters, points to EMU).

18. **Include slide master and layout references.** Even minimal PPTX files need a slide master and at least one layout. Without these, some viewers will fail to open the file.

19. **Validate XML structure against the OOXML schema.** Malformed XML in any part of the PPTX ZIP will cause the entire file to be rejected by presentation software.

---

## Anti-Patterns

### 1. Building the Entire Export in Memory Before Writing

**Wrong:**
```
// Generates ALL formats, holds ALL byte arrays, then writes ALL files
final pdfBytes = await generatePdf(data);
final pptxBytes = await generatePptx(data);
final pngBytes = await generatePng(data);      // Could be 100MB+
final svgString = generateSvg(data);

await File('out.pdf').writeAsBytes(pdfBytes);
await File('out.pptx').writeAsBytes(pptxBytes);
await File('out.png').writeAsBytes(pngBytes);
await File('out.svg').writeAsString(svgString);
```

**Right:** Generate and write each format sequentially, releasing memory between exports:
```
await generateAndWritePdf(data, 'out.pdf');
// pdfBytes is now eligible for GC
await generateAndWritePptx(data, 'out.pptx');
await generateAndWritePng(data, 'out.png');
await generateAndWriteSvg(data, 'out.svg');
```

### 2. Ignoring Image Disposal

**Wrong:**
```
final image = await boundary.toImage(pixelRatio: 3.0);
final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
// image is never disposed -- GPU memory leak
return byteData!.buffer.asUint8List();
```

**Right:** Always dispose in a finally block:
```
final image = await boundary.toImage(pixelRatio: 3.0);
try {
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
} finally {
  image.dispose();
}
```

### 3. Hardcoding Export Configuration

**Wrong:**
```
pdf.addPage(pw.Page(
  pageFormat: PdfPageFormat.a4,  // Always A4, no way to change
  margin: const pw.EdgeInsets.all(40),  // Fixed margins
  // ...
));
```

**Right:** Accept configuration parameters:
```
pdf.addPage(pw.Page(
  pageFormat: options.toPdfPageFormat(),
  margin: options.toEdgeInsets(),
  orientation: options.toPageOrientation(),
  // ...
));
```

### 4. Silent Failures in Batch Exports

**Wrong:**
```
for (final target in targets) {
  try {
    await exportFormat(target);
  } catch (_) {
    // Swallowed error -- caller has no idea what failed
  }
}
```

**Right:** Use result types to report success and failure per target:
```
for (final target in targets) {
  try {
    final file = await exportFormat(target);
    results.add(ExportSuccess(target: target, outputFile: file));
  } catch (e, st) {
    results.add(ExportFailure(target: target, error: e.toString(), stackTrace: st));
  }
}
return results; // Caller can inspect each result
```

### 5. Concatenating SVG as Raw Strings

**Wrong:**
```
final svg = '<svg viewBox="0 0 $w $h">'
    '<rect x="$x" y="$y" width="$rw" height="$rh" fill="$color"/>'
    // No escaping -- breaks if label contains < or &
    '<text x="$tx" y="$ty">$label</text>'
    '</svg>';
```

**Right:** Use `XmlBuilder` which handles escaping automatically:
```
final builder = XmlBuilder();
builder.element('svg', attributes: {
  'viewBox': '0 0 $w $h',
}, nest: () {
  builder.element('rect', attributes: {
    'x': '$x', 'y': '$y', 'width': '$rw', 'height': '$rh', 'fill': color,
  });
  builder.element('text', attributes: {
    'x': '$tx', 'y': '$ty',
  }, nest: label); // XmlBuilder escapes special characters
});
```

### 6. Not Setting a viewBox on SVG Elements

**Wrong:**
```
<svg width="800" height="600">
  <!-- Fixed pixel dimensions, cannot scale -->
</svg>
```

**Right:**
```
<svg viewBox="0 0 800 600" width="100%" height="100%" preserveAspectRatio="xMidYMid meet">
  <!-- Scalable to any container size -->
</svg>
```

### 7. Unbounded Concurrency in Batch Exports

**Wrong:**
```
// Launches ALL exports simultaneously -- can exhaust memory
await Future.wait(targets.map((t) => exportFormat(t)));
```

**Right:** Use a semaphore to bound concurrency:
```
final semaphore = _Semaphore(2); // At most 2 concurrent exports
await Future.wait(targets.map((t) async {
  await semaphore.acquire();
  try {
    await exportFormat(t);
  } finally {
    semaphore.release();
  }
}));
```

### 8. Missing Content_Types.xml in PPTX

**Wrong:** Omitting `[Content_Types].xml` from the PPTX ZIP archive. Every OOXML package requires this file to declare the MIME types of its parts. Without it, no application can open the file.

**Right:** Always include a complete `[Content_Types].xml` that declares every content type used:
```
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Default Extension="png" ContentType="image/png"/>
  <Default Extension="jpg" ContentType="image/jpeg"/>
  <Override PartName="/ppt/presentation.xml"
    ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
  <Override PartName="/ppt/slides/slide1.xml"
    ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>
</Types>
```

---

## Sources & References

1. **package:pdf (pub.dev)** -- The primary Dart library for PDF generation. Covers the Document, Page, MultiPage, and widget APIs used throughout this guide.
   https://pub.dev/packages/pdf

2. **package:archive (pub.dev)** -- Dart library for creating and reading ZIP archives, used for PPTX generation and asset bundling.
   https://pub.dev/packages/archive

3. **package:xml (pub.dev)** -- XML builder and parser for Dart, used for constructing PPTX slide XML and SVG documents.
   https://pub.dev/packages/xml

4. **Office Open XML (ECMA-376) Specification** -- The standard that defines PPTX, DOCX, and XLSX file formats including slide structure, relationships, and content types.
   https://ecma-international.org/publications-and-standards/standards/ecma-376/

5. **SVG Specification (W3C)** -- The definitive reference for SVG elements, attributes, path commands, viewBox, coordinate systems, and transforms.
   https://www.w3.org/TR/SVG2/

6. **Flutter RepaintBoundary Documentation** -- Official Flutter docs on RepaintBoundary and toImage() for capturing widget trees as raster images.
   https://api.flutter.dev/flutter/rendering/RenderRepaintBoundary-class.html

7. **Dart dart:ui Library Reference** -- Documentation for Canvas, PictureRecorder, Image, and other low-level rendering APIs used in headless PNG generation.
   https://api.flutter.dev/flutter/dart-ui/dart-ui-library.html
