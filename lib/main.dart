import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:bom/firebase_options.dart'; // تأكد من وجود هذا الملف
import 'package:bom/services/export_service.dart';
import 'package:bom/screens/map_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // شاشة الخرائط
// import 'package:bom/screens/splash_screen.dart'; // يمكنك تفعيلها لاحقاً

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. تهيئة الخطوط (لضمان عمل التصدير PDF)
  try {
    await ExportService.initializeFonts();
  } catch (e) {
    debugPrint("Error loading fonts: $e");
  }

  // 2. تهيئة Firebase (ضروري جداً لتجنب الانهيار)
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bom Map App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        // خطوط افتراضية تدعم العربية
        fontFamily: 'Roboto',
      ),
      // التوجيه المباشر للخريطة لتجاوز أي مشاكل في شاشات الدخول حالياً
      home: const MapScreen(),
    );
  }
}
