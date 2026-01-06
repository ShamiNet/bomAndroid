import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/distance_measurement.dart';

class ApiService {
  // عنوان السيرفر الخاص بك
  static const String _baseUrl = 'http://72.60.80.201:3002';

  // 🔐 مفتاح الحماية (يجب أن يطابق الموجود في server.js)
  static const String _apiSecret = "Shami_Top_Secret_777";

  // دالة مساعدة لتجهيز الترويسة (Headers) مع مفتاح الحماية
  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'x-api-key': _apiSecret,
      };

  // 1. دالة حفظ قياس جديد
  Future<bool> saveMeasurement(DistanceMeasurement measurement) async {
    try {
      final url = Uri.parse('$_baseUrl/api/addMeasurement');
      final body = jsonEncode(measurement.toJson());

      print("📡 محاولة الاتصال بـ: $url");

      final response = await http.post(
        url,
        headers: _headers, // ✅ استخدام الترويسة المحمية
        body: body,
      );

      if (response.statusCode == 200) {
        print("✅ تم إرسال القياس للسيرفر بنجاح");
        return true;
      } else if (response.statusCode == 403) {
        print("⛔ تم رفض الاتصال: مفتاح الحماية خاطئ!");
        return false;
      } else {
        print("❌ فشل الإرسال: ${response.body}");
        return false;
      }
    } catch (e) {
      print("❌ خطأ اتصال بالسيرفر: $e");
      return false;
    }
  }

  // 2. دالة حذف جميع القياسات من السيرفر
  Future<bool> clearAllMeasurements() async {
    try {
      final url = Uri.parse('$_baseUrl/api/clearMeasurements');

      final response = await http.delete(
        url,
        headers: _headers, // ✅ استخدام الترويسة المحمية
      );

      if (response.statusCode == 200) {
        print("🗑️ تم مسح السيرفر بنجاح");
        return true;
      } else {
        print("❌ فشل المسح: ${response.statusCode}");
        return false;
      }
    } catch (e) {
      print("❌ خطأ اتصال أثناء الحذف: $e");
      return false;
    }
  }

  // 3. دالة جلب القياسات من السيرفر
  Future<List<DistanceMeasurement>> fetchMeasurements() async {
    try {
      final url = Uri.parse('$_baseUrl/api/getMeasurements');

      final response =
          await http.get(url, headers: _headers // ✅ استخدام الترويسة المحمية
              );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);

        if (jsonResponse['success'] == true) {
          final List<dynamic> data = jsonResponse['data'];
          // تحويل البيانات القادمة إلى كائنات DistanceMeasurement
          return data
              .map((item) => DistanceMeasurement.fromJson(item))
              .toList();
        }
      } else {
        print("⚠️ فشل جلب البيانات: ${response.statusCode}");
      }
    } catch (e) {
      print("❌ خطأ في جلب القياسات: $e");
    }
    return []; // إعادة قائمة فارغة في حال الفشل
  }

  // جلب قائمة المستخدمين
  Future<List<dynamic>> getAllUsers() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/api/admin/users'),
          headers: _headers);
      if (response.statusCode == 200) {
        return jsonDecode(response.body)['data'];
      }
    } catch (e) {
      print(e);
    }
    return [];
  }

  // تحديث حالة مستخدم
  Future<bool> updateUserStatus(String code, String action) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/admin/updateUser'),
        headers: _headers,
        body: jsonEncode({'code': code, 'action': action}),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // حذف مستخدم
  Future<bool> deleteUser(String code) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/admin/deleteUser'),
        headers: _headers,
        body: jsonEncode({'code': code}),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // جلب إعدادات التطبيق
  Future<Map<String, dynamic>?> getAppConfig() async {
    try {
      // هذه النقطة قد لا تحتاج API Key لتعمل عند الكل، لكننا وضعنا حماية /api
      // يفضل في server.js إزالة authMiddleware عن /api/config أو تمرير المفتاح هنا
      final response =
          await http.get(Uri.parse('$_baseUrl/api/config'), headers: _headers);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print(e);
    }
    return null;
  }

  // تحديث إعدادات التطبيق (للمدير)
  Future<bool> updateAppConfig(Map<String, dynamic> config) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/admin/updateConfig'),
        headers: _headers,
        body: jsonEncode(config),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // إضافة مستخدم جديد
  Future<Map<String, dynamic>> addUser(
      String name, String code, String role) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/admin/addUser'),
        headers: _headers,
        body: jsonEncode({
          'name': name,
          'code': code,
          'role': role,
        }),
      );

      final body = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'message': body['message']};
      } else {
        return {'success': false, 'message': body['message'] ?? 'فشلت الإضافة'};
      }
    } catch (e) {
      return {'success': false, 'message': 'خطأ اتصال: $e'};
    }
  }
}
