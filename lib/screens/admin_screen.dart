import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart'; // تأكد من إضافتها
import '../services/api_service.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ApiService _api = ApiService();
  List<dynamic> _users = [];
  bool _isLoading = true;

  // إعدادات التطبيق
  final _minVerCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  bool _isMaintenance = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    _users = await _api.getAllUsers();
    final config = await _api.getAppConfig();
    if (config != null) {
      _minVerCtrl.text = config['minVersion'] ?? '';
      _urlCtrl.text = config['updateUrl'] ?? '';
      _isMaintenance = config['isMaintenance'] ?? false;
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA), // خلفية رمادية فاتحة عصرية
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Text(
          'غرفة العمليات 🛡️',
          style: TextStyle(
              color: Colors.black87, fontWeight: FontWeight.w900, fontSize: 24),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black87),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.blue.shade900,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.blue.shade900,
          indicatorWeight: 3,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          tabs: const [
            Tab(text: 'المستخدمين', icon: Icon(Icons.group_outlined)),
            Tab(text: 'إعدادات النظام', icon: Icon(Icons.tune_outlined)),
          ],
        ),
      ),
      // 👇 أضف هذا الزر الجديد هنا
      floatingActionButton:
          _tabController.index == 0 // يظهر فقط في تبويب المستخدمين
              ? FloatingActionButton.extended(
                  onPressed: _showAddUserDialog,
                  backgroundColor: Colors.blue.shade900,
                  icon: const Icon(Icons.person_add, color: Colors.white),
                  label: const Text("مستخدم جديد",
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                )
              : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildUsersTab(),
                _buildConfigTab(),
              ],
            ),
    );
  }

  // نافذة إضافة مستخدم
  void _showAddUserDialog() {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    String role = 'user'; // القيمة الافتراضية

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('إضافة عضو جديد 👤'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'الاسم (للعرض فقط)',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    prefixIcon: const Icon(Icons.badge),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: codeCtrl,
                  decoration: InputDecoration(
                    labelText: 'كود الدخول (السري)',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    prefixIcon: const Icon(Icons.password),
                    helperText: 'هذا الكود الذي سيستخدمه للدخول',
                  ),
                ),
                const SizedBox(height: 15),
                DropdownButtonFormField<String>(
                  value: role,
                  decoration: InputDecoration(
                    labelText: 'الصلاحية',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    prefixIcon: const Icon(Icons.security),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'user', child: Text('مستخدم عادي')),
                    DropdownMenuItem(
                        value: 'admin', child: Text('مشرف (Admin)')),
                  ],
                  onChanged: (v) => setState(() => role = v!),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade900,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  if (nameCtrl.text.isEmpty || codeCtrl.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('يرجى تعبئة جميع الحقول')));
                    return;
                  }

                  Navigator.pop(ctx); // إغلاق النافذة

                  // إرسال الطلب
                  setState(() =>
                      _isLoading = true); // إظهار التحميل في الشاشة الخلفية
                  final result =
                      await _api.addUser(nameCtrl.text, codeCtrl.text, role);

                  if (result['success']) {
                    _loadData(); // تحديث القائمة
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('✅ ${result['message']}')));
                  } else {
                    setState(() => _isLoading = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('❌ ${result['message']}')));
                  }
                },
                child: const Text('حفظ وإضافة'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ==========================================
  // 1. تبويب المستخدمين (تصميم البطاقات)
  // ==========================================
  Widget _buildUsersTab() {
    if (_users.isEmpty) {
      return const Center(
          child: Text("لا يوجد مستخدمين بعد",
              style: TextStyle(fontSize: 18, color: Colors.grey)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _users.length,
      itemBuilder: (context, index) {
        final user = _users[index];
        final isBlocked = user['isActive'] == false;
        final isAdmin = user['role'] == 'admin';

        // تحديد لون البطاقة بناءً على الحالة
        Color cardColor = Colors.white;
        Color accentColor = Colors.blue;
        IconData statusIcon = Icons.check_circle;

        if (isBlocked) {
          cardColor = const Color(0xFFFFEBEE); // أحمر فاتح جداً
          accentColor = Colors.red;
          statusIcon = Icons.block;
        } else if (isAdmin) {
          cardColor = const Color(0xFFFFF8E1); // ذهبي فاتح جداً
          accentColor = Colors.amber.shade800;
          statusIcon = Icons.shield;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              // رأس البطاقة
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                leading: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(statusIcon, color: accentColor, size: 28),
                ),
                title: Text(
                  user['name'] ?? 'مستخدم',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18),
                ),
                subtitle: Text(
                  'Code: ${user['code']}',
                  style: TextStyle(
                      color: Colors.grey.shade600, fontFamily: 'monospace'),
                ),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isBlocked ? 'محظور' : (isAdmin ? 'مشرف' : 'مستخدم'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              const Divider(height: 1),

              // أزرار التحكم
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildActionButton(
                      icon: isBlocked ? Icons.lock_open : Icons.lock_outline,
                      label: isBlocked ? 'فك الحظر' : 'حظر',
                      color: isBlocked ? Colors.green : Colors.red,
                      onTap: () => _performAction(
                          user['code'], isBlocked ? 'unblock' : 'block'),
                    ),
                    _buildActionButton(
                      icon: isAdmin
                          ? Icons.person_outline
                          : Icons.admin_panel_settings_outlined,
                      label: isAdmin ? 'إعفاء' : 'ترقية',
                      color: Colors.blue.shade800,
                      onTap: () => _performAction(
                          user['code'], isAdmin ? 'demote' : 'promote'),
                    ),
                    _buildActionButton(
                      icon: Icons.phonelink_erase,
                      label: 'فك الجهاز',
                      color: Colors.orange.shade800,
                      onTap: () => _performAction(user['code'], 'reset_device'),
                    ),
                    _buildActionButton(
                      icon: Icons.delete_forever,
                      label: 'حذف',
                      color: Colors.grey.shade700,
                      onTap: () => _deleteUser(user['code']),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionButton(
      {required IconData icon,
      required String label,
      required Color color,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // 2. تبويب الإعدادات (تصميم لوحة التحكم)
  // ==========================================
  Widget _buildConfigTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // بطاقة وضع الصيانة
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _isMaintenance
                    ? [Colors.red.shade900, Colors.red.shade700]
                    : [Colors.green.shade700, Colors.green.shade500],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: (_isMaintenance ? Colors.red : Colors.green)
                      .withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isMaintenance
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "حالة النظام",
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      Text(
                        _isMaintenance
                            ? "النظام في وضع الصيانة"
                            : "النظام يعمل بشكل طبيعي",
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _isMaintenance,
                  activeColor: Colors.white,
                  activeTrackColor: Colors.red.shade300,
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: Colors.green.shade300,
                  onChanged: (val) => setState(() => _isMaintenance = val),
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),
          const Text("إعدادات التحديث",
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87)),
          const SizedBox(height: 15),

          // حقول الإدخال بتصميم حديث
          _buildModernTextField(
            controller: _minVerCtrl,
            label: 'أقل إصدار مسموح',
            hint: 'مثال: 1.0.5',
            icon: Icons.verified_user_outlined,
          ),

          const SizedBox(height: 20),

          _buildModernTextField(
            controller: _urlCtrl,
            label: 'رابط التحديث المباشر',
            hint: 'https://myserver.com/app.apk',
            icon: Icons.link,
          ),

          const SizedBox(height: 40),

          // زر الحفظ الكبير
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: _saveConfig,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade900,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
                elevation: 5,
                shadowColor: Colors.blue.withOpacity(0.4),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.save_as, color: Colors.white),
                  SizedBox(width: 10),
                  Text("حفظ وتعميم التغييرات",
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernTextField(
      {required TextEditingController controller,
      required String label,
      required String hint,
      required IconData icon}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
              color: Colors.grey.shade200,
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: Colors.blue.shade900),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
      ),
    );
  }

  // --- دوال الاتصال (نفس المنطق السابق) ---
  Future<void> _performAction(String code, String action) async {
    final success = await _api.updateUserStatus(code, action);
    if (success) {
      await _loadData();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ تم تنفيذ العملية بنجاح')));
    }
  }

  Future<void> _deleteUser(String code) async {
    final confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠️ حذف نهائي'),
        content:
            const Text('هل أنت متأكد من حذف هذا المستخدم؟ لا يمكن التراجع.'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _api.deleteUser(code);
      if (success) _loadData();
    }
  }

  Future<void> _saveConfig() async {
    final config = {
      'minVersion': _minVerCtrl.text,
      'updateUrl': _urlCtrl.text,
      'isMaintenance': _isMaintenance,
    };
    final success = await _api.updateAppConfig(config);
    if (success) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('🚀 تم تحديث النظام بنجاح')));
    }
  }
}
