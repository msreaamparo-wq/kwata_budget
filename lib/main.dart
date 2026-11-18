import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'data/local_database.dart';
import 'data/sync_service.dart';

const String supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://edidurmeizrdysihvhdl.supabase.co',
);
const String supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: 'sb_publishable_hmnDpc2lKJvH4GiUX8ljXg_kxn4W80q',
);

const Color forest = Color(0xFF142B24);
const Color forestLight = Color(0xFF254B3B);
const Color gold = Color(0xFFE4C47F);
const Color paper = Color(0xFFF5F3EC);
const Color muted = Color(0xFF7C877E);
const Color lineColor = Color(0xFFE8E6DC);
const Color incomeColor = Color(0xFF347A56);
const Color expenseColor = Color(0xFFC56D45);

const List<String> expenseCategories = [
  'Pagkaon',
  'Transportasyon',
  'Kuryente/Tubig',
  'Load/Internet',
  'Eskwela',
  'Panimalay',
  'Lingaw',
  'Uban pa',
];
const List<String> incomeCategories = [
  'Sweldo',
  'Negosyo',
  'Regalo',
  'Allowance',
  'Uban pa',
];

final _currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 2);
final _uuid = const Uuid();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );
  await LocalDatabase.instance.database;
  runApp(const KwartaApp());
}

class KwartaApp extends StatelessWidget {
  const KwartaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: forest,
      brightness: Brightness.light,
      primary: forest,
      secondary: gold,
      surface: const Color(0xFFFFFEFA),
      error: expenseColor,
    );
    return MaterialApp(
      title: 'Kwarta',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: paper,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: forest,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFFBFAF6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: lineColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: lineColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: forest, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFFFFFEFA),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: lineColor),
          ),
          margin: EdgeInsets.zero,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: forest,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      home: const BudgetHomePage(),
    );
  }
}

class BudgetHomePage extends StatefulWidget {
  const BudgetHomePage({super.key});

  @override
  State<BudgetHomePage> createState() => _BudgetHomePageState();
}

