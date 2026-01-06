import 'dart:math'
    show sin, cos, sqrt, atan2, pi, log, tan; // تم إضافة log و tan هنا
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:proj4dart/proj4dart.dart' as proj4;
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

int getUtmZone(double longitude) {
  return (longitude + 180) ~/ 6 + 1;
}

proj4.Point convertLatLngToUtm(LatLng latLng) {
  final int zone = getUtmZone(latLng.longitude);
  var projSrc = proj4.Projection.get('EPSG:4326')!;
  var projDst = proj4.Projection.get('EPSG:326$zone') ??
      proj4.Projection.add(
        'EPSG:326$zone',
        '+proj=utm +zone=$zone +datum=WGS84 +units=m +no_defs',
      );
  var pointSrc = proj4.Point(x: latLng.longitude, y: latLng.latitude);
  var pointDst = projSrc.transform(projDst, pointSrc);
  return pointDst;
}

double calculateDistance(LatLng p1, LatLng p2) {
  const double earthRadius = 6371; // km
  double lat1Rad = p1.latitude * pi / 180;
  double lon1Rad = p1.longitude * pi / 180;
  double lat2Rad = p2.latitude * pi / 180;
  double lon2Rad = p2.longitude * pi / 180;
  double dLat = lat2Rad - lat1Rad;
  double dLon = lon2Rad - lon1Rad;
  double a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1Rad) * cos(lat2Rad) * sin(dLon / 2) * sin(dLon / 2);
  double c = 2 * atan2(sqrt(a), sqrt(1 - a));
  double distance = earthRadius * c;

  if (kDebugMode) {
    debugPrint('Point 1: (${p1.latitude}, ${p1.longitude})');
    debugPrint('Point 2: (${p2.latitude}, ${p2.longitude})');
    debugPrint('Calculated Distance: ${distance * 1000} meters');
  }

  return distance;
}

Map<String, double> calculateDisplacement(LatLng p1, LatLng p2) {
  const double earthRadiusMeters = 6371000;
  double lat1Rad = p1.latitude * pi / 180;
  double lon1Rad = p1.longitude * pi / 180;
  double lat2Rad = p2.latitude * pi / 180;
  double lon2Rad = p2.longitude * pi / 180;
  double dLat = lat2Rad - lat1Rad;
  double dLon = lon2Rad - lon1Rad;
  double latMid = (lat1Rad + lat2Rad) / 2;
  double metersPerDegreeLat = earthRadiusMeters * (pi / 180);
  double metersPerDegreeLon = earthRadiusMeters * cos(latMid) * (pi / 180);
  double deltaNorthMeters = dLat * (180 / pi) * metersPerDegreeLat;
  double deltaEastMeters = dLon * (180 / pi) * metersPerDegreeLon;
  return {
    'deltaNorthMeters': deltaNorthMeters,
    'deltaEastMeters': deltaEastMeters,
  };
}

// 1. دالة لحساب الزاوية (Bearing) بالدرجات من p1 إلى p2
double calculateBearing(LatLng start, LatLng end) {
  double startLat = start.latitude * pi / 180;
  double startLong = start.longitude * pi / 180;
  double endLat = end.latitude * pi / 180;
  double endLong = end.longitude * pi / 180;

  double dLong = endLong - startLong;

  double dPhi =
      log(tan(endLat / 2.0 + pi / 4.0) / tan(startLat / 2.0 + pi / 4.0));
  if (dLong.abs() > pi) {
    if (dLong > 0.0) {
      dLong = -(2.0 * pi - dLong);
    } else {
      dLong = (2.0 * pi + dLong);
    }
  }

  double bearing = (atan2(dLong, dPhi) * 180.0 / pi);

  // تحويل النتيجة لتكون من 0 إلى 360 درجة
  return (bearing + 360.0) % 360.0;
}

LatLng convertUtmToLatLng(double x, double y, int zone) {
  // تعريف نظام الإحداثيات UTM للمنطقة المحددة
  var projSrc = proj4.Projection.get('EPSG:326$zone') ??
      proj4.Projection.add(
        'EPSG:326$zone',
        '+proj=utm +zone=$zone +datum=WGS84 +units=m +no_defs',
      );

  // تعريف نظام WGS84 (الذي تستخدمه خرائط جوجل)
  var projDst = proj4.Projection.get('EPSG:4326')!;

  // إنشاء نقطة UTM
  var pointSrc = proj4.Point(x: x, y: y);

  // التحويل
  var pointDst = projSrc.transform(projDst, pointSrc);

  // إرجاع النتيجة كـ LatLng (انتبه: proj4 يعيد y=lat, x=long)
  return LatLng(pointDst.y, pointDst.x);
}

// 2. دالة لتحويل الدرجات إلى ميليم (النظام 6400)
double degreesToMils(double degrees) {
  // المعادلة: (الدرجات / 360) * 6400
  return (degrees / 360.0) * 6400.0;
}
