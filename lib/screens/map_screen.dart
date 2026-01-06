import 'dart:async';
import 'dart:convert';
import 'dart:ui'; // مكتبة مضافة لدعم تأثيرات التغبيش (Blur)
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' show max, min, cos, pi;
import 'package:proj4dart/proj4dart.dart' as proj4;

import 'package:bom/models/distance_measurement.dart';
import 'package:bom/services/map_utils.dart';
import 'package:bom/widgets/measurement_card.dart';
import 'package:bom/screens/web_view_screen.dart';
import 'package:bom/screens/web_tabs_screen.dart';
import 'package:bom/services/export_service.dart';

// --- نموذج بيانات المربض (Emplacement) ---
class Emplacement {
  final String id;
  final String name;
  final LatLng location;

  Emplacement({required this.id, required this.name, required this.location});

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lat': location.latitude,
        'lng': location.longitude,
      };

  static Emplacement fromJson(Map<String, dynamic> json) => Emplacement(
        id: json['id'],
        name: json['name'],
        location: LatLng(json['lat'], json['lng']),
      );
}
// ----------------------------------------

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  LatLng? _centerLatLng;
  proj4.Point? _centerUtmCache;
  DateTime? _lastCameraUpdate;
  final Completer<GoogleMapController> _controller = Completer();

  final List<LatLng> _tappedPoints = [];
  LatLng? _impactPoint;
  bool _isCorrectionMode = false;

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final List<DistanceMeasurement> _distanceMeasurements = [];
  bool _showDistanceList = false;
  MapType _currentMapType = MapType.normal;
  DistanceMeasurement? _selectedMeasurement;
  bool _showPath = true;
  CameraPosition? _initialCameraPosition;
  bool _fixFirstPoint = false;
  bool _addFromCenter = false;
  bool _isRecording = false;
  int _recordDuration = 0;
  Timer? _timer;
  SharedPreferences? _prefs;

  List<Emplacement> _emplacements = [];
  String? _activeEmplacementId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCameraPosition();
      _loadMeasurements();
      _loadEmplacements();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadCameraPosition() async {
    _prefs ??= await SharedPreferences.getInstance();
    final prefs = _prefs!;
    final lat = prefs.getDouble('camera_lat');
    final lng = prefs.getDouble('camera_lng');
    final zoom = prefs.getDouble('camera_zoom');
    setState(() {
      if (lat != null && lng != null && zoom != null) {
        _initialCameraPosition = CameraPosition(
          target: LatLng(lat, lng),
          zoom: zoom,
        );
        _centerLatLng = LatLng(lat, lng);
        try {
          _centerUtmCache = convertLatLngToUtm(_centerLatLng!);
        } catch (_) {
          _centerUtmCache = null;
        }
      } else {
        _initialCameraPosition = const CameraPosition(
          target: LatLng(34.4557784, 36.4936559),
          zoom: 14.4746,
        );
        _centerLatLng = const LatLng(34.4557784, 36.4936559);
      }
    });
  }

  Future<void> _saveCameraPosition(CameraPosition position) async {
    _prefs ??= await SharedPreferences.getInstance();
    final prefs = _prefs!;
    prefs.setDouble('camera_lat', position.target.latitude);
    prefs.setDouble('camera_lng', position.target.longitude);
    prefs.setDouble('camera_zoom', position.zoom);
  }

  Future<void> _loadMeasurements() async {
    _prefs ??= await SharedPreferences.getInstance();
    final prefs = _prefs!;
    final data = prefs.getStringList('distance_measurements');
    if (data != null) {
      setState(() {
        _distanceMeasurements.clear();
        _distanceMeasurements.addAll(
          data
              .map((e) => DistanceMeasurement.fromJson(json.decode(e)))
              .toList(),
        );
        _updateMarkers();
        _updatePolylines();
      });
    }
  }

  Future<void> _saveMeasurements() async {
    _prefs ??= await SharedPreferences.getInstance();
    final prefs = _prefs!;
    final data =
        _distanceMeasurements.map((e) => json.encode(e.toJson())).toList();
    prefs.setStringList('distance_measurements', data);
  }

  Future<void> _loadEmplacements() async {
    _prefs ??= await SharedPreferences.getInstance();
    final prefs = _prefs!;
    final data = prefs.getStringList('saved_emplacements');
    if (data != null) {
      setState(() {
        _emplacements =
            data.map((e) => Emplacement.fromJson(json.decode(e))).toList();
      });
    }
  }

  Future<void> _saveEmplacements() async {
    _prefs ??= await SharedPreferences.getInstance();
    final prefs = _prefs!;
    final data = _emplacements.map((e) => json.encode(e.toJson())).toList();
    await prefs.setStringList('saved_emplacements', data);
  }

  Future<void> _addEmplacement() async {
    if (_centerLatLng == null) return;
    String name = '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حفظ المربض الحالي'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('سيتم حفظ موقع منتصف الشاشة كمربض.'),
            TextField(
              autofocus: true,
              decoration: const InputDecoration(hintText: 'اسم المربض'),
              onChanged: (v) => name = v,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, name),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    if (result != null && result.trim().isNotEmpty) {
      final newEmplacement = Emplacement(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: result.trim(),
        location: _centerLatLng!,
      );
      setState(() {
        _emplacements.add(newEmplacement);
      });
      _saveEmplacements();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ المربض بنجاح')),
      );
    }
  }

  void _deleteEmplacement(String id) {
    setState(() {
      _emplacements.removeWhere((e) => e.id == id);
      if (_activeEmplacementId == id) {
        _deactivateEmplacement();
      }
    });
    _saveEmplacements();
  }

  void _activateEmplacement(Emplacement emp) {
    setState(() {
      _activeEmplacementId = emp.id;
      _tappedPoints.clear();
      _tappedPoints.add(emp.location);
      _fixFirstPoint = true;
      _isCorrectionMode = false;
      _impactPoint = null;
      _updateMarkers();
    });
    _controller.future.then((c) {
      c.animateCamera(CameraUpdate.newLatLng(emp.location));
    });
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم تفعيل المربض: ${emp.name}')),
    );
  }

  void _deactivateEmplacement() {
    setState(() {
      _activeEmplacementId = null;
      _fixFirstPoint = false;
      _tappedPoints.clear();
      _isCorrectionMode = false;
      _impactPoint = null;
      _updateMarkers();
    });
    if (Navigator.canPop(context)) Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم إيقاف المربض')),
    );
  }

  void _showEmplacementsDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'إدارة المرابض',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_location_alt,
                            color: Colors.blue),
                        tooltip: 'إضافة الموقع الحالي',
                        onPressed: () async {
                          Navigator.pop(context);
                          await _addEmplacement();
                        },
                      ),
                    ],
                  ),
                  const Divider(),
                  if (_emplacements.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('لا يوجد مرابض محفوظة'),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: _emplacements.length,
                        itemBuilder: (context, index) {
                          final emp = _emplacements[index];
                          final isActive = emp.id == _activeEmplacementId;
                          return ListTile(
                            leading: Icon(
                              Icons.fort,
                              color: isActive ? Colors.blue : Colors.grey,
                            ),
                            title: Text(emp.name),
                            subtitle: Text(
                                '${emp.location.latitude.toStringAsFixed(4)}, ${emp.location.longitude.toStringAsFixed(4)}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Switch(
                                  value: isActive,
                                  activeColor: Colors.blue,
                                  onChanged: (val) {
                                    if (val) {
                                      _activateEmplacement(emp);
                                    } else {
                                      _deactivateEmplacement();
                                    }
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  onPressed: () {
                                    _deleteEmplacement(emp.id);
                                    setSheetState(() {});
                                  },
                                ),
                              ],
                            ),
                            onTap: () {
                              if (!isActive) _activateEmplacement(emp);
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _createAndSaveMeasurement(LatLng p1, LatLng p2, {String? note}) {
    final double distance = calculateDistance(p1, p2);
    final Map<String, double> disp = calculateDisplacement(p1, p2);
    final double bearing = calculateBearing(p1, p2);
    final double mils = degreesToMils(bearing);

    final measurement = DistanceMeasurement(
      point1: p1,
      point1Utm: convertLatLngToUtm(p1),
      zone1: getUtmZone(p1.longitude),
      point2: p2,
      point2Utm: convertLatLngToUtm(p2),
      zone2: getUtmZone(p2.longitude),
      distance: distance,
      deltaNorthMeters: disp['deltaNorthMeters']!,
      deltaEastMeters: disp['deltaEastMeters']!,
      azimuthMils: mils,
      timestampMillis: DateTime.now().millisecondsSinceEpoch,
      note: note, // تمرير الملاحظة هنا
      emplacementId: _activeEmplacementId, // تمرير معرف المربض
    );

    _distanceMeasurements.add(measurement);
    _saveMeasurements();
  }

  // دالة لإظهار نافذة إدخال UTM
  void _showUtmInputDialog() {
    final xController = TextEditingController();
    final yController = TextEditingController();
    final zoneController =
        TextEditingController(text: '37'); // المنطقة الافتراضية
    String selectedType = 'emplacement'; // القيم: emplacement, target, impact

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.add_location_alt, color: Colors.blue),
            SizedBox(width: 10),
            Text('إضافة إحداثيات UTM'),
          ],
        ),
        content: StatefulBuilder(
          builder: (context, setState) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // اختيار نوع النقطة
                  DropdownButton<String>(
                    value: selectedType,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                          value: 'emplacement',
                          child: Text('🏗️ المربض (نقطة 1)')),
                      DropdownMenuItem(
                          value: 'target', child: Text('🎯 الهدف (نقطة 2)')),
                      DropdownMenuItem(
                          value: 'impact', child: Text('💥 السقوط (للتصحيح)')),
                    ],
                    onChanged: (val) {
                      setState(() => selectedType = val!);
                    },
                  ),
                  const SizedBox(height: 15),
                  // حقول الإدخال
                  TextField(
                    controller: xController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'الإحداثي السيني (X / Easting)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: yController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'الإحداثي الصادي (Y / Northing)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: zoneController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'رقم المنطقة (Zone)',
                      border: OutlineInputBorder(),
                      hintText: 'مثال: 37',
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final double x = double.parse(xController.text.trim());
                final double y = double.parse(yController.text.trim());
                final int zone = int.parse(zoneController.text.trim());

                // 1. التحويل من UTM إلى LatLng
                final LatLng point = convertUtmToLatLng(x, y, zone);

                // 2. معالجة النقطة حسب النوع المختار
                _handleAddUtmPoint(point, selectedType);

                // تحريك الكاميرا للموقع الجديد
                final controller = await _controller.future;
                controller.animateCamera(CameraUpdate.newLatLng(point));

                Navigator.pop(ctx);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('خطأ في الإحداثيات: $e')),
                );
              }
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }

  // دالة مساعدة لمعالجة النقطة المضافة
  void _handleAddUtmPoint(LatLng point, String type) {
    setState(() {
      if (type == 'emplacement') {
        // إذا كان مربضاً، نضعه في بداية القائمة
        if (_tappedPoints.isNotEmpty) {
          // إذا كان هناك نقاط بالفعل، نستبدل الأولى
          _tappedPoints[0] = point;
        } else {
          _tappedPoints.add(point);
        }
        // تنظيف ما بعده لضمان التسلسل الصحيح
        if (_tappedPoints.length > 2) {
          // نحتفظ فقط بالمربض والهدف إذا أضفنا مربض جديد
          final p2 = _tappedPoints[1];
          _tappedPoints.clear();
          _tappedPoints.add(point);
          _tappedPoints.add(p2);
        }
      } else if (type == 'target') {
        // الهدف هو النقطة الثانية
        if (_tappedPoints.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('يرجى تحديد المربض أولاً!')),
          );
          return; // لا يمكن إضافة هدف بدون مربض
        }

        if (_tappedPoints.length >= 2) {
          _tappedPoints[1] = point; // تحديث الهدف الموجود
        } else {
          _tappedPoints.add(point); // إضافة هدف جديد
        }

        // إذا اكتملت النقطتان، نقوم بإنشاء القياس
        if (_tappedPoints.length == 2) {
          _createAndSaveMeasurement(_tappedPoints[0], _tappedPoints[1],
              note: null);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم تحديد الهدف عبر UTM')),
          );
        }
      } else if (type == 'impact') {
        // نقطة السقوط (للتصحيح)
        if (_tappedPoints.length < 2) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('يجب تحديد المربض والهدف أولاً لحساب التصحيح')),
          );
          return;
        }

        _impactPoint = point;
        _isCorrectionMode = true;
        _updateMarkers();
        _updatePolylines();

        // إجراء الحساب فوراً
        Future.delayed(const Duration(milliseconds: 500), () {
          _calculateCorrection();
        });
        return; // الخروج لأن التحديث تم
      }

      // تحديث العلامات والخطوط للحالات العادية
      _updateMarkers();
      _updatePolylines();
    });
  }

  void _calculateCorrection() {
    if (_tappedPoints.length < 2 || _impactPoint == null) return;

    final battery = _tappedPoints[0];
    final target = _tappedPoints[1];
    final impact = _impactPoint!;

    final distToTarget = calculateDistance(battery, target) * 1000;
    final bearingToTarget = calculateBearing(battery, target);
    final distToImpact = calculateDistance(battery, impact) * 1000;

    double rangeDiff = distToImpact - distToTarget;
    String rangeCmd = rangeDiff > 0
        ? "اقصر (Drop) ${rangeDiff.abs().toStringAsFixed(0)}"
        : "اطول (Add) ${rangeDiff.abs().toStringAsFixed(0)}";

    double bearingToImpact = calculateBearing(battery, impact);
    double angleDiffDeg = bearingToImpact - bearingToTarget;

    if (angleDiffDeg > 180) angleDiffDeg -= 360;
    if (angleDiffDeg < -180) angleDiffDeg += 360;

    double angleDiffMils = degreesToMils(angleDiffDeg);

    String lateralCmd = angleDiffMils > 0
        ? "يسار (Left) ${angleDiffMils.abs().toStringAsFixed(0)}"
        : "يمين (Right) ${angleDiffMils.abs().toStringAsFixed(0)}";

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.calculate, color: Colors.red),
            SizedBox(width: 8),
            Text("نتائج التصحيح"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("المدى: $rangeCmd",
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text("الانحراف: $lateralCmd",
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(),
            const Text("المعطيات:", style: TextStyle(color: Colors.grey)),
            Text("مسافة الهدف: ${distToTarget.toStringAsFixed(0)} م"),
            Text("مسافة السقوط: ${distToImpact.toStringAsFixed(0)} م"),
          ],
        ),
        actions: [
          // زر حفظ التصحيح - تم إعادته
          TextButton.icon(
            icon: const Icon(Icons.save_alt),
            label: const Text("حفظ التصحيح"),
            onPressed: () {
              final String note = "$rangeCmd | $lateralCmd";
              setState(() {
                _createAndSaveMeasurement(battery, impact, note: note);
              });
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('تم حفظ بيانات التصحيح في القائمة')),
              );
            },
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
            },
            child: const Text("إغلاق"),
          )
        ],
      ),
    );
  }

  void _onMapTap(LatLng latLng) {
    if (_showDistanceList) {
      setState(() => _showDistanceList = false);
      return;
    }

    final LatLng pointToAdd =
        _addFromCenter && _centerLatLng != null ? _centerLatLng! : latLng;

    // 1. منطق وضع التصحيح (إذا كان مفعلاً)
    if (_isCorrectionMode && _tappedPoints.length >= 2) {
      setState(() {
        _impactPoint = pointToAdd;
        _updateMarkers();
      });
      _calculateCorrection();
      return;
    }

    setState(() {
      // 2. منطق الحفاظ على النقاط
      if (_tappedPoints.length >= 2) {
        if (_fixFirstPoint || _activeEmplacementId != null) {
          _tappedPoints.removeLast();
        } else {
          _tappedPoints.clear();
        }
        _impactPoint = null;
        _selectedMeasurement = null;
        _isCorrectionMode = false;
      }

      if (_activeEmplacementId != null && _tappedPoints.isEmpty) {
        final emp =
            _emplacements.firstWhere((e) => e.id == _activeEmplacementId!);
        _tappedPoints.add(emp.location);
      }

      if (_tappedPoints.isNotEmpty && _tappedPoints.last == pointToAdd) return;

      _tappedPoints.add(pointToAdd);
      _updatePolylines();

      if (_tappedPoints.length == 2) {
        final LatLng p1 = _tappedPoints[0];
        final LatLng p2 = _tappedPoints[1];

        // حفظ القياس العادي (بدون ملاحظات)
        _createAndSaveMeasurement(p1, p2, note: null);

        // الحفاظ على النقاط ليظهر زر التصحيح
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم تحديد الهدف. زر التصحيح (بنفسجي) متاح الآن ↘️'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
      _updateMarkers();
    });
  }

  void _onMarkerTap(MarkerId markerId) {
    setState(() {
      final String id = markerId.value;
      if (_activeEmplacementId != null && id == 'temp_0') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا يمكن حذف المربض المفعل.')),
        );
        return;
      }

      if (id == 'impact_point') {
        _impactPoint = null;
        _updateMarkers();
        return;
      }

      if (id.startsWith('temp_')) {
        final int? index = int.tryParse(id.substring(5));
        if (index != null && index >= 0 && index < _tappedPoints.length) {
          _tappedPoints.removeAt(index);
          _impactPoint = null;
        }
      }
      _updateMarkers();
    });
  }

  void _clearPointsAndMarkers() {
    setState(() {
      if (_activeEmplacementId != null && _tappedPoints.isNotEmpty) {
        final first = _tappedPoints[0];
        _tappedPoints.clear();
        _tappedPoints.add(first);
      } else {
        _tappedPoints.clear();
      }
      _distanceMeasurements.clear();
      _selectedMeasurement = null;
      _impactPoint = null;
      _isCorrectionMode = false;
      _updateMarkers();
      _updatePolylines();
    });
    _saveMeasurements();
  }

  void _toggleMapType() {
    setState(() {
      _currentMapType = (_currentMapType == MapType.normal)
          ? MapType.hybrid
          : (_currentMapType == MapType.hybrid)
              ? MapType.satellite
              : (_currentMapType == MapType.satellite)
                  ? MapType.terrain
                  : MapType.normal;
    });
  }

  void _togglePathVisibility() {
    setState(() {
      _showPath = !_showPath;
      _updatePolylines();
    });
  }

  void _updateMarkers() {
    final center = _centerLatLng;
    const double thresholdMeters = 50000;
    const double clusterRadiusMeters = 200;

    double latCull = double.infinity;
    if (center != null) latCull = thresholdMeters / 111320.0;

    final Map<String, List<_ClusterItem>> cells = {};

    void addPointToCells(LatLng p, String id, Marker Function() buildMarker) {
      if (center != null) {
        if ((p.latitude - center.latitude).abs() > latCull) return;
        final latRad = p.latitude * (pi / 180.0);
        final lonCull = thresholdMeters / (111320.0 * cos(latRad));
        if ((p.longitude - center.longitude).abs() > lonCull) return;
      }
      final latCell = clusterRadiusMeters / 111320.0;
      final lonCell =
          clusterRadiusMeters / (111320.0 * cos(p.latitude * (pi / 180.0)));
      final int latIdx = (p.latitude / latCell).floor();
      final int lonIdx = (p.longitude / lonCell).floor();
      final key = '$latIdx:$lonIdx';
      cells.putIfAbsent(key, () => []).add(_ClusterItem(p, id, buildMarker));
    }

    for (int i = 0; i < _tappedPoints.length; i++) {
      final p = _tappedPoints[i];
      final bool isActiveEmplacement = (i == 0 && _activeEmplacementId != null);

      addPointToCells(
          p,
          'temp_$i',
          () => Marker(
                markerId: MarkerId('temp_$i'),
                position: p,
                icon: BitmapDescriptor.defaultMarkerWithHue(isActiveEmplacement
                    ? BitmapDescriptor.hueBlue
                    : (i == 0
                        ? BitmapDescriptor.hueAzure
                        : BitmapDescriptor.hueRose)),
                zIndex: isActiveEmplacement ? 10 : 5,
                infoWindow: isActiveEmplacement
                    ? const InfoWindow(title: 'مربض مفعل')
                    : const InfoWindow(title: 'هدف'),
                onTap: () => _onMarkerTap(MarkerId('temp_$i')),
              ));
    }

    if (_impactPoint != null) {
      addPointToCells(
          _impactPoint!,
          'impact_point',
          () => Marker(
                markerId: const MarkerId('impact_point'),
                position: _impactPoint!,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueViolet),
                infoWindow: const InfoWindow(title: 'نقطة السقوط'),
                onTap: () => _onMarkerTap(const MarkerId('impact_point')),
              ));
    }

    for (var measurement in _distanceMeasurements) {
      addPointToCells(
          measurement.point1,
          'start_${measurement.point1.hashCode}',
          () => Marker(
                markerId: MarkerId('start_${measurement.point1.hashCode}'),
                position: measurement.point1,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueGreen),
              ));
      addPointToCells(
          measurement.point2,
          'end_${measurement.point2.hashCode}',
          () => Marker(
                markerId: MarkerId('end_${measurement.point2.hashCode}'),
                position: measurement.point2,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueOrange),
              ));
    }

    final Set<Marker> newMarkers = {};
    cells.forEach((key, list) {
      if (list.length == 1) {
        newMarkers.add(list.first.buildMarker());
      } else {
        double latSum = 0, lonSum = 0;
        for (var it in list) {
          latSum += it.point.latitude;
          lonSum += it.point.longitude;
        }
        final avg = LatLng(latSum / list.length, lonSum / list.length);
        newMarkers.add(Marker(
            markerId: MarkerId('cluster_$key'),
            position: avg,
            icon:
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: InfoWindow(title: '${list.length} نقاط'),
            onTap: () async {
              final controller = await _controller.future;
              controller.animateCamera(CameraUpdate.newLatLngZoom(avg, 12));
            }));
      }
    });

    _markers.clear();
    _markers.addAll(newMarkers);
  }

  void _updatePolylines() {
    _polylines.clear();
    if (_selectedMeasurement != null && _showPath) {
      _polylines.add(Polyline(
        polylineId: const PolylineId('selected_path'),
        points: [_selectedMeasurement!.point1, _selectedMeasurement!.point2],
        color: Theme.of(context).colorScheme.secondary,
        width: 5,
        patterns: [PatternItem.dash(20), PatternItem.gap(10)],
      ));
    }

    if (_impactPoint != null && _tappedPoints.length >= 2) {
      _polylines.add(Polyline(
        polylineId: const PolylineId('impact_line'),
        points: [_tappedPoints[0], _impactPoint!],
        color: Colors.purpleAccent,
        width: 2,
      ));
      _polylines.add(Polyline(
        polylineId: const PolylineId('error_line'),
        points: [_tappedPoints[1], _impactPoint!],
        color: Colors.red,
        width: 2,
        patterns: [PatternItem.dot, PatternItem.gap(5)],
      ));
    }
  }

  Future<void> _goToSelectedMeasurement(DistanceMeasurement measurement) async {
    final GoogleMapController controller = await _controller.future;
    LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(
        min(measurement.point1.latitude, measurement.point2.latitude),
        min(measurement.point1.longitude, measurement.point2.longitude),
      ),
      northeast: LatLng(
        max(measurement.point1.latitude, measurement.point2.latitude),
        max(measurement.point1.longitude, measurement.point2.longitude),
      ),
    );
    controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
  }

  String _formatDuration(int totalSeconds) {
    final duration = Duration(seconds: totalSeconds);
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  // --- دالة معدلة لإنشاء أزرار ثلاثية الأبعاد (3D Style) ---
  Widget _buildSideButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
    Color color = Colors.black87,
    Color backgroundColor = Colors.white,
    bool isActive = false,
  }) {
    // تحديد الألوان بناءً على حالة التفعيل
    final Color baseColor = isActive ? color : backgroundColor;
    final Color iconColor = isActive ? Colors.white : color;

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      // تصميم الزر ليبدو مجسماً (3D)
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isActive
              ? [
                  color.withOpacity(0.8),
                  color,
                ]
              : [
                  Colors.white,
                  Colors.grey.shade300,
                ],
        ),
        boxShadow: [
          // ظل خارجي عميق
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(4, 4),
          ),
          // إضاءة علوية (Highlight)
          BoxShadow(
            color: Colors.white.withOpacity(0.9),
            blurRadius: 4,
            offset: const Offset(-2, -2),
          ),
        ],
        border: Border.all(
          color: Colors.white.withOpacity(0.5),
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          splashColor: color.withOpacity(0.3),
          child: Container(
            width: 50,
            height: 50,
            alignment: Alignment.center,
            child: Icon(
              icon,
              color: iconColor,
              size: 24,
              shadows: [
                Shadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 2,
                  offset: const Offset(1, 1),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- دالة مساعدة لإنشاء صناديق المعلومات الزجاجية ---
  Widget _buildGlassInfoBox(BuildContext context, {required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6), // خلفية داكنة نصف شفافة
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
              fontFamily: 'Roboto', // خط نظيف
              shadows: [
                Shadow(
                  blurRadius: 2,
                  color: Colors.black,
                  offset: Offset(1, 1),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_initialCameraPosition == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final screenWidth = MediaQuery.of(context).size.width;

    bool canCorrect = _tappedPoints.length >= 2;

    return Scaffold(
      extendBodyBehindAppBar: true, // يجعل الخريطة تمتد خلف البار العلوي
      appBar: AppBar(
        elevation: 0,
        backgroundColor:
            Colors.transparent, // شفاف ليعمل مع extendBodyBehindAppBar
        flexibleSpace: ClipRRect(
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(0)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    (_isCorrectionMode
                            ? Colors.purple.shade900
                            : Theme.of(context).colorScheme.primary)
                        .withOpacity(0.85),
                    Theme.of(context).colorScheme.primary.withOpacity(0.6),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withOpacity(0.2),
                    width: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
        title: Text(
          _isCorrectionMode ? 'حدد نقطة السقوط' : 'BOM',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            shadows: [
              Shadow(
                color: Colors.black45,
                blurRadius: 2,
                offset: Offset(1, 1),
              )
            ],
          ),
        ),
        actions: [
          // 1. زر إدارة المرابض
          IconButton(
            icon: Icon(
              Icons.fort,
              color: _activeEmplacementId != null ? Colors.amber : Colors.white,
              shadows: const [
                Shadow(
                    color: Colors.black54, blurRadius: 3, offset: Offset(1, 1))
              ],
            ),
            tooltip: 'إدارة المرابض',
            onPressed: _showEmplacementsDialog,
          ),

          // 2. مؤشر التسجيل
          if (_isRecording)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Container(
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 4)
                    ]),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.fiber_manual_record,
                        color: Colors.red, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      _formatDuration(_recordDuration),
                      style: const TextStyle(
                          color: Colors.black, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),

          // 3. زر إضافة إحداثيات UTM
          IconButton(
            icon: const Icon(Icons.add_location_alt_outlined),
            tooltip: 'إضافة UTM',
            onPressed: _showUtmInputDialog,
          ),

          // 4. زر فتح الويب
          IconButton(
            icon: const Icon(Icons.language),
            tooltip: 'فتح ويب',
            onPressed: () async {
              final x = await showDialog<String>(
                context: context,
                builder: (context) {
                  String value = '';
                  return AlertDialog(
                    title: const Text('أدخل رقم x'),
                    content: TextField(
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: 'مثال: 123'),
                      onChanged: (v) => value = v,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('إلغاء'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, value),
                        child: const Text('فتح'),
                      ),
                    ],
                  );
                },
              );
              if (x != null && x.trim().isNotEmpty) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WebViewScreen(x: x.trim()),
                    fullscreenDialog: true,
                  ),
                );
              }
            },
          ),

          // 5. زر التبويبات
          IconButton(
            icon: const Icon(Icons.tab),
            tooltip: 'Tabs',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => WebTabsScreen()),
              );
            },
          ),

          // 6. زر تصدير PDF
          IconButton(
            icon: Icon(Icons.picture_as_pdf),
            tooltip: 'تصدير PDF',
            onPressed: () {
              if (_selectedMeasurement == null &&
                  _distanceMeasurements.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('لا يوجد قياسات')),
                );
                return;
              }
              showModalBottomSheet(
                context: context,
                builder: (ctx) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Builder(
                      builder: (context) {
                        final exportService = ExportService();
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.share),
                              title: const Text('مشاركة PDF'),
                              onTap: () {
                                Navigator.pop(ctx);
                                if (_selectedMeasurement == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content:
                                            Text('الرجاء تحديد قياس أولاً')),
                                  );
                                  return;
                                }
                                exportService.exportMeasurementToPdf(
                                  context: context,
                                  measurement: _selectedMeasurement!,
                                  description: 'تفاصيل القياس المحدد',
                                  saveToDownloads: false,
                                );
                              },
                            ),
                            if (_distanceMeasurements.isNotEmpty)
                              ListTile(
                                leading: const Icon(Icons.library_books),
                                title: const Text('تصدير جميع القياسات'),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  exportService.exportAllMeasurementsToPdf(
                                    context: context,
                                    measurements: _distanceMeasurements,
                                    title: 'جميع القياسات',
                                    description: 'تطبيق القياس',
                                    saveToDownloads: true,
                                  );
                                },
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            mapType: _currentMapType,
            initialCameraPosition: _initialCameraPosition!,
            // --- تفعيل الخصائص ثلاثية الأبعاد ---
            tiltGesturesEnabled: true, // السماح بإمالة الخريطة
            buildingsEnabled: true, // إظهار المباني المجسمة
            compassEnabled: true,
            // ------------------------------------
            onMapCreated: (GoogleMapController controller) {
              _controller.complete(controller);
            },
            onTap: _onMapTap,
            onCameraMove: (CameraPosition position) {
              final now = DateTime.now();
              final shouldUpdate = _lastCameraUpdate == null ||
                  now.difference(_lastCameraUpdate!).inMilliseconds > 300;
              _lastCameraUpdate = now;
              _centerLatLng = position.target;
              if (shouldUpdate) {
                _saveCameraPosition(position);
                setState(() {
                  _centerLatLng = position.target;
                  try {
                    _centerUtmCache = convertLatLngToUtm(_centerLatLng!);
                  } catch (_) {
                    _centerUtmCache = null;
                  }
                });
              }
            },
            markers: _markers,
            polylines: _polylines,
            myLocationButtonEnabled: false,
            myLocationEnabled: false,
            mapToolbarEnabled: false,
            zoomControlsEnabled: false,
            zoomGesturesEnabled: true,
          ),

          // --- عرض الإحداثيات (نمط HUD زجاجي) ---
          Positioned(
            left: 10,
            top: 100, // تم التعديل لأن الـ AppBar شفاف الآن
            child: _buildGlassInfoBox(
              context,
              child: Text(
                _centerLatLng == null
                    ? '—'
                    : '${_centerLatLng!.latitude.toStringAsFixed(6)}, ${_centerLatLng!.longitude.toStringAsFixed(6)}',
                textAlign: TextAlign.right,
              ),
            ),
          ),
          Positioned(
            left: 10,
            top: 140, // مسافة أسفل المربع الأول
            child: _buildGlassInfoBox(
              context,
              child: Builder(
                builder: (context) {
                  if (_centerLatLng == null) return const Text('—');
                  final utm = _centerUtmCache ??
                      (_centerLatLng != null
                          ? (() {
                              try {
                                final p = convertLatLngToUtm(_centerLatLng!);
                                _centerUtmCache = p;
                                return p;
                              } catch (_) {
                                return null;
                              }
                            })()
                          : null);
                  final zone = _centerLatLng == null
                      ? 0
                      : getUtmZone(_centerLatLng!.longitude);
                  return Text(
                    utm == null
                        ? 'UTM: --'
                        : 'UTM: Zone< $zone > ${utm.x.toStringAsFixed(0)}, ${utm.y.toStringAsFixed(0)}',
                    textAlign: TextAlign.right,
                  );
                },
              ),
            ),
          ),

          // --- القائمة الجانبية (3D Buttons) ---
          Positioned(
            top: 100, // مقابل الإحداثيات
            right: 15,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. زر نوع الخريطة
                _buildSideButton(
                  icon: Icons.satellite_alt_outlined,
                  tooltip: 'تغيير نوع الخريطة',
                  onPressed: _toggleMapType,
                  color: Colors.blue.shade700,
                  isActive: _currentMapType != MapType.normal,
                ),

                // 2. زر إظهار/إخفاء قائمة القياسات
                _buildSideButton(
                  icon: _showDistanceList
                      ? Icons.layers_clear_outlined
                      : Icons.layers_outlined,
                  tooltip:
                      _showDistanceList ? 'إخفاء القياسات' : 'إظهار القياسات',
                  onPressed: () {
                    setState(() {
                      _showDistanceList = !_showDistanceList;
                    });
                  },
                  isActive: _showDistanceList,
                  color: Colors.amber.shade700,
                ),

                // 3. زر تثبيت النقطة الأولى
                _buildSideButton(
                  icon:
                      _fixFirstPoint ? Icons.push_pin : Icons.push_pin_outlined,
                  tooltip: _fixFirstPoint
                      ? 'إلغاء تثبيت الأولى'
                      : 'تثبيت النقطة الأولى',
                  onPressed: () {
                    if (_activeEmplacementId != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content:
                                Text('قم بإلغاء تفعيل المربض لإلغاء التثبيت')),
                      );
                      return;
                    }
                    setState(() {
                      _fixFirstPoint = !_fixFirstPoint;
                    });
                  },
                  isActive: _fixFirstPoint,
                  color: Colors.red.shade700,
                ),

                // 4. زر وضع المركز (التصويب)
                _buildSideButton(
                  icon: _addFromCenter ? Icons.gps_fixed : Icons.gps_not_fixed,
                  tooltip:
                      _addFromCenter ? 'إلغاء وضع المركز' : 'تفعيل وضع المركز',
                  onPressed: () {
                    setState(() {
                      _addFromCenter = !_addFromCenter;
                    });
                  },
                  isActive: _addFromCenter,
                  color: Colors.green.shade700,
                ),

                // 5. زر إظهار المسار
                if (_selectedMeasurement != null)
                  _buildSideButton(
                    icon: _showPath
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    tooltip: _showPath ? 'إخفاء المسار' : 'إظهار المسار',
                    onPressed: _togglePathVisibility,
                    color: Colors.purple.shade700,
                    isActive: true,
                  ),
              ],
            ),
          ),

          // --- إشارة التصويب في المنتصف ---
          Align(
            alignment: Alignment.center,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.5),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 5,
                      spreadRadius: 2),
                ],
              ),
              child: const Icon(Icons.gps_fixed,
                  color: Color(0xFF00796B), size: 10),
            ),
          ),

          // --- القائمة الجانبية المنبثقة للقياسات ---
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            top: 0,
            bottom: 0,
            // تغيير الاتجاه ليكون من اليسار لليمين أو تغطية كاملة حسب الرغبة، هنا أبقيته كما هو
            right: _showDistanceList ? 0 : -screenWidth,
            width: screenWidth * 0.85,
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(25),
                bottomLeft: Radius.circular(25),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .background
                        .withOpacity(0.85),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(25),
                      bottomLeft: Radius.circular(25),
                    ),
                    border: Border(
                      left: BorderSide(
                          color: Colors.white.withOpacity(0.3), width: 1),
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 5),
                    ],
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 50), // مساحة للـ AppBar
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          'القياسات المحفوظة',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              const Shadow(
                                  color: Colors.black12,
                                  offset: Offset(1, 1),
                                  blurRadius: 2)
                            ],
                          ),
                        ),
                      ),
                      const Divider(indent: 16, endIndent: 16),
                      Expanded(
                        child: _distanceMeasurements.isEmpty
                            ? const Center(
                                child: Text('لا توجد قياسات محفوظة.'))
                            : ListView.builder(
                                itemCount: _distanceMeasurements.length,
                                itemBuilder: (context, index) {
                                  final measurement =
                                      _distanceMeasurements[index];

                                  return Dismissible(
                                    key: Key(measurement.hashCode.toString()),
                                    direction: DismissDirection.endToStart,
                                    onDismissed: (direction) {
                                      setState(() {
                                        _distanceMeasurements.removeAt(index);
                                        if (_selectedMeasurement ==
                                            measurement) {
                                          _selectedMeasurement = null;
                                        }
                                        _updateMarkers();
                                        _updatePolylines();
                                      });
                                      _saveMeasurements();
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text('تم حذف القياس'),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    },
                                    background: Container(
                                      color: Colors.redAccent,
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 20.0),
                                      child: const Icon(Icons.delete_forever,
                                          color: Colors.white),
                                    ),
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          if (_selectedMeasurement ==
                                              measurement) {
                                            _selectedMeasurement = null;
                                          } else {
                                            _selectedMeasurement = measurement;
                                          }
                                          _updatePolylines();
                                          if (_selectedMeasurement != null) {
                                            _goToSelectedMeasurement(
                                                _selectedMeasurement!);
                                          }
                                        });
                                      },
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(
                                            horizontal: 10.0, vertical: 6.0),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(15.0),
                                          // تأثير البطاقة
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: _selectedMeasurement ==
                                                    measurement
                                                ? [
                                                    Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                        .withOpacity(0.2),
                                                    Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                        .withOpacity(0.05)
                                                  ]
                                                : [
                                                    Colors.white
                                                        .withOpacity(0.7),
                                                    Colors.white
                                                        .withOpacity(0.4)
                                                  ],
                                          ),
                                          border: Border.all(
                                            color: _selectedMeasurement ==
                                                    measurement
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .primary
                                                : Colors.white.withOpacity(0.5),
                                            width: 1.5,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withOpacity(0.05),
                                              blurRadius: 5,
                                              offset: const Offset(2, 2),
                                            ),
                                          ],
                                        ),
                                        child: MeasurementCard(
                                            measurement: measurement),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // --- رسالة وضع التصحيح (تنبيه HUD) ---
          if (_isCorrectionMode)
            Positioned(
              top: 200, // تحت الأزرار العلوية
              left: 30,
              right: 400, // مساحة للأزرار الجانبية
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.5), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.red.withOpacity(0.3),
                            blurRadius: 15,
                            spreadRadius: 2)
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: Colors.white, size: 28),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "وضع التصحيح مفعل\nاضغط على مكان السقوط",
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // --- زر التصحيح العائم ---
          if (canCorrect) ...[
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                      color: (_isCorrectionMode ? Colors.red : Colors.purple)
                          .withOpacity(0.4),
                      blurRadius: 10,
                      spreadRadius: 2)
                ],
              ),
              child: FloatingActionButton.extended(
                heroTag: 'correction_btn',
                onPressed: () {
                  setState(() {
                    _isCorrectionMode = !_isCorrectionMode;
                    if (_isCorrectionMode) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'اضغط الآن على مكان سقوط القذيفة في الخريطة')),
                      );
                    } else {
                      _impactPoint = null;
                      _updateMarkers();
                    }
                  });
                },
                label:
                    Text(_isCorrectionMode ? 'إلغاء التصحيح' : 'وضع التصحيح'),
                icon: Icon(_isCorrectionMode ? Icons.close : Icons.gps_off),
                backgroundColor:
                    _isCorrectionMode ? Colors.redAccent : Colors.purpleAccent,
                foregroundColor: Colors.white,
                elevation: 0, // نستخدم الـ Shadow الخاص بنا
              ),
            ),
            const SizedBox(height: 12),
          ],

          // --- زر مسح الكل ---
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                    color: Colors.red.withOpacity(0.4),
                    blurRadius: 10,
                    spreadRadius: 2)
              ],
            ),
            child: FloatingActionButton.extended(
              heroTag: 'clear_btn',
              onPressed: _clearPointsAndMarkers,
              label: const Text('مسح الكل'),
              icon: const Icon(Icons.delete_sweep_outlined),
              backgroundColor: Colors.red.shade800,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClusterItem {
  final LatLng point;
  final String id;
  final Marker Function() buildMarker;

  _ClusterItem(this.point, this.id, this.buildMarker);
}