class _BudgetHomePageState extends State<BudgetHomePage> with WidgetsBindingObserver {
  final _client = Supabase.instance.client;
  final _local = LocalDatabase.instance;
  late final SyncService _syncService = SyncService(_client, _local);

  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  User? _user;
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _budgets = [];
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = true;
  bool _syncing = false;
  bool _online = true;
  bool _authBusy = false;
  bool _signUpMode = false;
  String? _authError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _user = _client.auth.currentUser;
    _authSubscription = _client.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      final nextUser = data.session?.user;
      if (nextUser?.id != _user?.id) {
        setState(() => _user = nextUser);
        if (nextUser != null) {
          unawaited(_loadAndSync());
        } else {
          setState(() {
            _transactions = [];
            _budgets = [];
          });
        }
      }
    });
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      final connected = results.any((result) => result != ConnectivityResult.none);
      if (!mounted) return;
      setState(() => _online = connected);
      if (connected && _user != null) unawaited(_syncNow(showMessage: false));
    });
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final results = await Connectivity().checkConnectivity();
      _online = results.any((result) => result != ConnectivityResult.none);
    } catch (_) {
      _online = true;
    }
    if (_user != null) {
      await _loadAndSync();
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _user != null) {
      unawaited(_reloadLocal());
      unawaited(_syncNow(showMessage: false));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  String get _monthKey => '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
  String get _monthLabel => DateFormat('MMMM yyyy').format(_month);

  Future<void> _loadAndSync() async {
    await _reloadLocal();
    if (_online) await _syncNow(showMessage: false);
  }

  Future<void> _reloadLocal() async {
    final userId = _user?.id;
    if (userId == null) return;
    final tx = await _local.getTransactions(userId);
    final budgets = await _local.getBudgets(userId);
    if (!mounted) return;
    setState(() {
      _transactions = tx;
      _budgets = budgets;
      _loading = false;
    });
  }

  Future<void> _syncNow({bool showMessage = true}) async {
    final userId = _user?.id;
    if (userId == null || _syncing || !_online) return;
    setState(() => _syncing = true);
    try {
      await _syncService.sync(userId);
      await _reloadLocal();
      if (showMessage && mounted) _message('Na-sync na ang imong records sa Supabase.');
    } catch (error) {
      if (showMessage && mounted) {
        _message('Local gihapon ang data. Wala pa na-sync: ${_friendlyError(error)}');
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('SocketException') || text.contains('Failed host lookup')) {
      return 'Walay internet connection.';
    }
    return text.replaceFirst('Exception: ', '');
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _authenticate(String email, String password) async {
    setState(() {
      _authBusy = true;
      _authError = null;
    });
    try {
      if (_signUpMode) {
        final response = await _client.auth.signUp(email: email, password: password);
        if (response.session == null) {
          setState(() {
            _authError = 'Na-create na ang account. I-check ang imong email para sa confirmation, unya sign in.';
          });
        } else {
          setState(() => _user = response.user);
          await _loadAndSync();
        }
      } else {
        final response = await _client.auth.signInWithPassword(email: email, password: password);
        setState(() => _user = response.user);
        await _loadAndSync();
      }
    } on AuthException catch (error) {
      setState(() => _authError = error.message);
    } catch (error) {
      setState(() => _authError = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('Mabilin ang local records niini nga device. Kinahanglan og internet aron makabalik sa account.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _client.auth.signOut();
    } catch (error) {
      _message(_friendlyError(error));
    }
    if (!mounted) return;
    setState(() {
      _user = null;
      _transactions = [];
      _budgets = [];
      _loading = false;
    });
  }

  double get _income => _currentMonthTransactions
      .where((row) => row['kind'] == 'income')
      .fold(0, (sum, row) => sum + (row['amount'] as num).toDouble());

  double get _expenses => _currentMonthTransactions
      .where((row) => row['kind'] == 'expense')
      .fold(0, (sum, row) => sum + (row['amount'] as num).toDouble());

  double get _balance => _income - _expenses;

  List<Map<String, dynamic>> get _currentMonthTransactions => _transactions.where((row) {
    final date = (row['transaction_date'] as String?) ?? '';
    return date.startsWith(_monthKey) && row['deleted_at'] == null;
  }).toList();

  double get _budget => _budgets
      .where((row) => row['month'] == _monthKey)
      .fold<double>(0, (value, row) => (row['amount'] as num).toDouble());

  int get _pendingCount => _transactions.where((row) => row['sync_status'] == 'pending').length +
      _budgets.where((row) => row['sync_status'] == 'pending').length;

  Future<void> _addTransaction({
    required String kind,
    required double amount,
    required String category,
    required DateTime date,
    required String note,
  }) async {
    final userId = _user!.id;
    final now = DateTime.now().toUtc().toIso8601String();
    await _local.saveTransaction({
      'id': _uuid.v4(),
      'user_id': userId,
      'kind': kind,
      'amount': amount,
      'category': category,
      'transaction_date': DateFormat('yyyy-MM-dd').format(date),
      'note': note,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
      'sync_status': 'pending',
    });
    setState(() => _month = DateTime(date.year, date.month));
    await _reloadLocal();
    if (_online) unawaited(_syncNow(showMessage: false));
    _message(_online ? 'Na-save locally. Nag-sync sa cloud…' : 'Na-save sa phone bisan offline.');
  }

  Future<void> _saveBudget(double amount) async {
    final userId = _user!.id;
    await _local.saveBudget({
      'user_id': userId,
      'month': _monthKey,
      'amount': amount,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'sync_status': 'pending',
    });
    await _reloadLocal();
    if (_online) unawaited(_syncNow(showMessage: false));
    _message(_online ? 'Na-save ang budget limit.' : 'Na-save ang budget locally.');
  }

  Future<void> _deleteTransaction(Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Papason ang record?'),
        content: Text('Sigurado ka nga papason ang ${row['category']} nga record?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Dili')), 
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Papason')),
        ],
      ),
    );
    if (confirmed != true) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await _local.saveTransaction({
      ...row,
      'deleted_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });
    await _reloadLocal();
    if (_online) unawaited(_syncNow(showMessage: false));
    _message(_online ? 'Na-delete ang record.' : 'Na-delete locally; i-sync sa internet puhon.');
  }

  Future<void> _showAddTransaction() async {
    if (_user == null) return;
    final result = await showModalBottomSheet<_TransactionInput>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _AddTransactionSheet(),
    );
    if (result == null) return;
    await _addTransaction(
      kind: result.kind,
      amount: result.amount,
      category: result.category,
      date: result.date,
      note: result.note,
    );
  }

  Future<void> _showBudgetDialog() async {
    final controller = TextEditingController(text: _budget > 0 ? _budget.toStringAsFixed(2) : '');
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Budget sa $_monthLabel'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Monthly limit (₱)', prefixText: '₱ '),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            final amount = double.tryParse(controller.text.trim());
            if (amount == null || amount < 0) return;
            Navigator.pop(context, amount);
          }, child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (value != null) await _saveBudget(value);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: forest)));
    }
    if (_user == null) {
      return _AuthPage(
        signUpMode: _signUpMode,
        busy: _authBusy,
        error: _authError,
        onSubmit: _authenticate,
        onToggleMode: () => setState(() {
          _signUpMode = !_signUpMode;
          _authError = null;
        }),
      );
    }
    return _buildDashboard();
  }

  Widget _buildDashboard() {
    final records = _currentMonthTransactions;
    final categories = <String, double>{};
    for (final row in records.where((row) => row['kind'] == 'expense')) {
      final category = row['category'] as String;
      categories[category] = (categories[category] ?? 0) + (row['amount'] as num).toDouble();
    }
    final sortedCategories = categories.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final recentRecords = [...records]..sort((a, b) => (b['transaction_date'] as String).compareTo(a['transaction_date'] as String));
    final budgetUsed = _budget > 0 ? (_expenses / _budget).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 39,
              height: 39,
              decoration: BoxDecoration(color: const Color(0xFF244638), borderRadius: BorderRadius.circular(13), border: Border.all(color: Colors.white24)),
              child: const Center(child: Text('K', style: TextStyle(color: gold, fontSize: 22, fontWeight: FontWeight.w900))),
            ),
            const SizedBox(width: 10),
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('kwarta.', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19, height: 1.1)),
              Text('BUDGET TRACKER', style: TextStyle(fontSize: 9, color: Color(0xFFCBD7CD), letterSpacing: 1.4)),
            ]),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(child: _ConnectionChip(online: _online, syncing: _syncing, pending: _pendingCount)),
          ),
          IconButton(
            tooltip: 'Sync now',
            onPressed: _syncing ? null : () => _syncNow(),
            icon: _syncing ? const SizedBox(width: 19, height: 19, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.sync_rounded),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) { if (value == 'signout') _signOut(); },
            itemBuilder: (context) => const [PopupMenuItem(value: 'signout', child: Text('Sign out'))],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddTransaction,
        backgroundColor: forest,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Record', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: RefreshIndicator(
        color: forest,
        onRefresh: () async {
          await _reloadLocal();
          await _syncNow();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
          children: [
            Text('YOUR MONEY, IN ORDER', style: TextStyle(color: muted, letterSpacing: 1.8, fontWeight: FontWeight.w800, fontSize: 10)),
            const SizedBox(height: 6),
            const Text('Maayong adlaw!', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900, color: forest, letterSpacing: -0.7)),
            const SizedBox(height: 4),
            Text(_user?.email ?? 'Personal budget', style: const TextStyle(color: muted, fontSize: 12)),
            const SizedBox(height: 18),
            _MonthSelector(
              label: _monthLabel,
              onPrevious: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
              onNext: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
            ),
            const SizedBox(height: 13),
            LayoutBuilder(builder: (context, constraints) {
              final width = (constraints.maxWidth - 20) / 3;
              return Row(children: [
                SizedBox(width: width, child: _SummaryCard(label: 'Kita', value: _currency.format(_income), icon: Icons.north_east_rounded, color: incomeColor)),
                const SizedBox(width: 10),
                SizedBox(width: width, child: _SummaryCard(label: 'Gasto', value: _currency.format(_expenses), icon: Icons.south_east_rounded, color: expenseColor)),
                const SizedBox(width: 10),
                SizedBox(width: width, child: _SummaryCard(label: 'Balance', value: _currency.format(_balance), icon: Icons.account_balance_wallet_outlined, color: _balance < 0 ? expenseColor : forestLight)),
              ]);
            }),
            const SizedBox(height: 14),
            _BudgetCard(
              monthLabel: _monthLabel,
              budget: _budget,
              spent: _expenses,
              progress: budgetUsed,
              onEdit: _showBudgetDialog,
            ),
            const SizedBox(height: 19),
            _SectionHeader(title: 'Asa miadto ang kwarta', subtitle: 'Gasto sumala sa category'),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(17),
                child: sortedCategories.isEmpty
                    ? const _EmptyState(icon: Icons.pie_chart_outline_rounded, message: 'Wala pay gasto ning bulana.')
                    : Column(children: [
                        for (var i = 0; i < sortedCategories.length; i++) ...[
                          _CategoryProgress(category: sortedCategories[i].key, amount: sortedCategories[i].value, total: _expenses),
                          if (i != sortedCategories.length - 1) const SizedBox(height: 16),
                        ],
                      ]),
              ),
            ),
            const SizedBox(height: 20),
            _SectionHeader(title: 'Mga record', subtitle: '${records.length} record(s) ning bulana'),
            const SizedBox(height: 10),
            Card(
              child: records.isEmpty
                  ? const Padding(padding: EdgeInsets.all(14), child: _EmptyState(icon: Icons.receipt_long_outlined, message: 'Wala pay record. I-tap ang Record para magsugod.'))
                  : Column(children: [
                      for (var i = 0; i < recentRecords.length; i++) ...[
                        _TransactionTile(
                          row: recentRecords[i],
                          onDelete: () => _deleteTransaction(recentRecords[i]),
                        ),
                        if (i != recentRecords.length - 1) const Divider(height: 1, indent: 64, color: lineColor),
                      ],
                    ]),
            ),
            const SizedBox(height: 15),
            Text(
              _pendingCount > 0
                  ? '$_pendingCount record(s) waiting to sync. Naka-save na kini sa imong phone.'
                  : _online
                      ? 'Na-save sa phone ug naka-sync sa cloud.'
                      : 'Offline mode. Ang imong records magpabilin sa phone.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 11, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthPage extends StatefulWidget {
  const _AuthPage({required this.signUpMode, required this.busy, required this.error, required this.onSubmit, required this.onToggleMode});
  final bool signUpMode;
  final bool busy;
  final String? error;
  final Future<void> Function(String email, String password) onSubmit;
  final VoidCallback onToggleMode;

  @override
  State<_AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<_AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Container(width: 48, height: 48, decoration: BoxDecoration(color: forest, borderRadius: BorderRadius.circular(15)), child: const Center(child: Text('K', style: TextStyle(color: gold, fontWeight: FontWeight.w900, fontSize: 26)))),
                        const SizedBox(width: 12),
                        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('kwarta.', style: TextStyle(color: forest, fontWeight: FontWeight.w900, fontSize: 23)),
                          Text('PERSONAL BUDGET TRACKER', style: TextStyle(color: muted, fontSize: 9, letterSpacing: 1.2)),
                        ]),
                      ]),
                      const SizedBox(height: 29),
                      Text(widget.signUpMode ? 'Paghimo og account' : 'Maayong pagbalik!', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 25, color: forest)),
                      const SizedBox(height: 7),
                      Text(widget.signUpMode ? 'Paghimo og account aron ma-backup sa cloud ang imong budget.' : 'Sign in aron makita ang imong budget records.', style: const TextStyle(color: muted, fontSize: 13, height: 1.4)),
                      const SizedBox(height: 22),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(labelText: 'Email address', prefixIcon: Icon(Icons.mail_outline_rounded)),
                        validator: (value) => value == null || !value.contains('@') ? 'Ibutang ang valid nga email.' : null,
                      ),
                      const SizedBox(height: 13),
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        autofillHints: [widget.signUpMode ? AutofillHints.newPassword : AutofillHints.password],
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(onPressed: () => setState(() => _obscure = !_obscure), icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined)),
                        ),
                        validator: (value) => value == null || value.length < 6 ? 'Minimum 6 characters.' : null,
                      ),
                      if (widget.error != null) ...[
                        const SizedBox(height: 12),
                        Text(widget.error!, style: const TextStyle(color: expenseColor, fontSize: 12, height: 1.4)),
                      ],
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: widget.busy ? null : () {
                          if (_formKey.currentState!.validate()) {
                            widget.onSubmit(_email.text.trim(), _password.text);
                          }
                        },
                        icon: widget.busy ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.arrow_forward_rounded),
                        label: Text(widget.busy ? 'Palihog hulat…' : widget.signUpMode ? 'Create account' : 'Sign in'),
                        style: FilledButton.styleFrom(backgroundColor: forest, padding: const EdgeInsets.symmetric(vertical: 15)),
                      ),
                      const SizedBox(height: 13),
                      Center(child: TextButton(onPressed: widget.busy ? null : widget.onToggleMode, child: Text(widget.signUpMode ? 'Naa na kay account? Sign in' : 'Wala kay account? Create account', style: const TextStyle(color: forest, fontWeight: FontWeight.w700)))),
                      const SizedBox(height: 7),
                      const Text('Ang unang sign in kinahanglan og internet. Human ana, mahimo kang mag-record bisan offline.', textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 11, height: 1.5)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.online, required this.syncing, required this.pending});
  final bool online;
  final bool syncing;
  final int pending;

  @override
  Widget build(BuildContext context) {
    final label = syncing ? 'Sync…' : online ? (pending > 0 ? '$pending pending' : 'Online') : 'Offline';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white24)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: syncing ? gold : online ? const Color(0xFF85D39D) : const Color(0xFFE4A27F), shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _MonthSelector extends StatelessWidget {
  const _MonthSelector({required this.label, required this.onPrevious, required this.onNext});
  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: const Color(0xFFFFFEFA), border: Border.all(color: lineColor), borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        IconButton(onPressed: onPrevious, icon: const Icon(Icons.chevron_left_rounded), visualDensity: VisualDensity.compact),
        Expanded(child: Text(label, textAlign: TextAlign.center, style: const TextStyle(color: forest, fontWeight: FontWeight.w800, fontSize: 13))),
        IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right_rounded), visualDensity: VisualDensity.compact),
      ]),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.value, required this.icon, required this.color});
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 13, 10, 14),
      decoration: BoxDecoration(color: const Color(0xFFFFFEFA), border: Border.all(color: lineColor), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 25, height: 25, decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: color, size: 15)),
        const SizedBox(height: 9),
        Text(label, style: const TextStyle(color: muted, fontSize: 10, fontWeight: FontWeight.w700)),
        const SizedBox(height: 5),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: -0.5))),
      ]),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.monthLabel, required this.budget, required this.spent, required this.progress, required this.onEdit});
  final String monthLabel;
  final double budget;
  final double spent;
  final double progress;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final remaining = budget - spent;
    final exceeded = budget > 0 && remaining < 0;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(gradient: const LinearGradient(colors: [forest, forestLight], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(19), boxShadow: [BoxShadow(color: forest.withValues(alpha: 0.12), blurRadius: 18, offset: const Offset(0, 7))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Expanded(child: Text('Monthly budget limit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14))), Text(budget > 0 ? '${(spent / budget * 100).round()}% used' : 'Not set', style: const TextStyle(color: Color(0xFFD4DED6), fontSize: 11))]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Text(budget > 0 ? _currency.format(remaining.abs()) : 'Set your limit', style: const TextStyle(color: gold, fontWeight: FontWeight.w900, fontSize: 23, letterSpacing: -0.7))),
          Text(budget > 0 ? (exceeded ? 'over budget' : 'remaining') : monthLabel, style: const TextStyle(color: Color(0xFFD4DED6), fontSize: 11)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(borderRadius: BorderRadius.circular(20), child: LinearProgressIndicator(value: progress, minHeight: 7, backgroundColor: Colors.white24, color: exceeded ? const Color(0xFFE99A75) : gold)),
        const SizedBox(height: 13),
        Row(children: [
          Expanded(child: Text(budget > 0 ? 'Gasto: ${_currency.format(spent)} sa ${_currency.format(budget)}' : 'Ibutang ang budget para ani nga bulan.', style: const TextStyle(color: Color(0xFFD4DED6), fontSize: 10))),
          TextButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 14), label: const Text('Edit'), style: TextButton.styleFrom(foregroundColor: gold, visualDensity: VisualDensity.compact)),
        ]),
      ]),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: forest, fontWeight: FontWeight.w900, fontSize: 17)), const SizedBox(height: 3), Text(subtitle, style: const TextStyle(color: muted, fontSize: 11))])),
  ]);
}

