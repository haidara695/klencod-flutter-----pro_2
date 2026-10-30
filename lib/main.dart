
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as dart_ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AccountingDb.instance.init();
  runApp(const SchoolAccountingApp());
}

const Color kPrimary = Color(0xFF2457D6);
const Color kSecondary = Color(0xFF6D5CE8);
const Color kBackground = Color(0xFFF4F7FC);
const Color kText = Color(0xFF18243A);
const Color kMuted = Color(0xFF758198);
const Color kGreen = Color(0xFF159D70);
const Color kRed = Color(0xFFE34D59);

String money(num value) =>
    NumberFormat('#,##0.##', 'en_US').format(value);

String dateText(String value) {
  try {
    return DateFormat('yyyy/MM/dd').format(DateTime.parse(value));
  } catch (_) {
    return value;
  }
}

class SchoolAccountingApp extends StatelessWidget {
  const SchoolAccountingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'المحاسب المدرسي PRO',
      locale: const Locale('ar'),
      supportedLocales: const [
        Locale('ar'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: kPrimary),
        scaffoldBackgroundColor: kBackground,
        fontFamily: 'Arial',
        appBarTheme: const AppBarTheme(
          backgroundColor: kBackground,
          foregroundColor: kText,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: Color(0xFFE8EDF5)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF7F9FD),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE2E8F2)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE2E8F2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: kPrimary,
              width: 1.5,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
        ),
      ),
      home: const AccountingHome(),
    );
  }
}

class AccountingDb {
  AccountingDb._();

  static final AccountingDb instance = AccountingDb._();

  Database? _db;

