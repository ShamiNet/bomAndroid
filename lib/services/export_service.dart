import 'dart:io';
import 'package:flutter/material.dart';
import '../models/distance_measurement.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Centralized export helpers: PDF, TXT, Clipboard, GPX.
class ExportService {
  static late pw.Font ttf;

  static Future<void> initializeFonts() async {
    final fontData =
        await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf');
    ttf = pw.Font.ttf(fontData);
  }

  Future<File> _writeTempFile(String filename, String content) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$filename');
    await f.writeAsString(content);
    return f;
  }

  Future<void> _maybeSaveToDownloads(String filename, String content) async {
    Directory? downloadsDir;
    if (Platform.isAndroid) {
      downloadsDir = Directory('/storage/emulated/0/Download');
    } else if (Platform.isIOS) {
      downloadsDir = await getApplicationDocumentsDirectory();
    } else {
      downloadsDir = await getDownloadsDirectory();
    }
    if (downloadsDir != null) {
      final file = File('${downloadsDir.path}/$filename');
      await file.writeAsString(content);
    }
  }

  Future<void> exportMeasurementsToTxt({
    required BuildContext context,
    required List<DistanceMeasurement> measurements,
    required String title,
    String? description,
    bool saveToDownloads = false,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln(title);
    if (description != null) buffer.writeln(description);
    buffer.writeln();

    for (final m in measurements) {
      buffer.writeln('--- قياس ---');
      buffer.writeln(
          'الهدف (UTM - ${m.zone1}N): (${m.point1Utm.x.toStringAsFixed(0)}, ${m.point1Utm.y.toStringAsFixed(0)})');
      buffer.writeln(
          'الرماية (UTM - ${m.zone2}N): (${m.point2Utm.x.toStringAsFixed(0)}, ${m.point2Utm.y.toStringAsFixed(0)})');
      buffer.writeln('المسافة: ${m.distance.toStringAsFixed(2)} متر');
      buffer.writeln(
          'تصحيح شمالي: ${m.deltaNorthMeters.abs().toStringAsFixed(2)} متر (${m.deltaNorthMeters >= 0 ? "شمالاً" : "جنوباً"})');
      buffer.writeln(
          'تصحيح شرقي: ${m.deltaEastMeters.abs().toStringAsFixed(2)} متر (${m.deltaEastMeters >= 0 ? "شرقاً" : "غرباً"})');
      buffer.writeln(
          'التاريخ: ${DateTime.fromMillisecondsSinceEpoch(m.timestampMillis).toLocal()}');
      buffer.writeln('----------------');
    }

    final content = buffer.toString();
    final temp = await _writeTempFile(
        'measurements_${DateTime.now().millisecondsSinceEpoch}.txt', content);

    if (saveToDownloads) {
      try {
        await _maybeSaveToDownloads(temp.uri.pathSegments.last, content);
        if (context.mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('تم حفظ الملف في مجلد التنزيلات')));
      } catch (_) {
        if (context.mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('فشل حفظ الملف في التنزيلات')));
      }
    }

    await Share.shareXFiles([XFile(temp.path)],
        text: 'تم تصدير القياسات كملف نصي.');
  }

  Future<void> exportMeasurementsToClipboard({
    required BuildContext context,
    required List<DistanceMeasurement> measurements,
    required String title,
    String? description,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln(title);
    if (description != null) buffer.writeln(description);
    buffer.writeln();

    for (final m in measurements) {
      buffer.writeln('--- قياس ---');
      buffer.writeln(
          'الهدف (UTM - ${m.zone1}N): (${m.point1Utm.x.toStringAsFixed(0)}, ${m.point1Utm.y.toStringAsFixed(0)})');
      buffer.writeln(
          'الرماية (UTM - ${m.zone2}N): (${m.point2Utm.x.toStringAsFixed(0)}, ${m.point2Utm.y.toStringAsFixed(0)})');
      buffer.writeln('المسافة: ${m.distance.toStringAsFixed(2)} متر');
      buffer.writeln(
          'التاريخ: ${DateTime.fromMillisecondsSinceEpoch(m.timestampMillis).toLocal()}');
      buffer.writeln('----------------');
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم نسخ القياسات إلى الحافظة!')));
  }

  Future<void> exportMeasurementsToGpx({
    required BuildContext context,
    required List<DistanceMeasurement> measurements,
    required String title,
    bool saveToDownloads = false,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln(
        '<gpx version="1.1" creator="bom" xmlns="http://www.topografix.com/GPX/1/1">');
    buffer.writeln('<metadata><name>${title}</name></metadata>');
    buffer.writeln('<trk>');
    buffer.writeln('<name>${title}</name>');

    for (final m in measurements) {
      final t1 = DateTime.fromMillisecondsSinceEpoch(m.timestampMillis)
          .toUtc()
          .toIso8601String();
      final t2 = DateTime.fromMillisecondsSinceEpoch(m.timestampMillis + 1000)
          .toUtc()
          .toIso8601String();
      buffer.writeln('  <trkseg>');
      buffer.writeln(
          '    <trkpt lat="${m.point1.latitude}" lon="${m.point1.longitude}">');
      buffer.writeln('      <time>$t1</time>');
      buffer.writeln('    </trkpt>');
      buffer.writeln(
          '    <trkpt lat="${m.point2.latitude}" lon="${m.point2.longitude}">');
      buffer.writeln('      <time>$t2</time>');
      buffer.writeln('    </trkpt>');
      buffer.writeln('  </trkseg>');
    }

    buffer.writeln('</trk>');
    buffer.writeln('</gpx>');

    final content = buffer.toString();
    final temp = await _writeTempFile(
        'measurements_${DateTime.now().millisecondsSinceEpoch}.gpx', content);

    if (saveToDownloads) {
      try {
        await _maybeSaveToDownloads(temp.uri.pathSegments.last, content);
        if (context.mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('تم حفظ الملف في مجلد التنزيلات')));
      } catch (_) {
        if (context.mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('فشل حفظ الملف في التنزيلات')));
      }
    }

    await Share.shareXFiles([XFile(temp.path)], text: 'تصدير القياسات كـ GPX');
  }

  Future<void> exportMeasurementToPdf({
    required BuildContext context,
    required DistanceMeasurement measurement,
    String? description,
    bool saveToDownloads = false,
  }) async {
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('تفاصيل القياس',
                  style: pw.TextStyle(
                      font: ttf, fontSize: 24, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 20),
              if (description != null) ...[
                pw.Text(description,
                    style: pw.TextStyle(font: ttf, fontSize: 14)),
                pw.SizedBox(height: 20),
              ],
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  borderRadius: pw.BorderRadius.circular(10),
                  color: PdfColors.grey100,
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(children: [
                      pw.Text('الهدف (UTM - ${measurement.zone1}N): ',
                          style: pw.TextStyle(font: ttf)),
                      pw.Text(
                          '(${measurement.point1Utm.x.toStringAsFixed(0)}, ${measurement.point1Utm.y.toStringAsFixed(0)})',
                          style: pw.TextStyle(
                              font: ttf, fontWeight: pw.FontWeight.bold)),
                    ]),
                    pw.SizedBox(height: 10),
                    pw.Row(children: [
                      pw.Text('الرماية (UTM - ${measurement.zone2}N): ',
                          style: pw.TextStyle(font: ttf)),
                      pw.Text(
                          '(${measurement.point2Utm.x.toStringAsFixed(0)}, ${measurement.point2Utm.y.toStringAsFixed(0)})',
                          style: pw.TextStyle(
                              font: ttf, fontWeight: pw.FontWeight.bold)),
                    ]),
                    pw.SizedBox(height: 15),
                    pw.Row(children: [
                      pw.Text('المسافة: ', style: pw.TextStyle(font: ttf)),
                      pw.Text('${measurement.distance.toStringAsFixed(2)} متر',
                          style: pw.TextStyle(
                              font: ttf,
                              fontSize: 16,
                              fontWeight: pw.FontWeight.bold)),
                    ]),
                    pw.SizedBox(height: 15),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                      children: [
                        _buildCorrectionChipPdf(
                          isPositive: measurement.deltaNorthMeters >= 0,
                          positiveText: 'شمالاً',
                          negativeText: 'جنوباً',
                          value: measurement.deltaNorthMeters,
                          font: ttf,
                        ),
                        _buildCorrectionChipPdf(
                          isPositive: measurement.deltaEastMeters >= 0,
                          positiveText: 'شرقاً',
                          negativeText: 'غرباً',
                          value: measurement.deltaEastMeters,
                          font: ttf,
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 10),
                    pw.Text(
                        'التاريخ: ${DateTime.fromMillisecondsSinceEpoch(measurement.timestampMillis).toLocal()}',
                        style:
                            pw.TextStyle(font: ttf, color: PdfColors.grey700)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    final pdfData = await doc.save();
    final temp = await _writeTempFile(
        'measurement_${DateTime.now().millisecondsSinceEpoch}.pdf',
        String.fromCharCodes(pdfData));

    if (saveToDownloads) {
      try {
        await _maybeSaveToDownloads(
            temp.uri.pathSegments.last, String.fromCharCodes(pdfData));
        if (context.mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('تم حفظ الملف في مجلد التنزيلات')));
      } catch (_) {
        if (context.mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('فشل حفظ الملف في التنزيلات')));
      }
    }

    await Share.shareXFiles([XFile(temp.path)], text: 'تفاصيل القياس (PDF)');
  }

  Future<void> exportAllMeasurementsToPdf({
    required BuildContext context,
    required List<DistanceMeasurement> measurements,
    required String title,
    String? description,
    bool saveToDownloads = false,
  }) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        build: (pw.Context context) {
          return [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(title,
                    style: pw.TextStyle(
                        font: ttf,
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 10),
                if (description != null) ...[
                  pw.Text(description,
                      style: pw.TextStyle(font: ttf, fontSize: 14)),
                  pw.SizedBox(height: 20),
                ],
                for (final m in measurements) ...[
                  pw.Container(
                    margin: const pw.EdgeInsets.only(bottom: 20),
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      borderRadius: pw.BorderRadius.circular(10),
                      color: PdfColors.grey100,
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(children: [
                          pw.Text('الهدف (UTM - ${m.zone1}N): ',
                              style: pw.TextStyle(font: ttf)),
                          pw.Text(
                              '(${m.point1Utm.x.toStringAsFixed(0)}, ${m.point1Utm.y.toStringAsFixed(0)})',
                              style: pw.TextStyle(
                                  font: ttf, fontWeight: pw.FontWeight.bold)),
                        ]),
                        pw.SizedBox(height: 10),
                        pw.Row(children: [
                          pw.Text('الرماية (UTM - ${m.zone2}N): ',
                              style: pw.TextStyle(font: ttf)),
                          pw.Text(
                              '(${m.point2Utm.x.toStringAsFixed(0)}, ${m.point2Utm.y.toStringAsFixed(0)})',
                              style: pw.TextStyle(
                                  font: ttf, fontWeight: pw.FontWeight.bold)),
                        ]),
                        pw.SizedBox(height: 15),
                        pw.Row(children: [
                          pw.Text('المسافة: ', style: pw.TextStyle(font: ttf)),
                          pw.Text('${m.distance.toStringAsFixed(2)} متر',
                              style: pw.TextStyle(
                                  font: ttf,
                                  fontSize: 16,
                                  fontWeight: pw.FontWeight.bold)),
                        ]),
                        pw.SizedBox(height: 15),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                          children: [
                            _buildCorrectionChipPdf(
                              isPositive: m.deltaNorthMeters >= 0,
                              positiveText: 'شمالاً',
                              negativeText: 'جنوباً',
                              value: m.deltaNorthMeters,
                              font: ttf,
                            ),
                            _buildCorrectionChipPdf(
                              isPositive: m.deltaEastMeters >= 0,
                              positiveText: 'شرقاً',
                              negativeText: 'غرباً',
                              value: m.deltaEastMeters,
                              font: ttf,
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 10),
                        pw.Text(
                            'التاريخ: ${DateTime.fromMillisecondsSinceEpoch(m.timestampMillis).toLocal()}',
                            style: pw.TextStyle(
                                font: ttf, color: PdfColors.grey700)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ];
        },
      ),
    );

    final pdfData = await doc.save();
    final temp = await _writeTempFile(
        'measurements_${DateTime.now().millisecondsSinceEpoch}.pdf',
        String.fromCharCodes(pdfData));

    if (saveToDownloads) {
      try {
        await _maybeSaveToDownloads(
            temp.uri.pathSegments.last, String.fromCharCodes(pdfData));
        if (context.mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('تم حفظ الملف في مجلد التنزيلات')));
      } catch (_) {
        if (context.mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('فشل حفظ الملف في التنزيلات')));
      }
    }

    await Share.shareXFiles([XFile(temp.path)], text: '$title (PDF)');
  }

  pw.Widget _buildCorrectionChipPdf({
    required bool isPositive,
    required String positiveText,
    required String negativeText,
    required double value,
    required pw.Font font,
  }) {
    final color = isPositive ? PdfColors.green800 : PdfColors.red800;
    final icon = isPositive
        ? (positiveText == 'شمالاً' ? '\u2191' : '\u2192')
        : (positiveText == 'شمالاً' ? '\u2193' : '\u2190');
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: pw.BoxDecoration(
          color: PdfColors.grey300, borderRadius: pw.BorderRadius.circular(6)),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(icon,
              style: pw.TextStyle(font: font, color: color, fontSize: 14)),
          pw.SizedBox(width: 4),
          pw.Text(
              '${isPositive ? positiveText : negativeText}: ${value.abs().toStringAsFixed(2)} م',
              style: pw.TextStyle(
                  font: font,
                  color: color,
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }
}
