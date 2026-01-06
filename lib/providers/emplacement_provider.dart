import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/emplacement.dart';

// تعريف المزود (Provider)
final emplacementsProvider =
    StateNotifierProvider<EmplacementNotifier, List<Emplacement>>((ref) {
  return EmplacementNotifier();
});

// منطق إدارة الحالة
class EmplacementNotifier extends StateNotifier<List<Emplacement>> {
  EmplacementNotifier() : super([]) {
    _loadEmplacements();
  }

  // تحميل المرابض
  Future<void> _loadEmplacements() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList('saved_emplacements');
    if (data != null) {
      state = data.map((e) => Emplacement.fromJson(json.decode(e))).toList();
    }
  }

  // حفظ المرابض
  Future<void> _saveEmplacements() async {
    final prefs = await SharedPreferences.getInstance();
    final data = state.map((e) => json.encode(e.toJson())).toList();
    await prefs.setStringList('saved_emplacements', data);
  }

  // إضافة مربض
  Future<void> addEmplacement(String name, LatLng location) async {
    final newEmplacement = Emplacement(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      location: location,
    );
    state = [...state, newEmplacement];
    await _saveEmplacements();
  }

  // حذف مربض
  Future<void> deleteEmplacement(String id) async {
    state = state.where((e) => e.id != id).toList();
    await _saveEmplacements();
  }
}