class _CategoryProgress extends StatelessWidget {
  const _CategoryProgress({required this.category, required this.amount, required this.total});
  final String category;
  final double amount;
  final double total;

  @override
  Widget build(BuildContext context) {
    final percent = total <= 0 ? 0.0 : (amount / total).clamp(0.0, 1.0);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(category, style: const TextStyle(color: Color(0xFF56645A), fontSize: 12))), Text(_currency.format(amount), style: const TextStyle(color: forest, fontSize: 12, fontWeight: FontWeight.w800))]),
      const SizedBox(height: 7),
      ClipRRect(borderRadius: BorderRadius.circular(20), child: LinearProgressIndicator(value: percent, minHeight: 6, backgroundColor: const Color(0xFFF0EFE7), color: const Color(0xFF608467))),
    ]);
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.row, required this.onDelete});
  final Map<String, dynamic> row;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isIncome = row['kind'] == 'income';
    final color = isIncome ? incomeColor : expenseColor;
    final amount = (row['amount'] as num).toDouble();
    final date = DateTime.tryParse(row['transaction_date'] as String? ?? '');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 3),
      leading: Container(width: 39, height: 39, decoration: BoxDecoration(color: const Color(0xFFF3F0E5), borderRadius: BorderRadius.circular(12)), child: Icon(isIncome ? Icons.north_east_rounded : Icons.south_east_rounded, color: color, size: 19)),
      title: Text(row['category'] as String? ?? 'Uban pa', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: forest)),
      subtitle: Text('${date == null ? '' : DateFormat('MMM d, yyyy').format(date)}${(row['note'] as String? ?? '').isEmpty ? '' : ' · ${row['note']}'}${row['sync_status'] == 'pending' ? ' · Pending sync' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: muted)),
      trailing: SizedBox(width: 105, child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        FittedBox(fit: BoxFit.scaleDown, child: Text('${isIncome ? '+' : '−'}${_currency.format(amount)}', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12))),
        const SizedBox(height: 1),
        InkWell(onTap: onDelete, child: const Padding(padding: EdgeInsets.symmetric(vertical: 2), child: Text('Delete', style: TextStyle(color: muted, fontSize: 10)))),
      ])),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});
  final IconData icon;
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 13),
    child: Column(children: [Icon(icon, color: const Color(0xFFB3BAAF), size: 28), const SizedBox(height: 8), Text(message, textAlign: TextAlign.center, style: const TextStyle(color: muted, fontSize: 12))]),
  );
}

