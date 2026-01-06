import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:proj4dart/proj4dart.dart' as proj4;

class DistanceMeasurement {
  final LatLng point1;
  final proj4.Point point1Utm;
  final int zone1;
  final LatLng point2;
  final proj4.Point point2Utm;
  final int zone2;
  final double distance;
  final double deltaNorthMeters;
  final double deltaEastMeters;
  final int timestampMillis;
  final double azimuthMils;
  final String? note; // حقل جديد للملاحظات (التصحيح)
  final String? emplacementId; // معرف المربض إن وجد

  DistanceMeasurement({
    required this.point1,
    required this.point1Utm,
    required this.zone1,
    required this.point2,
    required this.point2Utm,
    required this.zone2,
    required this.distance,
    required this.deltaNorthMeters,
    required this.deltaEastMeters,
    required this.timestampMillis,
    required this.azimuthMils,
    this.note, // اختياري
    this.emplacementId, // اختياري
  });

  Map<String, dynamic> toJson() => {
        'point1': {'lat': point1.latitude, 'lng': point1.longitude},
        'point1Utm': {'x': point1Utm.x, 'y': point1Utm.y},
        'zone1': zone1,
        'point2': {'lat': point2.latitude, 'lng': point2.longitude},
        'point2Utm': {'x': point2Utm.x, 'y': point2Utm.y},
        'zone2': zone2,
        'distance': distance,
        'deltaNorthMeters': deltaNorthMeters,
        'deltaEastMeters': deltaEastMeters,
        'timestampMillis': timestampMillis,
        'azimuthMils': azimuthMils,
        'note': note, // حفظ الملاحظة
        'emplacementId': emplacementId, // حفظ معرف المربض
      };

  static DistanceMeasurement fromJson(Map<String, dynamic> json) =>
      DistanceMeasurement(
        point1: LatLng(json['point1']['lat'], json['point1']['lng']),
        point1Utm: proj4.Point(
          x: json['point1Utm']['x'],
          y: json['point1Utm']['y'],
        ),
        zone1: json['zone1'],
        point2: LatLng(json['point2']['lat'], json['point2']['lng']),
        point2Utm: proj4.Point(
          x: json['point2Utm']['x'],
          y: json['point2Utm']['y'],
        ),
        zone2: json['zone2'],
        distance: (json['distance'] as num).toDouble(),
        deltaNorthMeters: (json['deltaNorthMeters'] as num).toDouble(),
        deltaEastMeters: (json['deltaEastMeters'] as num).toDouble(),
        timestampMillis:
            json['timestampMillis'] ?? DateTime.now().millisecondsSinceEpoch,
        azimuthMils: (json['azimuthMils'] as num?)?.toDouble() ?? 0.0,
        note: json['note'], // استرجاع الملاحظة
        emplacementId: json['emplacementId'], // استرجاع معرف المربض
      );
}