  Future<void> init() async {
    if (_db != null) return;

    final base = await getDatabasesPath();
    final dbPath = p.join(base, 'school_accounting.db');

    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE school_years(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            is_active INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE cash_transactions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            year_id INTEGER NOT NULL,
            type TEXT NOT NULL,
            amount REAL NOT NULL,
            category TEXT NOT NULL,
            person TEXT NOT NULL,
            note TEXT NOT NULL,
            transaction_date TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE app_settings(
            id INTEGER PRIMARY KEY CHECK(id = 1),
            school_name TEXT NOT NULL,
            school_address TEXT NOT NULL,
            currency TEXT NOT NULL,
            manager_name TEXT NOT NULL
          )
        ''');

        final now = DateTime.now().toIso8601String();

        await db.insert('school_years', {
          'name':
              '${DateTime.now().year}/${DateTime.now().year + 1}',
          'is_active': 1,
          'created_at': now,
        });

        await db.insert('app_settings', {
          'id': 1,
          'school_name': 'مدرستي',
          'school_address': '',
          'currency': 'ريال',
          'manager_name': 'أ. محمد علي حيدره',
        });
      },
    );
  }

  Database get db {
    final value = _db;
    if (value == null) {
      throw StateError('قاعدة البيانات لم تتم تهيئتها');
    }
    return value;
  }

  Future<List<Map<String, Object?>>> years() {
    return db.query('school_years', orderBy: 'id DESC');
  }

  Future<Map<String, Object?>> activeYear() async {
    final rows = await db.query(
      'school_years',
      where: 'is_active = 1',
      limit: 1,
    );

    if (rows.isNotEmpty) return rows.first;

    final all = await years();
    if (all.isNotEmpty) {
      final id = (all.first['id'] as num).toInt();
      await activateYear(id);
      return (await db.query(
        'school_years',
        where: 'id = ?',
        whereArgs: [id],
      )).first;
    }

    final id = await addYear(
      '${DateTime.now().year}/${DateTime.now().year + 1}',
    );

    await activateYear(id);

    return (await db.query(
      'school_years',
      where: 'id = ?',
      whereArgs: [id],
    )).first;
  }

  Future<int> addYear(String name) async {
    final clean = name.trim();

    if (clean.isEmpty) {
      throw Exception('اكتب اسم العام الدراسي');
    }

    final exists = await db.query(
      'school_years',
      where: 'name = ?',
      whereArgs: [clean],
    );

    if (exists.isNotEmpty) {
      throw Exception('هذا العام الدراسي موجود بالفعل');
    }

    return db.insert('school_years', {
      'name': clean,
      'is_active': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> activateYear(int id) async {
    await db.transaction((txn) async {
      await txn.update('school_years', {'is_active': 0});

      await txn.update(
        'school_years',
        {'is_active': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<List<Map<String, Object?>>> transactionsForYear(
    int yearId,
  ) {
    return db.query(
      'cash_transactions',
      where: 'year_id = ?',
      whereArgs: [yearId],
      orderBy: 'transaction_date DESC, id DESC',
    );
  }

  Future<int> saveTransaction({
    int? id,
    required int yearId,
    required String type,
    required double amount,
    required String category,
    required String person,
    required String note,
    required String date,
  }) async {
    final values = <String, Object?>{
      'year_id': yearId,
      'type': type,
      'amount': amount,
      'category': category.trim(),
      'person': person.trim(),
      'note': note.trim(),
      'transaction_date': date,
      'created_at': DateTime.now().toIso8601String(),
    };

    if (id == null) {
      return db.insert('cash_transactions', values);
    }

    return db.update(
      'cash_transactions',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteTransaction(int id) async {
    await db.delete(
      'cash_transactions',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Map<String, Object?>> settings() async {
    final rows = await db.query(
      'app_settings',
      where: 'id = 1',
      limit: 1,
    );

    if (rows.isNotEmpty) return rows.first;

    await db.insert('app_settings', {
      'id': 1,
      'school_name': 'مدرستي',
      'school_address': '',
      'currency': 'ريال',
      'manager_name': 'أ. محمد علي حيدره',
    });

    return settings();
  }

  Future<void> saveSettings({
    required String schoolName,
    required String address,
    required String currency,
    required String manager,
  }) async {
    await db.update(
      'app_settings',
      {
        'school_name':
            schoolName.trim().isEmpty ? 'مدرستي' : schoolName.trim(),
        'school_address': address.trim(),
        'currency':
            currency.trim().isEmpty ? 'ريال' : currency.trim(),
        'manager_name': manager.trim(),
      },
      where: 'id = 1',
    );
  }

  Future<Map<String, Object?>> makeBackup() async {
    final yearsList = await db.query(
      'school_years',
      orderBy: 'id',
    );

    final transactionsList = await db.query(
      'cash_transactions',
      orderBy: 'id',
    );

    final settingsRow = await settings();

    return {
      'app': 'المحاسب المدرسي PRO',
      'backup_version': 1,
      'created_at': DateTime.now().toIso8601String(),
      'school_years': yearsList,
      'cash_transactions': transactionsList,
      'app_settings': settingsRow,
    };
  }

  Future<void> restoreBackup(Map<String, dynamic> data) async {
    final yearsData = data['school_years'];
    final transactionsData = data['cash_transactions'];
    final settingsData = data['app_settings'];

    if (yearsData is! List ||
        transactionsData is! List ||
        settingsData is! Map) {
      throw Exception('ملف النسخة الاحتياطية غير صالح أو غير مكتمل');
    }

    await db.transaction((txn) async {
      await txn.delete('cash_transactions');
      await txn.delete('school_years');
      await txn.delete('app_settings');

      for (final item in yearsData) {
        if (item is Map) {
          await txn.insert(
            'school_years',
            Map<String, Object?>.from(item),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      for (final item in transactionsData) {
        if (item is Map) {
          await txn.insert(
            'cash_transactions',
            Map<String, Object?>.from(item),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      await txn.insert(
        'app_settings',
        Map<String, Object?>.from(settingsData),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    final currentYears = await years();

    if (currentYears.isEmpty) {
      final id = await addYear(
        '${DateTime.now().year}/${DateTime.now().year + 1}',
      );
      await activateYear(id);
    } else if (!currentYears.any(
      (e) => (e['is_active'] as num? ?? 0) == 1,
    )) {
      await activateYear((currentYears.first['id'] as num).toInt());
    }
  }
}

class AccountingHome extends StatefulWidget {
  const AccountingHome({super.key});

  @override
  State<AccountingHome> createState() => _AccountingHomeState();
}

class _AccountingHomeState extends State<AccountingHome> {
  int _tab = 0;
  bool _loading = true;

  Map<String, Object?>? _year;
  List<Map<String, Object?>> _years = [];
  List<Map<String, Object?>> _transactions = [];
  Map<String, Object?> _settings = {};

  String _filter = 'الكل';
  String _search = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _loading = true);

    try {
      final database = AccountingDb.instance;
      final year = await database.activeYear();
      final years = await database.years();

      final transactions = await database.transactionsForYear(
        (year['id'] as num).toInt(),
      );

      final settings = await database.settings();

      if (!mounted) return;

      setState(() {
        _year = year;
        _years = years;
        _transactions = transactions;
        _settings = settings;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _loading = false);
      _message('تعذر تحميل البيانات: $e', error: true);
    }
  }

  void _message(String message, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          textDirection: dart_ui.TextDirection.rtl,
        ),
        backgroundColor: error ? kRed : kPrimary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  double get _income => _transactions
      .where((e) => e['type'] == 'قبض')
      .fold(
        0.0,
        (sum, e) =>
            sum + ((e['amount'] as num?)?.toDouble() ?? 0),
      );

  double get _expenses => _transactions
      .where((e) => e['type'] == 'صرف')
      .fold(
        0.0,
        (sum, e) =>
            sum + ((e['amount'] as num?)?.toDouble() ?? 0),
      );

  double get _balance => _income - _expenses;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: dart_ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [kPrimary, kSecondary],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Colors.white,
                  size: 23,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'المحاسب المدرسي PRO',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      (_settings['school_name'] ?? 'مدرستي').toString(),
                      style: const TextStyle(
                        fontSize: 11,
                        color: kMuted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'تحديث',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                child: IndexedStack(
                  index: _tab,
                  children: [
                    _dashboard(),
                    _transactionsPage(),
                    _yearsPage(),
                    _settingsPage(),
                  ],
                ),
              ),
        floatingActionButton: _tab == 1
            ? FloatingActionButton.extended(
                onPressed: () => _editTransaction(),
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add_rounded),
                label: const Text('سند جديد'),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (index) {
            setState(() => _tab = index);
          },
          backgroundColor: Colors.white,
          indicatorColor: kPrimary.withValues(alpha: 0.12),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_rounded),
              label: 'الرئيسية',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_rounded),
              label: 'السندات',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_rounded),
              label: 'الأعوام',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_rounded),
              label: 'الإعدادات',
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageScroll(List<Widget> children) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: children,
      ),
    );
  }

  Widget _dashboard() {
    final recent = _transactions.take(5).toList();

    return _pageScroll([
      _welcomeCard(),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: _statCard(
              'إجمالي المقبوضات',
              _income,
              kGreen,
              Icons.south_west_rounded,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _statCard(
              'إجمالي المصروفات',
              _expenses,
              kRed,
              Icons.north_east_rounded,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      _balanceCard(),
      const SizedBox(height: 22),
      _sectionHeader(
        'آخر الحركات',
        'عرض الكل',
        () => setState(() => _tab = 1),
      ),
      const SizedBox(height: 10),
      if (recent.isEmpty)
        const _EmptyState(
          icon: Icons.receipt_long_rounded,
          title: 'لا توجد حركات مالية بعد',
          subtitle: 'ابدأ بتسجيل أول سند قبض أو صرف.',
        )
      else
        ...recent.map(_transactionTile),
      const SizedBox(height: 18),
      _sectionHeader('إجراءات سريعة', null, null),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: _quickAction(
              'سند قبض',
              Icons.add_card_rounded,
              kGreen,
              () => _editTransaction(type: 'قبض'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _quickAction(
              'سند صرف',
              Icons.payments_rounded,
              kRed,
              () => _editTransaction(type: 'صرف'),
            ),
          ),
        ],
      ),
    ]);
  }

  Widget _welcomeCard() {
    final yearName = (_year?['name'] ?? 'لا يوجد عام').toString();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF234EC9), Color(0xFF7656E8)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: kPrimary.withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'مرحباً بك 👋',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 5),
          Text(
            (_settings['school_name'] ?? 'مدرستي').toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(
                Icons.event_available_rounded,
                color: Colors.white70,
                size: 18,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'العام الدراسي: $yearName',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'يعمل دون إنترنت',
                  style: TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCard(
    String title,
    double value,
    Color color,
    IconData icon,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(color: kMuted, fontSize: 12),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                money(value),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
            Text(
              (_settings['currency'] ?? 'ريال').toString(),
              style: const TextStyle(fontSize: 11, color: kMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _balanceCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.account_balance_rounded,
                color: kPrimary,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'الرصيد الحالي',
                    style: TextStyle(color: kMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${money(_balance)} ${_settings['currency'] ?? 'ريال'}',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: _balance < 0 ? kRed : kText,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              _balance < 0
                  ? Icons.trending_down_rounded
                  : Icons.trending_up_rounded,
              color: _balance < 0 ? kRed : kGreen,
              size: 28,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(
    String title,
    String? action,
    VoidCallback? onAction,
  ) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: kText,
            ),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onAction,
            child: Text(action),
          ),
      ],
    );
  }

  Widget _quickAction(
    String title,
    IconData icon,
    Color color,
    VoidCallback action,
  ) {
    return InkWell(
      onTap: action,
      borderRadius: BorderRadius.circular(18),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 17,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const Icon(Icons.chevron_left_rounded, color: kMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _transactionsPage() {
    final filtered = _transactions.where((item) {
      final typeMatch = _filter == 'الكل' || item['type'] == _filter;
      final query = _search.trim().toLowerCase();

      final searchMatch = query.isEmpty ||
          ['person', 'category', 'note'].any(
            (key) => (item[key] ?? '')
                .toString()
                .toLowerCase()
                .contains(query),
          ) ||
          (item['amount'] ?? '').toString().contains(query);

      return typeMatch && searchMatch;
    }).toList();

    return _pageScroll([
      Row(
        children: [
          const Expanded(
            child: Text(
              'السندات المالية',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton.filledTonal(
            onPressed: () => _editTransaction(type: 'قبض'),
            icon: const Icon(Icons.add_rounded),
            tooltip: 'إضافة سند',
          ),
        ],
      ),
      const SizedBox(height: 12),
      TextField(
        onChanged: (value) => setState(() => _search = value),
        decoration: const InputDecoration(
          hintText: 'ابحث بالاسم أو التصنيف أو المبلغ...',
          prefixIcon: Icon(Icons.search_rounded),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        children: ['الكل', 'قبض', 'صرف']
            .map(
              (item) => ChoiceChip(
                label: Text(item),
                selected: _filter == item,
                onSelected: (_) => setState(() => _filter = item),
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 12),
      if (filtered.isEmpty)
        const _EmptyState(
          icon: Icons.search_off_rounded,
          title: 'لا توجد نتائج',
          subtitle: 'غيّر كلمات البحث أو أضف سنداً جديداً.',
        )
      else
        ...filtered.map(_transactionTile),
    ]);
  }

  Widget _transactionTile(Map<String, Object?> item) {
    final isReceipt = item['type'] == 'قبض';
    final color = isReceipt ? kGreen : kRed;
    final amount = (item['amount'] as num?)?.toDouble() ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Card(
        child: InkWell(
          onTap: () => _showTransactionDetails(item),
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isReceipt
                        ? Icons.south_west_rounded
                        : Icons.north_east_rounded,
                    color: color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (item['person'] ?? '').toString().isEmpty
                            ? (item['category'] ?? 'حركة مالية').toString()
                            : item['person'].toString(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item['type']} • ${item['category']}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: kMuted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        dateText(
                          (item['transaction_date'] ?? '').toString(),
                        ),
                        style: const TextStyle(
                          fontSize: 11,
                          color: kMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${isReceipt ? '+' : '−'}${money(amount)}',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      (_settings['currency'] ?? 'ريال').toString(),
                      style: const TextStyle(
                        color: kMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') {
                      _editTransaction(existing: item);
                    }
                    if (value == 'delete') {
                      _confirmDelete(item);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text('تعديل'),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('حذف'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showTransactionDetails(
    Map<String, Object?> item,
  ) async {
    final amount = (item['amount'] as num?)?.toDouble() ?? 0;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Directionality(
        textDirection: dart_ui.TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'تفاصيل سند ${item['type']}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 18),
              _detailRow(
                'المبلغ',
                '${money(amount)} ${_settings['currency'] ?? 'ريال'}',
              ),
              _detailRow('التصنيف', '${item['category']}'),
              _detailRow('الاسم / الجهة', '${item['person']}'),
              _detailRow(
                'التاريخ',
                dateText('${item['transaction_date']}'),
              ),
              _detailRow(
                'البيان',
                '${item['note']}'.isEmpty ? '—' : '${item['note']}',
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _editTransaction(existing: item);
                  },
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('تعديل السند'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: kMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    Map<String, Object?> item,
  ) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: dart_ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف السند؟'),
          content: const Text(
            'لا يمكن التراجع عن هذه العملية بعد الحذف.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: kRed,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );

    if (yes == true) {
      await AccountingDb.instance.deleteTransaction(
        (item['id'] as num).toInt(),
      );
      await _refresh();
      _message('تم حذف السند');
    }
  }

  Future<void> _editTransaction({
    Map<String, Object?>? existing,
    String type = 'قبض',
  }) async {
    if (_year == null) {
      _message('أنشئ عاماً دراسياً أولاً', error: true);
      return;
    }

    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController(
      text: existing == null ? '' : '${existing['amount']}',
    );
    final personController = TextEditingController(
      text: '${existing?['person'] ?? ''}',
    );
    final categoryController = TextEditingController(
      text: '${existing?['category'] ??
          (type == 'قبض' ? 'رسوم دراسية' : 'مصروفات تشغيلية')}',
    );
    final noteController = TextEditingController(
      text: '${existing?['note'] ?? ''}',
    );

    var selectedType = '${existing?['type'] ?? type}';
    var selectedDate =
        DateTime.tryParse('${existing?['transaction_date'] ?? ''}') ??
            DateTime.now();
    var saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: kBackground,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Directionality(
          textDirection: dart_ui.TextDirection.rtl,
          child: Padding(
            padding: EdgeInsets.only(
              left: 18,
              right: 18,
              top: 8,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 22,
            ),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      existing == null
                          ? 'إضافة سند مالي'
                          : 'تعديل السند',
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'قبض',
                          label: Text('سند قبض'),
                          icon: Icon(Icons.south_west_rounded),
                        ),
                        ButtonSegment(
                          value: 'صرف',
                          label: Text('سند صرف'),
                          icon: Icon(Icons.north_east_rounded),
                        ),
                      ],
                      selected: {selectedType},
                      onSelectionChanged: (values) {
                        setSheetState(
                          () => selectedType = values.first,
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'المبلغ *',
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                      validator: (value) {
                        final amount = double.tryParse(
                          (value ?? '').replaceAll(',', '').trim(),
                        );
                        if (amount == null || amount <= 0) {
                          return 'أدخل مبلغاً صحيحاً أكبر من صفر';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: personController,
                      decoration: const InputDecoration(
                        labelText: 'اسم الطالب / الجهة',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: categoryController,
                      decoration: const InputDecoration(
                        labelText: 'التصنيف *',
                        prefixIcon: Icon(Icons.category_outlined),
                      ),
                      validator: (value) =>
                          (value ?? '').trim().isEmpty
                              ? 'اكتب التصنيف'
                              : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: noteController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'البيان / ملاحظات',
                        prefixIcon: Icon(Icons.notes_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: selectedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          locale: const Locale('ar'),
                        );
                        if (picked != null) {
                          setSheetState(() => selectedDate = picked);
                        }
                      },
                      icon: const Icon(Icons.calendar_month_rounded),
                      label: Text(
                        'التاريخ: ${DateFormat('yyyy/MM/dd').format(selectedDate)}',
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: saving
                            ? null
                            : () async {
                                if (!(formKey.currentState?.validate() ??
                                    false)) {
                                  return;
                                }

                                setSheetState(() => saving = true);

                                try {
                                  await AccountingDb.instance.saveTransaction(
                                    id: existing == null
                                        ? null
                                        : (existing['id'] as num).toInt(),
                                    yearId: (_year!['id'] as num).toInt(),
                                    type: selectedType,
                                    amount: double.parse(
                                      amountController.text
                                          .replaceAll(',', '')
                                          .trim(),
                                    ),
                                    category: categoryController.text,
                                    person: personController.text,
                                    note: noteController.text,
                                    date: DateFormat('yyyy-MM-dd')
                                        .format(selectedDate),
                                  );

                                  if (ctx.mounted) {
                                    Navigator.pop(ctx);
                                  }

                                  await _refresh();

                                  _message(
                                    existing == null
                                        ? 'تم حفظ السند بنجاح'
                                        : 'تم تحديث السند',
                                  );
                                } catch (e) {
                                  setSheetState(() => saving = false);
                                  _message(
                                    'تعذر حفظ السند: $e',
                                    error: true,
                                  );
                                }
                              },
                        icon: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_rounded),
                        label: Text(
                          saving ? 'جارٍ الحفظ...' : 'حفظ السند',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    amountController.dispose();
    personController.dispose();
    categoryController.dispose();
    noteController.dispose();
  }

  Widget _yearsPage() {
    return _pageScroll([
      Row(
        children: [
          const Expanded(
            child: Text(
              'الأعوام الدراسية',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: _addYearDialog,
            icon: const Icon(Icons.add_rounded),
            label: const Text('عام جديد'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      const Text(
        'كل عام دراسي مستقل بسنداته المالية، والتبديل بين الأعوام لا يخلط البيانات.',
        style: TextStyle(color: kMuted, height: 1.5),
      ),
      const SizedBox(height: 16),
      ..._years.map((year) {
        final active = (year['is_active'] as num? ?? 0) == 1;

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: CircleAvatar(
                backgroundColor: active
                    ? kGreen.withValues(alpha: 0.12)
                    : kPrimary.withValues(alpha: 0.1),
                child: Icon(
                  Icons.calendar_month_rounded,
                  color: active ? kGreen : kPrimary,
                ),
              ),
              title: Text(
                '${year['name']}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                active ? 'العام النشط حالياً' : 'عام دراسي محفوظ',
              ),
              trailing: active
                  ? const Chip(
                      label: Text('نشط'),
                      avatar: Icon(Icons.check_circle, size: 16),
                    )
                  : TextButton(
                      onPressed: () async {
                        await AccountingDb.instance.activateYear(
                          (year['id'] as num).toInt(),
                        );
                        await _refresh();
                        _message(
                          'تم تفعيل العام الدراسي ${year['name']}',
                        );
                      },
                      child: const Text('تفعيل'),
                    ),
            ),
          ),
        );
      }),
      if (_years.isEmpty)
        const _EmptyState(
          icon: Icons.calendar_month_rounded,
          title: 'لا توجد أعوام',
          subtitle: 'أضف عاماً دراسياً لبدء تسجيل السندات.',
        ),
    ]);
  }

  Future<void> _addYearDialog() async {
    final controller = TextEditingController();
    final current = DateTime.now().year;
    controller.text = '$current/${current + 1}';

    final formKey = GlobalKey<FormState>();

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: dart_ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إنشاء عام دراسي جديد'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'اسم العام الدراسي',
                hintText: '2026/2027',
              ),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'اكتب اسم العام' : null,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.pop(ctx, controller.text.trim());
                }
              },
              child: const Text('إنشاء'),
            ),
          ],
        ),
      ),
    );

    controller.dispose();

    if (result == null) return;

    try {
      final id = await AccountingDb.instance.addYear(result);
      await AccountingDb.instance.activateYear(id);
      await _refresh();
      _message('تم إنشاء العام وتفعيله ببيانات مالية فارغة');
    } catch (e) {
      _message(
        e.toString().replaceFirst('Exception: ', ''),
        error: true,
      );
    }
  }

  Widget _settingsPage() {
    return _pageScroll([
      const Text(
        'الإعدادات',
        style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 14),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: kPrimary.withValues(alpha: 0.1),
                child: const Icon(
                  Icons.school_rounded,
                  size: 32,
                  color: kPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                (_settings['school_name'] ?? 'مدرستي').toString(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                (_settings['manager_name'] ?? '').toString(),
                style: const TextStyle(color: kMuted),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _editSettings,
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('تعديل بيانات المدرسة'),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 18),
      const Text(
        'النسخ الاحتياطي والاستعادة',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 10),
      _settingsAction(
        icon: Icons.cloud_upload_outlined,
        title: 'إنشاء نسخة احتياطية',
        subtitle: 'تصدير الأعوام والسندات والإعدادات إلى ملف JSON.',
        onTap: _exportBackup,
      ),
      const SizedBox(height: 10),
      _settingsAction(
        icon: Icons.restore_rounded,
        title: 'استعادة نسخة احتياطية',
        subtitle: 'استيراد ملف نسخة احتياطية محفوظ سابقاً.',
        onTap: _importBackup,
      ),
      const SizedBox(height: 22),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(
                Icons.verified_user_outlined,
                color: kPrimary,
                size: 28,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'المحاسب المدرسي PRO',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'نسخة محلية • البيانات محفوظة على الجهاز',
                      style: TextStyle(fontSize: 12, color: kMuted),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'تطوير: أ. محمد علي حيدره • 785068859',
                      style: TextStyle(fontSize: 11, color: kMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _settingsAction({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.all(14),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: kPrimary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: kPrimary),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: kMuted),
          ),
        ),
        trailing: const Icon(Icons.chevron_left_rounded),
      ),
    );
  }

  Future<void> _editSettings() async {
    final name = TextEditingController(
      text: '${_settings['school_name'] ?? ''}',
    );
    final address = TextEditingController(
      text: '${_settings['school_address'] ?? ''}',
    );
    final currency = TextEditingController(
      text: '${_settings['currency'] ?? 'ريال'}',
    );
    final manager = TextEditingController(
      text: '${_settings['manager_name'] ?? ''}',
    );

    final formKey = GlobalKey<FormState>();

    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: dart_ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Text('بيانات المدرسة'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'اسم المدرسة *',
                    ),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'اكتب اسم المدرسة' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: address,
                    decoration: const InputDecoration(labelText: 'العنوان'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: currency,
                    decoration: const InputDecoration(labelText: 'العملة'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: manager,
                    decoration: const InputDecoration(
                      labelText: 'اسم المدير / المسؤول',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.pop(ctx, true);
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (save == true) {
      await AccountingDb.instance.saveSettings(
        schoolName: name.text,
        address: address.text,
        currency: currency.text,
        manager: manager.text,
      );
      await _refresh();
      _message('تم حفظ بيانات المدرسة');
    }

    name.dispose();
    address.dispose();
    currency.dispose();
    manager.dispose();
  }

  Future<void> _exportBackup() async {
    try {
      final data = await AccountingDb.instance.makeBackup();
      final directory = await getTemporaryDirectory();

      final filename =
          'school_accounting_backup_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.json';

      final file = File(p.join(directory.path, filename));

      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data),
        flush: true,
      );

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        text: 'النسخة الاحتياطية للمحاسب المدرسي PRO',
        subject: 'نسخة احتياطية للمحاسب المدرسي',
      );

      _message('تم تجهيز ملف النسخة الاحتياطية للمشاركة أو الحفظ');
    } catch (e) {
      _message('تعذر إنشاء النسخة الاحتياطية: $e', error: true);
    }
  }

  Future<void> _importBackup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: dart_ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Text('استعادة نسخة احتياطية'),
          content: const Text(
            'ستستبدل الاستعادة بيانات الأعوام والسندات والإعدادات الحالية بالبيانات الموجودة في الملف. يفضل تصدير نسخة حالية أولاً.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('متابعة'),
            ),
          ],
        ),
      ),
    );

    if (confirm != true) return;

    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );

      if (picked == null || picked.files.isEmpty) return;

      final selected = picked.files.single;
      String contents;

      if (selected.bytes != null) {
        contents = utf8.decode(selected.bytes!);
      } else if (selected.path != null) {
        contents = await File(selected.path!).readAsString();
      } else {
        throw Exception('تعذر قراءة الملف المحدد');
      }

      final decoded = jsonDecode(contents);

      if (decoded is! Map<String, dynamic>) {
        throw Exception('تنسيق الملف غير صحيح');
      }

      await AccountingDb.instance.restoreBackup(decoded);
      await _refresh();
      _message('تمت استعادة النسخة الاحتياطية بنجاح');
    } catch (e) {
      _message('فشلت الاستعادة: $e', error: true);
    }
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 22,
          vertical: 28,
        ),
        child: Column(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 29, color: kPrimary),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: kMuted,
                fontSize: 12,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}