import 'dart:ui'; // ✅ مضافة لدعم تأثير الزجاج (Blur)
import 'package:bom/services/export_service.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_screen_recording/flutter_screen_recording.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// --- ملاحظة ---
// تأكد من أن هذا المسار صحيح في مشروعك
// import 'package:bom/services/export_service.dart';

enum TabLayout { horizontal, vertical, grid }

class WebTabsScreen extends StatefulWidget {
  final List<String> initialTabs;
  const WebTabsScreen({Key? key, this.initialTabs = const []})
      : super(key: key);

  @override
  State<WebTabsScreen> createState() => _WebTabsScreenState();
}

class _WebTabsScreenState extends State<WebTabsScreen>
    with TickerProviderStateMixin {
  bool _isLoading = true;
  late TabController _tabController;
  List<List<String>> _tabs = [];
  late List<List<WebViewController>> _controllers;
  List<String> _tabNames = [];
  List<List<String>> _floatingTexts = [];
  List<TabLayout> _tabLayouts = [];
  static String defaultBaseUrl = 'http://qaaz.live/';

  bool _isRecording = false;
  Timer? _timer;
  int _recordDuration = 0;

  static const platform = MethodChannel('media_scanner_channel');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 0, vsync: this);
    _loadTabs();
  }

  Future<void> _loadTabs() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTabsJson = prefs.getString('tabs_data');
    if (savedTabsJson != null) {
      final savedData = jsonDecode(savedTabsJson);
      _tabs = (savedData['tabs'] as List)
          .map((item) => List<String>.from(item))
          .toList();
      _tabNames = List<String>.from(savedData['tabNames']);
      _floatingTexts = (savedData['floatingTexts'] as List)
          .map((item) => List<String>.from(item))
          .toList();
      _tabLayouts = (savedData['tabLayouts'] as List)
          .map((item) => TabLayout.values[item as int])
          .toList();
    } else {
      _tabs = widget.initialTabs.isEmpty
          ? []
          : widget.initialTabs.map((x) => [defaultBaseUrl + x]).toList();
      _tabNames = List.generate(_tabs.length, (i) => 'بث');
      _floatingTexts = List.generate(
        _tabs.length,
        (tabIdx) => List.generate(_tabs[tabIdx].length, (splitIdx) => ''),
      );
      _tabLayouts = List.generate(_tabs.length, (_) => TabLayout.horizontal);
    }

    _controllers = [];
    for (final tabLinks in _tabs) {
      final List<WebViewController> tabControllers = [];
      for (final url in tabLinks) {
        final controller = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(const Color(0x00000000))
          ..loadRequest(Uri.parse(url));
        tabControllers.add(controller);
      }
      _controllers.add(tabControllers);
    }

    _tabController.dispose();
    _tabController = TabController(length: _tabs.length, vsync: this);

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveTabs() async {
    final prefs = await SharedPreferences.getInstance();
    final dataToSave = jsonEncode({
      'tabs': _tabs,
      'tabNames': _tabNames,
      'floatingTexts': _floatingTexts,
      'tabLayouts': _tabLayouts.map((e) => e.index).toList(),
    });
    await prefs.setString('tabs_data', dataToSave);
  }

  Future<void> _addTab(String x) async {
    final url = x.startsWith('http') ? x : defaultBaseUrl + x;

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..loadRequest(Uri.parse(url));

    setState(() {
      _tabs.add([url]);
      _controllers.add([controller]);
      _tabNames.add('بث');
      _floatingTexts.add(['']);
      _tabLayouts.add(TabLayout.horizontal);

      _tabController.dispose();
      _tabController = TabController(
        length: _tabs.length,
        vsync: this,
        initialIndex: _tabs.length - 1,
      );
    });
    _saveTabs();
  }

  void _removeTab(int index) {
    setState(() {
      _tabs.removeAt(index);
      _controllers.removeAt(index);
      _tabNames.removeAt(index);
      _floatingTexts.removeAt(index);
      _tabLayouts.removeAt(index);

      _tabController.dispose();
      _tabController = TabController(
        length: _tabs.length,
        vsync: this,
        initialIndex: (_tabs.isEmpty
            ? 0
            : (_tabController.index - 1).clamp(0, _tabs.length - 1)),
      );
    });
    _saveTabs();
  }

  void _clearAllTabs() {
    setState(() {
      _tabs.clear();
      _controllers.clear();
      _tabNames.clear();
      _floatingTexts.clear();
      _tabLayouts.clear();

      _tabController.dispose();
      _tabController = TabController(length: 0, vsync: this);
    });
    _saveTabs();
  }

  Future<void> _addSplit(int tabIndex, String x) async {
    final url = x.startsWith('http') ? x : defaultBaseUrl + x;

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..loadRequest(Uri.parse(url));

    setState(() {
      _tabs[tabIndex].add(url);
      _controllers[tabIndex].add(controller);
      _floatingTexts[tabIndex].add('');
    });
    _saveTabs();
  }

  void _removeSplit(int tabIndex, int splitIndex) {
    setState(() {
      _tabs[tabIndex].removeAt(splitIndex);
      _controllers[tabIndex].removeAt(splitIndex);
      _floatingTexts[tabIndex].removeAt(splitIndex);
    });
    _saveTabs();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _recordDuration++;
        });
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _recordDuration = 0;
  }

  String _formatDuration(int totalSeconds) {
    final duration = Duration(seconds: totalSeconds);
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  Future<void> _toggleScreenRecording() async {
    if (_isRecording) {
      _stopTimer();
      String path = await FlutterScreenRecording.stopRecordScreen;
      setState(() {
        _isRecording = false;
      });
      if (path.isNotEmpty) {
        try {
          String moviesPath = '/storage/emulated/0/Movies';
          if (!(await Directory(moviesPath).exists())) {
            await Directory(moviesPath).create(recursive: true);
          }
          String fileName =
              'recording_${DateTime.now().millisecondsSinceEpoch}.mp4';
          String newPath = '$moviesPath/$fileName';
          await File(path).copy(newPath);
          try {
            await platform.invokeMethod('scanFile', {'path': newPath});
          } catch (e) {
            print('MediaScanner error: $e');
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('تم حفظ الفيديو في الاستوديو: $newPath')),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'تم التسجيل لكن تعذر نقل الفيديو للاستوديو. المسار الأصلي: $path',
                ),
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('حدث خطأ أثناء إيقاف التسجيل.')),
          );
        }
      }
    } else {
      bool started = await FlutterScreenRecording.startRecordScreen(
        'recording_${DateTime.now().millisecondsSinceEpoch}',
      );
      if (!started) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تعذر بدء تسجيل الشاشة. تأكد من الصلاحيات.'),
            ),
          );
        }
      } else {
        _startTimer();
      }
      setState(() {
        _isRecording = started;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // تعريف ستايل موحد للتدرجات والزجاج
    const gradientColor = LinearGradient(
      colors: [Color(0xFF4A148C), Color(0xFF880E4F)], // بنفسجي إلى وردي غامق
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          flexibleSpace: Container(
              decoration: const BoxDecoration(gradient: gradientColor)),
          title: const Text('جاري التحميل...',
              style: TextStyle(color: Colors.white)),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Colors.purple),
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF3E5F5), // خلفية فاتحة جداً
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        // استخدام FlexibleSpace لإضافة تدرج لوني للبار العلوي
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: gradientColor,
            boxShadow: [
              BoxShadow(
                  color: Colors.black26, blurRadius: 10, offset: Offset(0, 2))
            ],
          ),
        ),
        title: const Text(
          'البث المباشر',
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 22,
              shadows: [
                Shadow(
                    color: Colors.black26, blurRadius: 2, offset: Offset(1, 1))
              ]),
        ),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: _tabs.isEmpty
            ? null
            : TabBar(
                controller: _tabController,
                isScrollable: true,
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                indicatorSize: TabBarIndicatorSize.label,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                tabs: List.generate(
                  _tabs.length,
                  (i) => Tab(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(_tabNames[i],
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () async {
                              String value = _tabNames[i];
                              final result = await showDialog<String>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20)),
                                  title: const Text('تغيير اسم الصفحة'),
                                  content: TextField(
                                    autofocus: true,
                                    controller:
                                        TextEditingController(text: value),
                                    decoration: InputDecoration(
                                        hintText: 'اسم جديد',
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(15)),
                                        filled: true,
                                        fillColor: Colors.grey.shade50),
                                    onChanged: (v) => value = v,
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('إلغاء',
                                          style: TextStyle(color: Colors.grey)),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.purple,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10))),
                                      onPressed: () =>
                                          Navigator.pop(context, value),
                                      child: const Text('تغيير'),
                                    ),
                                  ],
                                ),
                              );
                              if (result != null && result.trim().isNotEmpty) {
                                setState(() {
                                  _tabNames[i] = result.trim();
                                  _saveTabs();
                                });
                              }
                            },
                            child: const Icon(Icons.edit,
                                size: 16, color: Colors.white70),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _removeTab(i),
                            child: const Icon(Icons.close,
                                size: 16, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
        actions: [
          if (_tabs.isNotEmpty)
            PopupMenuButton<TabLayout>(
              icon: const Icon(Icons.view_quilt_rounded),
              tooltip: 'تغيير التخطيط',
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15)),
              onSelected: (TabLayout result) {
                if (_tabController.index >= 0 &&
                    _tabController.index < _tabLayouts.length) {
                  setState(() {
                    _tabLayouts[_tabController.index] = result;
                    _saveTabs();
                  });
                }
              },
              itemBuilder: (BuildContext context) =>
                  <PopupMenuEntry<TabLayout>>[
                const PopupMenuItem<TabLayout>(
                  value: TabLayout.horizontal,
                  child: ListTile(
                    leading:
                        Icon(Icons.view_stream_rounded, color: Colors.purple),
                    title: Text('أفقي'),
                  ),
                ),
                const PopupMenuItem<TabLayout>(
                  value: TabLayout.vertical,
                  child: ListTile(
                    leading: Icon(Icons.view_day_rounded, color: Colors.purple),
                    title: Text('عمودي'),
                  ),
                ),
                const PopupMenuItem<TabLayout>(
                  value: TabLayout.grid,
                  child: ListTile(
                    leading:
                        Icon(Icons.view_module_rounded, color: Colors.purple),
                    title: Text('شبكة'),
                  ),
                ),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded),
            tooltip: 'إضافة صفحة',
            onPressed: () async {
              final x = await showDialog<String>(
                context: context,
                builder: (context) {
                  String value = '';
                  return AlertDialog(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    title: const Text('أدخل رابط أو رقم x'),
                    content: TextField(
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                          hintText: 'مثال: 123 أو ',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15)),
                          filled: true,
                          fillColor: Colors.grey.shade50),
                      onChanged: (v) => value = v,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('إلغاء',
                            style: TextStyle(color: Colors.grey)),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10))),
                        onPressed: () => Navigator.pop(context, value),
                        child: const Text('إضافة'),
                      ),
                    ],
                  );
                },
              );
              if (x != null && x.trim().isNotEmpty) {
                await _addTab(x.trim());
              }
            },
          ),
          if (_tabs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded),
              tooltip: 'إغلاق كل الصفحات',
              onPressed: _clearAllTabs,
            ),
          if (_tabs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: ElevatedButton.icon(
                onPressed: _toggleScreenRecording,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRecording
                      ? Colors.redAccent
                      : Colors.white.withOpacity(0.9),
                  foregroundColor: _isRecording ? Colors.white : Colors.red,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: Icon(
                  _isRecording ? Icons.stop_circle : Icons.fiber_manual_record,
                  size: 20,
                ),
                label: Text(
                  _isRecording ? _formatDuration(_recordDuration) : 'REC',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_rounded),
            tooltip: 'تصدير الروابط إلى PDF',
            onPressed: () {
              if (_tabs.isNotEmpty) {
                final exportService = ExportService();
                exportService.exportAllMeasurementsToPdf(
                  context: context,
                  measurements: [],
                  title: 'روابط التبويبات',
                  description: _tabs.map((tab) => tab.join(', ')).join('\n'),
                  saveToDownloads: false,
                );
              }
            },
          ),
        ],
      ),
      body: _tabs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.web_asset_off,
                      size: 80, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text('لا توجد صفحات مفتوحة',
                      style:
                          TextStyle(fontSize: 18, color: Colors.grey.shade600)),
                ],
              ),
            )
          : TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              controller: _tabController,
              children: List.generate(
                _tabs.length,
                (tabIndex) {
                  final layout = _tabLayouts[tabIndex];
                  final splitsCount = _tabs[tabIndex].length;
                  final webViews = List.generate(splitsCount, (splitIndex) {
                    return Stack(
                      children: [
                        Container(
                          margin: const EdgeInsets.all(2), // هامش صغير جداً
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: Colors.purple.withOpacity(0.1)),
                          ),
                          child: WebViewWidget(
                            controller: _controllers[tabIndex][splitIndex],
                          ),
                        ),

                        // --- أزرار التحكم العلوية بتصميم زجاجي ---
                        Positioned(
                          top: 10,
                          right: 10,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(25),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.4),
                                    borderRadius: BorderRadius.circular(25),
                                    border: Border.all(
                                        color: Colors.white.withOpacity(0.2)),
                                    boxShadow: [
                                      BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 8)
                                    ]),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.close_rounded,
                                          size: 20, color: Colors.white),
                                      tooltip: 'إغلاق هذه الصفحة',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                          minWidth: 40, minHeight: 40),
                                      onPressed: _tabs[tabIndex].length > 1
                                          ? () =>
                                              _removeSplit(tabIndex, splitIndex)
                                          : null,
                                    ),
                                    Container(
                                        width: 1,
                                        height: 20,
                                        color: Colors.white24), // فاصل
                                    IconButton(
                                      icon: const Icon(Icons.add_box_rounded,
                                          size: 20, color: Colors.white),
                                      tooltip: 'إضافة صفحة بجانبها',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                          minWidth: 40, minHeight: 40),
                                      onPressed: () async {
                                        final x = await showDialog<String>(
                                          context: context,
                                          builder: (context) {
                                            String value = '';
                                            return AlertDialog(
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          20)),
                                              title: const Text(
                                                'أدخل رابط أو رقم x جديد',
                                              ),
                                              content: TextField(
                                                keyboardType:
                                                    TextInputType.number,
                                                autofocus: true,
                                                decoration: InputDecoration(
                                                    hintText: 'مثال: 456 أو ',
                                                    border: OutlineInputBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(15)),
                                                    filled: true,
                                                    fillColor:
                                                        Colors.grey.shade50),
                                                onChanged: (v) => value = v,
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(context),
                                                  child: const Text('إلغاء',
                                                      style: TextStyle(
                                                          color: Colors.grey)),
                                                ),
                                                ElevatedButton(
                                                  style: ElevatedButton.styleFrom(
                                                      backgroundColor:
                                                          Colors.purple,
                                                      foregroundColor:
                                                          Colors.white,
                                                      shape:
                                                          RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          10))),
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                          context, value),
                                                  child: const Text('إضافة'),
                                                ),
                                              ],
                                            );
                                          },
                                        );
                                        if (x != null && x.trim().isNotEmpty) {
                                          await _addSplit(tabIndex, x.trim());
                                        }
                                      },
                                    ),
                                    Container(
                                        width: 1,
                                        height: 20,
                                        color: Colors.white24),
                                    IconButton(
                                      icon: const Icon(Icons.edit_rounded,
                                          size: 20, color: Colors.white),
                                      tooltip: 'تغيير الرابط',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                          minWidth: 40, minHeight: 40),
                                      onPressed: () async {
                                        String value =
                                            _tabs[tabIndex][splitIndex];
                                        final result = await showDialog<String>(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(20)),
                                            title: const Text('تغيير الرابط'),
                                            content: TextField(
                                              autofocus: true,
                                              controller: TextEditingController(
                                                text: value,
                                              ),
                                              decoration: InputDecoration(
                                                  hintText: 'أدخل رابط جديد',
                                                  border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              15)),
                                                  filled: true,
                                                  fillColor:
                                                      Colors.grey.shade50),
                                              onChanged: (v) => value = v,
                                              onSubmitted: (v) =>
                                                  Navigator.pop(context, v),
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(context),
                                                child: const Text('إلغاء',
                                                    style: TextStyle(
                                                        color: Colors.grey)),
                                              ),
                                              ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                    backgroundColor: Colors
                                                        .purple,
                                                    foregroundColor:
                                                        Colors.white,
                                                    shape:
                                                        RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        10))),
                                                onPressed: () => Navigator.pop(
                                                    context, value),
                                                child: const Text('تغيير'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (result != null &&
                                            result.trim().isNotEmpty) {
                                          final url = result.trim().startsWith(
                                                    'http',
                                                  )
                                              ? result.trim()
                                              : defaultBaseUrl + result.trim();

                                          await _controllers[tabIndex]
                                                  [splitIndex]
                                              .loadRequest(Uri.parse(url));

                                          setState(() {
                                            _tabs[tabIndex][splitIndex] = url;
                                            _saveTabs();
                                          });
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        // --- النص العائم بتصميم زجاجي ---
                        Positioned(
                          left: 10,
                          bottom: 10,
                          child: GestureDetector(
                            onTap: () async {
                              String value =
                                  _floatingTexts[tabIndex][splitIndex];
                              final result = await showDialog<String>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20)),
                                  title: const Text(
                                    'تعديل النص العائم',
                                  ),
                                  content: TextField(
                                    autofocus: true,
                                    controller: TextEditingController(
                                      text: value,
                                    ),
                                    decoration: InputDecoration(
                                        hintText: 'النص العائم',
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(15)),
                                        filled: true,
                                        fillColor: Colors.grey.shade50),
                                    onChanged: (v) => value = v,
                                    onSubmitted: (v) =>
                                        Navigator.pop(context, v),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('إلغاء',
                                          style: TextStyle(color: Colors.grey)),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.purple,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10))),
                                      onPressed: () =>
                                          Navigator.pop(context, value),
                                      child: const Text('حفظ'),
                                    ),
                                  ],
                                ),
                              );
                              if (result != null) {
                                setState(() {
                                  _floatingTexts[tabIndex][splitIndex] = result;
                                  _saveTabs();
                                });
                              }
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(15),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(15),
                                      border: Border.all(
                                          color: Colors.white.withOpacity(0.2)),
                                      boxShadow: const [
                                        BoxShadow(
                                            color: Colors.black26,
                                            blurRadius: 4)
                                      ]),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.edit_note,
                                          color: Colors.white70, size: 16),
                                      const SizedBox(width: 5),
                                      Text(
                                        _floatingTexts[tabIndex][splitIndex]
                                                .isEmpty
                                            ? 'نص عائم'
                                            : _floatingTexts[tabIndex]
                                                [splitIndex],
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            shadows: [
                                              Shadow(
                                                  color: Colors.black,
                                                  blurRadius: 2)
                                            ]),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  });

                  switch (layout) {
                    case TabLayout.vertical:
                      return Column(
                        children: webViews
                            .map((webView) => Expanded(child: webView))
                            .toList(),
                      );
                    case TabLayout.grid:
                      return GridView.count(
                        crossAxisCount:
                            splitsCount <= 1 ? 1 : (sqrt(splitsCount).ceil()),
                        childAspectRatio: 1.0, // نسبة العرض للارتفاع لشبكة أجمل
                        mainAxisSpacing: 2,
                        crossAxisSpacing: 2,
                        children: webViews,
                      );
                    case TabLayout.horizontal:
                      return Row(
                        children: webViews
                            .map((webView) => Expanded(child: webView))
                            .toList(),
                      );
                  }
                },
              ),
            ),
    );
  }
}
