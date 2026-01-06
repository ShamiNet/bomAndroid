import 'package:flutter/material.dart';
import 'package:bom/models/distance_measurement.dart';
import 'package:proj4dart/proj4dart.dart' as proj4;

class MeasurementCard extends StatelessWidget {
  final DistanceMeasurement measurement;

  const MeasurementCard({Key? key, required this.measurement})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    // التحقق من نوع القياس
    final bool isEmplacementMeasurement = measurement.emplacementId != null &&
        measurement.emplacementId!.isNotEmpty;
    final bool isCorrection =
        measurement.note != null && measurement.note!.isNotEmpty;
    final bool suppressUntilImpact = isEmplacementMeasurement && !isCorrection;

    // في حالة المربض بدون سقوط، لا نعرض البطاقة ولا نطبع أي شيء
    if (suppressUntilImpact) {
      return const SizedBox.shrink();
    }

    // طباعة البيانات في الكونسول
    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('📊 بيانات القياس:');
    debugPrint(
        'نوع القياس: ${isEmplacementMeasurement ? '🏗️ قياس مربض' : '📍 قياس عادي'}');
    debugPrint('معرف المربض: ${measurement.emplacementId ?? 'لا يوجد'}');
    debugPrint(
        'الهدف (LatLng): ${measurement.point1.latitude}, ${measurement.point1.longitude}');
    debugPrint(
        'السقوط (LatLng): ${measurement.point2.latitude}, ${measurement.point2.longitude}');
    debugPrint(
        'الهدف (UTM): (${measurement.point1Utm.x.toStringAsFixed(2)}, ${measurement.point1Utm.y.toStringAsFixed(2)}) Zone: ${measurement.zone1}N');
    debugPrint(
        'السقوط (UTM): (${measurement.point2Utm.x.toStringAsFixed(2)}, ${measurement.point2Utm.y.toStringAsFixed(2)}) Zone: ${measurement.zone2}N');
    debugPrint('المسافة: ${measurement.distance.toStringAsFixed(3)} كم');
    debugPrint(
        'تصحيح شمالي: ${measurement.deltaNorthMeters.toStringAsFixed(2)} متر');
    debugPrint(
        'تصحيح شرقي: ${measurement.deltaEastMeters.toStringAsFixed(2)} متر');
    debugPrint(
        'الزاوية (Azimuth): ${measurement.azimuthMils.toStringAsFixed(0)} ميليم');
    debugPrint('الملاحظات: ${measurement.note ?? 'لا توجد'}');
    debugPrint(
        'الوقت: ${DateTime.fromMillisecondsSinceEpoch(measurement.timestampMillis).toLocal()}');
    debugPrint('═══════════════════════════════════════════════════════════');

