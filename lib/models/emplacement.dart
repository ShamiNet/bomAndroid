import 'package:google_maps_flutter/google_maps_flutter.dart';

// نموذج بيانات المربض
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