class _TransactionInput {
  const _TransactionInput({required this.kind, required this.amount, required this.category, required this.date, required this.note});
  final String kind;
  final double amount;
  final String category;
  final DateTime date;
  final String note;
}

class _AddTransactionSheet extends StatefulWidget {
  const _AddTransactionSheet();
  @override
  State<_AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends State<_AddTransactionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _kind = 'expense';
  String _category = expenseCategories.first;
  DateTime _date = DateTime.now();

  @override
  void dispose() { _amount.dispose(); _note.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final categories = _kind == 'expense' ? expenseCategories : incomeCategories;
    if (!categories.contains(_category)) _category = categories.first;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(color: Color(0xFFFFFEFA), borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
            child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: lineColor, borderRadius: BorderRadius.circular(4)))),
              const SizedBox(height: 18),
              const Text('Dugang og record', style: TextStyle(color: forest, fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 15),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'expense', label: Text('Gasto'), icon: Icon(Icons.south_east_rounded)),
                  ButtonSegment(value: 'income', label: Text('Kita'), icon: Icon(Icons.north_east_rounded)),
                ],
                selected: {_kind},
                onSelectionChanged: (value) => setState(() { _kind = value.first; _category = (_kind == 'expense' ? expenseCategories : incomeCategories).first; }),
                style: SegmentedButton.styleFrom(selectedBackgroundColor: const Color(0xFFE8EFE8), selectedForegroundColor: forest),
              ),
              const SizedBox(height: 13),
              TextFormField(
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Kantidad (₱)', prefixText: '₱ ', hintText: '0.00'),
                validator: (value) { final n = double.tryParse(value ?? ''); return n == null || n <= 0 ? 'Ibutang ang kantidad nga mas dako sa zero.' : null; },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: categories.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                onChanged: (value) { if (value != null) setState(() => _category = value); },
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_rounded, color: forest),
                title: const Text('Petsa', style: TextStyle(fontSize: 12, color: muted)),
                subtitle: Text(DateFormat('MMMM d, yyyy').format(_date), style: const TextStyle(color: forest, fontWeight: FontWeight.w800)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  final value = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2000), lastDate: DateTime(2100));
                  if (value != null) setState(() => _date = value);
                },
              ),
              const SizedBox(height: 7),
              TextFormField(controller: _note, maxLength: 80, decoration: const InputDecoration(labelText: 'Nota (optional)', hintText: 'Pananglitan: pamasahe, lunch…')),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  if (!_formKey.currentState!.validate()) return;
                  Navigator.pop(context, _TransactionInput(
                    kind: _kind,
                    amount: (double.parse(_amount.text.trim()) * 100).roundToDouble() / 100,
                    category: _category,
                    date: _date,
                    note: _note.text.trim(),
                  ));
                },
                icon: const Icon(Icons.save_rounded),
                label: const Text('I-save ang record'),
                style: FilledButton.styleFrom(backgroundColor: forest, padding: const EdgeInsets.symmetric(vertical: 15)),
              ),
            ])),
          ),
        ),
      ),
    );
  }
}
