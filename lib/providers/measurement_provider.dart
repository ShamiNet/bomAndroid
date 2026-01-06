import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/distance_measurement.dart';
import '../services/api_service.dart'; // ✅ إضافة الاستيراد

final measurementsProvider =
    StateNotifierProvider<MeasurementNotifier, List<DistanceMeasurement>>((
  ref,
) {
  return MeasurementNotifier();
});

class MeasurementNotifier extends StateNotifier<List<DistanceMeasurement>> {
  MeasurementNotifier() : super([]) {
    _loadMeasurements();
  }

  Future<void> _loadMeasurements() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList('distance_measurements');
    if (data != null) {
      state = data
          .map((e) => DistanceMeasurement.fromJson(json.decode(e)))
          .toList();
    }
  }

  Future<void> _saveMeasurements() async {
    final prefs = await SharedPreferences.getInstance();
    final data = state.map((e) => json.encode(e.toJson())).toList();
    await prefs.setStringList('distance_measurements', data);
  }

  // ✅ الدالة المعدلة للإرسال للسيرفر
  Future<void> addMeasurement(DistanceMeasurement measurement) async {
    // 1. تحديث الواجهة والحفظ المحلي فوراً
    state = [...state, measurement];
    await _saveMeasurements();

    // 2. محاولة الإرسال للسيرفر في الخلفية
    try {
      ApiService().saveMeasurement(measurement).then((success) {
        if (success) {
          print("✅ تمت المزامنة مع السيرفر: ${measurement.distance}");
        } else {
          print("⚠️ فشلت المزامنة، تم الحفظ محلياً فقط");
        }
      });
    } catch (e) {
      print("❌ خطأ في الاتصال بالسيرفر: $e");
    }
  }

  Future<void> deleteMeasurement(DistanceMeasurement measurement) async {
    state = state.where((m) => m != measurement).toList();
    await _saveMeasurements();
  }

  Future<void> clearMeasurements() async {
    // 1. الحذف المحلي
    state = [];
    await _saveMeasurements();

    // 2. الحذف من السيرفر
    ApiService().clearAllMeasurements().then((success) {
      if (success) {
        print("✅ تمت تصفية السيرفر والهاتف معاً");
      }
    });
  }
}