    final isNorth = measurement.deltaNorthMeters >= 0;
    final isEast = measurement.deltaEastMeters >= 0;

    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: isCorrection
              ? Colors.red.shade800
              : Theme.of(context).colorScheme.primary,
        );
    final dataStyle = Theme.of(
      context,
    ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600);
    final correctionStyle = Theme.of(
      context,
    ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold);

    return Card(
      elevation: 0,
      color: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- الرأس ---
            Row(
              children: [
                Icon(
                  isEmplacementMeasurement
                      ? Icons.location_on
                      : (isCorrection
                          ? Icons.gps_off
                          : Icons.analytics_outlined),
                  color: isEmplacementMeasurement
                      ? Colors.amber
                      : (isCorrection
                          ? Colors.red
                          : Theme.of(context).colorScheme.primary),
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                    isEmplacementMeasurement
                        ? 'قياس المربض'
                        : (isCorrection ? 'بيانات تصحيح' : 'تفاصيل القياس'),
                    style: titleStyle),
                const Spacer(),
                Text(
                  DateTime.fromMillisecondsSinceEpoch(
                          measurement.timestampMillis)
                      .toLocal()
                      .toString()
                      .split('.')
                      .first,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ),
            const Divider(height: 16, thickness: 0.5),

            // =========================================================
            // عرض مختلف حسب نوع القياس
            // =========================================================
            if (isEmplacementMeasurement) ...[
              // >>> قياس المربض: عرض مبسط (قرب/بعيد + انحراف) فقط <<<
              _buildEmplacementMeasurement(
                context: context,
                dataStyle: dataStyle,
                correctionStyle: correctionStyle,
              ),
            ] else ...[
              // >>> القياس العادي: عرض كامل <<<
              _printNormalMeasurementData(),
              // الزاوية
              Row(
                children: [
                  const Icon(Icons.explore, size: 20, color: Colors.blueGrey),
                  const SizedBox(width: 8),
                  Text('الزاوية (Azimuth): ',
                      style: Theme.of(context).textTheme.bodyMedium),
                  Text(
                    '${measurement.azimuthMils.toStringAsFixed(0)} ميليم',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (isCorrection) ...[
                // عرض التصحيح فقط
                const SizedBox(height: 5),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade200, width: 1.5),
                  ),
                  child: Column(
                    children: [
                      const Text("أوامر التصحيح المطلوبة",
                          style: TextStyle(
                              color: Colors.red,
                              fontSize: 13,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(
                        measurement.note!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // عرض التفاصيل الكاملة
                _buildPointRow(
                  context: context,
                  label: 'الهدف(UTM - ${measurement.zone1}N):',
                  point: measurement.point1Utm,
                  dataStyle: dataStyle,
                ),
                const SizedBox(height: 8),
                _buildPointRow(
                  context: context,
                  label: 'الرماية(UTM - ${measurement.zone2}N):',
                  point: measurement.point2Utm,
                  dataStyle: dataStyle,
                ),
                const SizedBox(height: 7),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 8.0,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildCorrectionChip(
                            isPositive: isNorth,
                            positiveText: 'شمالاً',
                            negativeText: 'جنوباً',
                            value: measurement.deltaNorthMeters,
                            style: correctionStyle,
                          ),
                          _buildCorrectionChip(
                            isPositive: isEast,
                            positiveText: 'شرقاً',
                            negativeText: 'غرباً',
                            value: measurement.deltaEastMeters,
                            style: correctionStyle,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        ' تصحيح'
                        '     ${measurement.deltaEastMeters.abs().toStringAsFixed(2)} متر ${isEast ? 'غرباً' : 'شرقاً'}'
                        '    و    ${measurement.deltaNorthMeters.abs().toStringAsFixed(2)} متر ${isNorth ? 'جنوباً' : 'شمالاً'}    لتكون فوق الهدف.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: const Color.fromARGB(255, 228, 55, 3),
                              fontWeight: FontWeight.w600,
                            ),
                        textAlign: TextAlign.right,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmplacementMeasurement({
    required BuildContext context,
    TextStyle? dataStyle,
    TextStyle? correctionStyle,
  }) {
    final distance = measurement.distance;
    final distanceText = distance >= 1
        ? '${distance.toStringAsFixed(2)} كم'
        : '${(distance * 1000).toStringAsFixed(0)} م';

    final hasCorrectionNote = (measurement.note ?? '').isNotEmpty;

    // قراءة أوامر التصحيح من الملاحظة بدلاً من التخمين
    final String note = measurement.note ?? '';
    final parts = note.split('|').map((p) => p.trim()).toList();
    final String rangeCmd = parts.isNotEmpty ? parts[0] : '';
    final String lateralCmd = parts.length > 1 ? parts[1] : '';

    final bool isRangeDrop =
        rangeCmd.contains('Drop') || rangeCmd.contains('اقصر');
    final String? rangeMeters =
        RegExp(r'(\d+(?:\.\d+)?)').firstMatch(rangeCmd)?.group(1);

    final String? lateralMils =
        RegExp(r'(\d+(?:\.\d+)?)').firstMatch(lateralCmd)?.group(1);
    final bool isLeft = lateralCmd.contains('يسار') ||
        lateralCmd.toLowerCase().contains('left');

    // طباعة بيانات قياس المربض في الكونسول (بعد وجود سقوط فقط)
    debugPrint('🏗️ بيانات قياس المربض:');
    debugPrint('   المسافة: $distanceText');
    if (hasCorrectionNote) {
      debugPrint('   ⚡ أمر المدى: $rangeCmd');
      debugPrint('   ⚡ أمر الانحراف: $lateralCmd');
      debugPrint('   📌 الأوامر المطلوبة كما في الملاحظة:');
      debugPrint('      1️⃣  $rangeCmd');
      debugPrint('      2️⃣  $lateralCmd');
    }
    debugPrint('   معرف المربض: ${measurement.emplacementId}');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade200, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasCorrectionNote) ...[
            // أوامر التصحيح (بعد تحديد السقوط)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color:
                    isRangeDrop ? Colors.red.shade100 : Colors.green.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color:
                      isRangeDrop ? Colors.red.shade400 : Colors.green.shade400,
                  width: 1.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    rangeCmd.isNotEmpty ? rangeCmd : 'أمر مدى غير متوفر',
                    style: correctionStyle?.copyWith(
                      color: isRangeDrop
                          ? Colors.red.shade700
                          : Colors.green.shade700,
                      fontSize: 16,
                    ),
                  ),
                  if (rangeMeters != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '$rangeMeters متر',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isRangeDrop
                                ? Colors.red.shade600
                                : Colors.green.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade400, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    lateralCmd.isNotEmpty ? lateralCmd : 'أمر انحراف غير متوفر',
                    style: correctionStyle?.copyWith(
                      color: Colors.blue.shade700,
                      fontSize: 16,
                    ),
                  ),
                  if (lateralMils != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '$lateralMils ميليم',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.blue.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ] else ...[
            // عرض معلومات فقط قبل تحديد السقوط
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300, width: 1.2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'تم تحديد الهدف. حدد نقطة السقوط لإظهار أوامر التصحيح.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text('المسافة: $distanceText'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPointRow({
    required BuildContext context,
    required String label,
    required proj4.Point point,
    TextStyle? dataStyle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: dataStyle?.copyWith(
            color: Theme.of(
              context,
            ).textTheme.bodySmall?.color?.withOpacity(0.7),
            fontSize: 14,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 16.0, top: 2.0),
          child: Text(
            '(${point.x.toStringAsFixed(0)}, ${point.y.toStringAsFixed(0)})',
            style: dataStyle?.copyWith(letterSpacing: 1.1),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _printNormalMeasurementData() {
    // طباعة بيانات القياس العادي في الكونسول
    debugPrint('📍 بيانات القياس العادي (بدون مربض):');
    debugPrint(
        '   الهدف: (${measurement.point1.latitude.toStringAsFixed(6)}, ${measurement.point1.longitude.toStringAsFixed(6)})');
    debugPrint(
        '   السقوط: (${measurement.point2.latitude.toStringAsFixed(6)}, ${measurement.point2.longitude.toStringAsFixed(6)})');
    debugPrint('   المسافة: ${measurement.distance.toStringAsFixed(3)} كم');
    debugPrint(
        '   تصحيح شمالي: ${measurement.deltaNorthMeters.toStringAsFixed(2)} متر');
    debugPrint(
        '   تصحيح شرقي: ${measurement.deltaEastMeters.toStringAsFixed(2)} متر');
    debugPrint(
        '   الزاوية: ${measurement.azimuthMils.toStringAsFixed(0)} ميليم');
    return const SizedBox.shrink();
  }

  Widget _buildCorrectionChip({
    required bool isPositive,
    required String positiveText,
    required String negativeText,
    required double value,
    TextStyle? style,
  }) {
    final color =
        isPositive ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    final icon = isPositive
        ? (positiveText == 'شمالاً' ? Icons.arrow_upward : Icons.arrow_forward)
        : (positiveText == 'شمالاً' ? Icons.arrow_downward : Icons.arrow_back);

    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '${isPositive ? positiveText : negativeText}: ${value.abs().toStringAsFixed(2)} م',
              style: style?.copyWith(color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
