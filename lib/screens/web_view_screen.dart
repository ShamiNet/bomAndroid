import 'package:flutter/material.dart';
// تم التغيير إلى المكتبة الصحيحة
import 'package:webview_flutter/webview_flutter.dart';

class WebViewScreen extends StatefulWidget {
  final String? x;
  final String? url;
  static String defaultBaseUrl = 'http://qaaz.live/';
  const WebViewScreen({Key? key, this.x, this.url}) : super(key: key);

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  // 1. تم تغيير نوع المتحكم
  late final WebViewController _controller;
  late String _urlToLoad;

  @override
  void initState() {
    super.initState();
    if (widget.url != null && widget.url!.isNotEmpty) {
      _urlToLoad = widget.url!;
    } else if (widget.x != null && widget.x!.isNotEmpty) {
      _urlToLoad = WebViewScreen.defaultBaseUrl + widget.x!;
    } else {
      _urlToLoad = WebViewScreen.defaultBaseUrl;
    }

    // 2. طريقة تهيئة المتحكم الجديدة
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..loadRequest(Uri.parse(_urlToLoad));
  }

  @override
  void dispose() {
    // المتحكم الحديث لا يتطلب dispose() يدوياً
    super.dispose();
  }

  void _changeUrlDialog() async {
    // 3. طريقة الحصول على الرابط الحالي تغيرت
    String? currentUrl = await _controller.currentUrl();
    String value = currentUrl ?? _urlToLoad;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تغيير الرابط'),
        content: TextField(
          autofocus: true,
          controller: TextEditingController(text: value),
          decoration: const InputDecoration(hintText: 'أدخل رابط جديد'),
          onChanged: (v) => value = v,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, value),
            child: const Text('تغيير'),
          ),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      // 4. طريقة تحميل الرابط الجديد تغيرت
      await _controller.loadRequest(Uri.parse(result.trim()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('البث المباشر'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'تغيير الرابط',
            onPressed: _changeUrlDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'إعادة تحميل',
            onPressed: () {
              _controller.reload();
            },
          ),
        ],
      ),
      // 5. تم تغيير الـ Widget إلى WebViewWidget
      body: WebViewWidget(
        controller: _controller,
      ),
    );
  }
}
