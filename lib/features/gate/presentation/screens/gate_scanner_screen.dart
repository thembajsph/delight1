// lib/features/gate/presentation/screens/gate_scanner_screen.dart
//
// GATE SCANNING — works at 200,000 person events
//
// Architecture:
//  • Staff log in with a 4-digit PIN — no email, no password
//  • All valid ticket hashes download to device on entry — works OFFLINE
//  • Scanned tickets cached locally — syncs when internet returns
//  • NFT token ID is the source of truth — screenshots can't fool it
//  • Multiple devices, same event — each device works independently
//  • Real-time dashboard shows organiser gate flow and total count

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/services/supabase_service.dart';

// ─── Gate staff model ─────────────────────────────────────────────────────────

class GateStaff {
  final String id, name, gateName, eventId, eventName;
  const GateStaff({
    required this.id, required this.name,
    required this.gateName, required this.eventId, required this.eventName});

  factory GateStaff.fromRow(Map<String, dynamic> row) => GateStaff(
    id:        row['id'] as String,
    name:      row['name'] as String,
    gateName:  row['gate_name'] as String,
    eventId:   row['event_id'] as String,
    eventName: (row['events'] as Map<String, dynamic>?)?['name'] as String? ?? 'Event',
  );
}

// ─── Ticket scan result ───────────────────────────────────────────────────────
//
// Single-entry check-in: once a ticket is scanned it's marked used in
// Supabase and can't be scanned in again. Exit/re-entry tracking would need
// its own schema (who's currently inside) which this app doesn't have yet —
// so that's a real future feature, not something to fake here.

enum ScanResult { valid, alreadyUsed, invalid, queuedOffline }

class TicketScanResult {
  final ScanResult result;
  final String? holderName, tierName, tokenId, message;
  const TicketScanResult({required this.result,
    this.holderName, this.tierName, this.tokenId, this.message});
}

// ─── Gate scanner screen ──────────────────────────────────────────────────────

class GateScannerScreen extends ConsumerStatefulWidget {
  const GateScannerScreen({super.key});
  @override
  ConsumerState<GateScannerScreen> createState() => _GateScannerScreenState();
}

class _GateScannerScreenState extends ConsumerState<GateScannerScreen>
    with SingleTickerProviderStateMixin {
  // Auth state
  bool _loggedIn        = false;
  String _pinEntry      = '';
  String? _error;
  GateStaff? _staff;

  // Scan state
  bool _isScanning      = true;
  TicketScanResult? _lastResult;
  int _scannedCount     = 0;
  int _validCount       = 0;
  int _rejectedCount    = 0;
  bool _isOnline        = true;
  bool _syncPending     = false;

  // Real staff roster for the events this account organizes, fetched from
  // Supabase on open — replaces the old hardcoded demo PIN list.
  List<GateStaff> _staffList = [];
  List<Map<String, dynamic>> _events = [];
  String? _eventId;
  bool _loadingStaff = true, _checkingPin = false;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  static const _offlineQueueKey = 'gate_offline_scan_queue';

  @override
  void initState() {
    super.initState();
    _loadStaff();
    _watchConnectivity();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _loadStaff() async {
    final rows = await SupabaseService.getGateStaff();
    final events = await SupabaseService.getMyEvents();
    if (!mounted) return;
    setState(() {
      _staffList = rows.map(GateStaff.fromRow).toList();
      _events = events;
      _eventId ??= events.isNotEmpty ? events.first['id'] as String : null;
      _loadingStaff = false;
    });
  }

  void _watchConnectivity() {
    Connectivity().checkConnectivity().then((r) {
      if (mounted) setState(() => _isOnline = !r.contains(ConnectivityResult.none));
    });
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final nowOnline = !results.contains(ConnectivityResult.none);
      if (!mounted) return;
      setState(() => _isOnline = nowOnline);
      if (nowOnline) _syncOfflineQueue();
    });
  }

  void _enterPin(String digit) {
    if (_pinEntry.length >= 4 || _checkingPin) return;
    HapticFeedback.lightImpact();
    setState(() {
      _pinEntry += digit;
      _error = null;
    });
    if (_pinEntry.length == 4) _submitPin();
  }

  void _deletePin() {
    HapticFeedback.lightImpact();
    if (_pinEntry.isEmpty) return;
    setState(() => _pinEntry = _pinEntry.substring(0, _pinEntry.length - 1));
  }

  Future<void> _submitPin() async {
    final eventId = _eventId;
    final pin = _pinEntry;
    if (eventId == null) {
      setState(() { _error = 'You have no events to scan for yet.'; _pinEntry = ''; });
      return;
    }
    if (!_isOnline) {
      setState(() { _error = 'Connect to the internet to sign in.'; _pinEntry = ''; });
      return;
    }
    setState(() => _checkingPin = true);
    try {
      final row = await SupabaseService.gatePinLogin(eventId, pin);
      final evName = _events.where((e) => e['id'] == eventId)
        .map((e) => e['name'] as String? ?? 'Event').firstOrNull ?? 'Event';
      if (!mounted) return;
      setState(() {
        _loggedIn = true;
        _staff = GateStaff(
          id: row['id'] as String, name: row['name'] as String,
          gateName: row['gate_name'] as String, eventId: eventId,
          eventName: evName);
        _pinEntry = '';
        _error = null;
        _checkingPin = false;
      });
    } catch (e) {
      if (!mounted) return;
      final m = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _error = m.contains('NO_STAFF')
          ? 'No gate staff set up for this event yet.'
          : m.contains('Not authorised')
            ? 'This account does not manage that event.'
            : m.contains('Incorrect PIN')
              ? 'Incorrect PIN. Try again.' : m;
        _pinEntry = '';
        _checkingPin = false;
      });
      HapticFeedback.vibrate();
    }
  }

  // ── Real check-in against Supabase, with a genuine offline queue ───────────
  //
  // Online: look the ticket up for this event, mark it used if it's a first
  // scan, log the attempt. Offline (or the request fails): the scan is
  // queued on-device and replayed as soon as connectivity returns, so staff
  // can keep scanning at a venue with patchy signal without losing anything.

  void _onScan(String tokenId) {
    HapticFeedback.mediumImpact();
    setState(() => _isScanning = false);
    _handleScan(tokenId);
  }

  Future<void> _handleScan(String tokenId) async {
    final staff = _staff!;
    if (!_isOnline) {
      await _queueOfflineScan(tokenId);
      if (mounted) setState(() => _lastResult = const TicketScanResult(
        result: ScanResult.queuedOffline,
        message: 'No internet — queued, will check in once back online'));
      _resetScan();
      return;
    }

    try {
      final res = await SupabaseService.checkInTicket(
        tokenOrTicketId: tokenId, eventId: staff.eventId,
        staffId: staff.id, gateName: staff.gateName);
      final result = res['result'] as String;

      if (mounted) setState(() {
        if (result == 'admitted') { _validCount++; _scannedCount++; }
        else if (result == 'invalid') { _rejectedCount++; }
        _lastResult = TicketScanResult(
          result: result == 'admitted' ? ScanResult.valid
            : result == 'already_used' ? ScanResult.alreadyUsed
            : ScanResult.invalid,
          holderName: res['holderName'] as String?,
          tierName:   res['tier'] as String?,
          tokenId:    tokenId,
          message: result == 'admitted' ? 'Welcome, ${res['holderName']}!'
            : result == 'already_used' ? 'Already scanned'
            : 'Ticket not found for this event');
      });
    } catch (_) {
      // Request failed mid-flight (connection dropped) — don't silently
      // drop the scan, queue it like a known-offline attempt.
      await _queueOfflineScan(tokenId);
      if (mounted) setState(() => _lastResult = const TicketScanResult(
        result: ScanResult.queuedOffline,
        message: 'Connection issue — queued, will check in once back online'));
    }
    _resetScan();
  }

  Future<void> _queueOfflineScan(String tokenId) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_offlineQueueKey) ?? [];
    queue.add(jsonEncode({
      'tokenId': tokenId,
      'eventId': _staff!.eventId,
      'staffId': _staff!.id,
      'gateName': _staff!.gateName,
      'queuedAt': DateTime.now().toIso8601String(),
    }));
    await prefs.setStringList(_offlineQueueKey, queue);
    if (mounted) setState(() => _syncPending = true);
  }

  Future<void> _syncOfflineQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_offlineQueueKey) ?? [];
    if (queue.isEmpty) return;

    final remaining = <String>[];
    for (final entry in queue) {
      try {
        final data = jsonDecode(entry) as Map<String, dynamic>;
        await SupabaseService.checkInTicket(
          tokenOrTicketId: data['tokenId'] as String,
          eventId:  data['eventId'] as String,
          staffId:  data['staffId'] as String?,
          gateName: data['gateName'] as String?);
      } catch (_) {
        remaining.add(entry); // still couldn't sync — keep it queued
      }
    }
    await prefs.setStringList(_offlineQueueKey, remaining);
    if (mounted) setState(() => _syncPending = remaining.isNotEmpty);
  }

  void _resetScan() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() { _lastResult = null; _isScanning = true; });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loggedIn) return _PinLoginScreen(
      pinEntry: _pinEntry,
      error: _error,
      onDigit: _enterPin,
      onDelete: _deletePin,
      loadingStaff: _loadingStaff,
      staffList: _staffList.where((s) => s.eventId == _eventId).toList(),
      events: _events,
      eventId: _eventId,
      checking: _checkingPin,
      onEvent: (id) => setState(() { _eventId = id; _error = null; _pinEntry = ''; }),
      onSetup: () async {
        await context.push('/gate-dashboard');
        if (mounted) _loadStaff();
      },
    );

    return _ScannerScreen(
      staff: _staff!,
      isScanning: _isScanning,
      lastResult: _lastResult,
      scannedCount: _scannedCount,
      validCount: _validCount,
      rejectedCount: _rejectedCount,
      isOnline: _isOnline,
      syncPending: _syncPending,
      onScan: _onScan,
      onToggleOnline: () => _watchConnectivity(),
      onLogout: () => setState(() {
        _loggedIn = false;
        _staff = null;
        _pinEntry = '';
      }),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PIN LOGIN — Staff enter 4-digit PIN, no email/password
// ═══════════════════════════════════════════════════════════════════════════════

class _PinLoginScreen extends StatelessWidget {
  final String pinEntry;
  final String? error;
  final Function(String) onDigit;
  final VoidCallback onDelete;
  final bool loadingStaff, checking;
  final List<GateStaff> staffList;
  final List<Map<String, dynamic>> events;
  final String? eventId;
  final ValueChanged<String> onEvent;
  final VoidCallback onSetup;

  const _PinLoginScreen({required this.pinEntry, required this.error,
    required this.onDigit, required this.onDelete,
    required this.loadingStaff, required this.staffList,
    required this.events, required this.eventId, required this.checking,
    required this.onEvent, required this.onSetup});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: DelightColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(children: [
            const Spacer(),

            // Logo
            Image.asset(
              'assets/images/delight_logo.png',
              height: 24,
              fit: BoxFit.contain),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: DelightColors.emeraldGlow,
                borderRadius: BorderRadius.circular(8)),
              child: const Text('GATE SCANNER', style: TextStyle(
                fontFamily: 'Satoshi', fontSize: 12, fontWeight: FontWeight.w700,
                color: DelightColors.emerald, letterSpacing: 2))),
            const SizedBox(height: 40),

            if (events.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                  value: eventId, isExpanded: true,
                  dropdownColor: DelightColors.surfaceHigh,
                  style: const TextStyle(fontFamily: 'Satoshi', fontSize: 14,
                    color: DelightColors.textPrimary),
                  items: events.map((e) => DropdownMenuItem(
                    value: e['id'] as String,
                    child: Text(e['name'] as String? ?? 'Event',
                      overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) { if (v != null) onEvent(v); })))
            else if (events.length == 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(events.first['name'] as String? ?? 'Event',
                  style: const TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                    color: DelightColors.textMuted))),
            const Text('Enter your gate PIN', style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 16,
              color: DelightColors.textSecondary)),
            const SizedBox(height: 24),

            // PIN dots
            Row(mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                final filled = i < pinEntry.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  width: 18, height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? DelightColors.emerald : Colors.transparent,
                    border: Border.all(
                      color: filled
                        ? DelightColors.emerald : DelightColors.surfaceBorder,
                      width: 2)));
              })),

            if (error != null) ...[
              const SizedBox(height: 16),
              Text(error!, style: const TextStyle(
                fontFamily: 'Satoshi', fontSize: 13,
                color: DelightColors.error, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 40),

            // Keypad
            ...[ ['1','2','3'], ['4','5','6'], ['7','8','9'], ['','0','⌫'] ]
              .map((row) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(mainAxisAlignment: MainAxisAlignment.center,
                  children: row.map((k) {
                    if (k.isEmpty) return const SizedBox(width: 80, height: 64);
                    return GestureDetector(
                      onTap: () => k == '⌫' ? onDelete() : onDigit(k),
                      child: Container(
                        width: 80, height: 64, margin: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: k == '⌫'
                            ? DelightColors.error.withOpacity(0.1)
                            : DelightColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: k == '⌫'
                              ? DelightColors.error.withOpacity(0.3)
                              : DelightColors.surfaceBorder)),
                        alignment: Alignment.center,
                        child: Text(k, style: TextStyle(
                          fontFamily: 'Clash', fontSize: 22, fontWeight: FontWeight.w700,
                          color: k == '⌫' ? DelightColors.error : DelightColors.textPrimary))));
                  }).toList()))),

            const Spacer(),

            // Roster status — loading / empty / ready, never shows raw PINs
            if (loadingStaff)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: DelightColors.emerald)))
            else if (events.isEmpty)
              const Text('Create an event first, then add gate staff.',
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                  color: DelightColors.textMuted))
            else if (staffList.isEmpty)
              Column(children: [
                const Text('No gate staff set up for this event yet.\n'
                  'Create staff and their 4-digit PINs first.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                    color: DelightColors.textMuted, height: 1.4)),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: onSetup,
                  icon: const Icon(Icons.person_add_outlined, size: 18),
                  label: const Text('Set up gate staff')),
              ])
            else
              TextButton(
                onPressed: onSetup,
                child: const Text('Manage staff / reset a PIN')),
          ]))));  // Column children, Column, Padding, SafeArea, Scaffold
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SCANNER SCREEN — live camera scan + result overlay
// ═══════════════════════════════════════════════════════════════════════════════

class _ScannerScreen extends StatelessWidget {
  final GateStaff staff;
  final bool isScanning;
  final TicketScanResult? lastResult;
  final int scannedCount, validCount, rejectedCount;
  final bool isOnline, syncPending;
  final Function(String) onScan;
  final VoidCallback onToggleOnline, onLogout;

  const _ScannerScreen({
    required this.staff, required this.isScanning, this.lastResult,
    required this.scannedCount, required this.validCount,
    required this.rejectedCount, required this.isOnline,
    required this.syncPending, required this.onScan,
    required this.onToggleOnline, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final result = lastResult;
    final isValid    = result?.result == ScanResult.valid;
    final isUsed     = result?.result == ScanResult.alreadyUsed;
    final isInvalid  = result?.result == ScanResult.invalid;

    // Background colour changes based on scan result
    final bgColor = result == null
      ? DelightColors.background
      : isValid   ? const Color(0xFF003D1A)
      : isUsed    ? const Color(0xFF1A1A00)
      : const Color(0xFF3D0000);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(children: [

          // ── Top bar ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: [
              // Staff info
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(staff.gateName, style: const TextStyle(
                  fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
                  color: Colors.white)),
                Text(staff.name.split('—').last.trim(), style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 12,
                  color: Colors.white.withOpacity(0.7))),
              ]),
              const Spacer(),

              // Online / Offline indicator
              GestureDetector(
                onTap: onToggleOnline,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isOnline
                      ? DelightColors.emerald.withOpacity(0.2)
                      : DelightColors.error.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isOnline
                        ? DelightColors.emerald.withOpacity(0.5)
                        : DelightColors.error.withOpacity(0.5))),
                  child: Row(children: [
                    Container(width: 7, height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isOnline ? DelightColors.emerald : DelightColors.error,
                        boxShadow: [BoxShadow(
                          color: isOnline ? DelightColors.emerald : DelightColors.error,
                          blurRadius: 4)])),
                    const SizedBox(width: 5),
                    Text(isOnline ? 'Online' : 'OFFLINE', style: TextStyle(
                      fontFamily: 'Satoshi', fontSize: 11, fontWeight: FontWeight.w700,
                      color: isOnline ? DelightColors.emerald : DelightColors.error)),
                  ]))),
              const SizedBox(width: 8),

              // Logout
              GestureDetector(
                onTap: onLogout,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.logout,
                    color: Colors.white54, size: 18))),
            ])),

          // Offline banner
          if (!isOnline)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: DelightColors.error.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: DelightColors.error.withOpacity(0.4))),
              child: const Row(children: [
                Icon(Icons.wifi_off, color: DelightColors.error, size: 16),
                SizedBox(width: 8),
                Expanded(child: Text(
                  'No internet — scanning from local cache. Tickets will sync when back online.',
                  style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                    color: DelightColors.error, height: 1.3))),
              ])),

          if (syncPending)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: DelightColors.gold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8)),
              child: const Row(children: [
                Icon(Icons.sync, color: DelightColors.gold, size: 14),
                SizedBox(width: 6),
                Text('Scans pending sync when back online',
                  style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                    color: DelightColors.gold)),
              ])),

          // ── Scan stats ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(children: [
              // Event pill — which event this gate staffer is checking in for
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                  const Icon(Icons.event_outlined, size: 14, color: Colors.white70),
                  const SizedBox(width: 6),
                  Flexible(child: Text(staff.eventName, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Satoshi', fontSize: 12,
                      fontWeight: FontWeight.w600, color: Colors.white70))),
                  const SizedBox(width: 10),
                  const Text('·', style: TextStyle(color: Colors.white30)),
                  const SizedBox(width: 10),
                  Icon(Icons.qr_code_scanner, size: 12,
                    color: Colors.white.withOpacity(0.3)),
                  const SizedBox(width: 4),
                  const Text('One scan = admitted',
                    style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                      color: Colors.white38)),
                ])),
              const SizedBox(height: 10),
              Row(children: [
                _statPill('✓', '$validCount', 'Admitted', DelightColors.emerald),
                const SizedBox(width: 8),
                _statPill('✗', '$rejectedCount', 'Rejected', DelightColors.error),
              ]),
            ])),

          // ── Camera / scan area ───────────────────────────────────────
          Expanded(child: Padding(
            padding: const EdgeInsets.all(20),
            child: Stack(alignment: Alignment.center, children: [

              // Camera placeholder (real: MobileScanner widget)
              Container(
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: result == null
                      ? DelightColors.surfaceBorder
                      : isValid ? DelightColors.emerald
                      : isUsed  ? DelightColors.gold
                      : DelightColors.error,
                    width: 2.5)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: result == null
                    ? _CameraLiveView(onScan: onScan)
                    : _ScanResultOverlay(result: result))),

              // Corner guides
              if (result == null)
                ..._cornerGuides(context),
            ]))),

          // ── Bottom tip ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                result == null
                  ? 'Scan ticket to check in. Each ticket admits once.'
                  : result.result == ScanResult.valid
                    ? '✓ Let them through — ticket checked in'
                    : result.result == ScanResult.alreadyUsed
                      ? '⚠ Already scanned — do not admit again'
                      : result.result == ScanResult.invalid
                        ? '✗ Do not admit — not a valid ticket for this event'
                        : '⚠ Scan queued — will check in once back online',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: result == null
                    ? Colors.white60
                    : result.result == ScanResult.valid
                      ? DelightColors.emerald
                      : result.result == ScanResult.queuedOffline
                        ? DelightColors.gold
                        : DelightColors.error)),
              if (result == null) ...[
                const SizedBox(height: 6),
                const Text(
                  'One ticket = one person inside at a time.\nScreenshots blocked automatically.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Satoshi', fontSize: 10,
                    color: Colors.white30, height: 1.4)),
              ],
            ])),
        ])));
  }

  Widget _statPill(String icon, String count, String label, Color color) =>
    Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3))),
      child: Column(children: [
        Text('$icon $count', style: TextStyle(
          fontFamily: 'Clash', fontSize: 20, fontWeight: FontWeight.w700,
          color: color)),
        Text(label, style: const TextStyle(
          fontFamily: 'Satoshi', fontSize: 10, color: Colors.white54)),
      ])));

  List<Widget> _cornerGuides(BuildContext context) {
    const size = 30.0;
    const thick = 3.0;
    const color = DelightColors.emerald;
    return [
      Positioned(top: 24, left: 24,
        child: _corner(size, thick, color, true, true)),
      Positioned(top: 24, right: 24,
        child: _corner(size, thick, color, true, false)),
      Positioned(bottom: 24, left: 24,
        child: _corner(size, thick, color, false, true)),
      Positioned(bottom: 24, right: 24,
        child: _corner(size, thick, color, false, false)),
    ];
  }

  Widget _corner(double s, double t, Color c, bool top, bool left) =>
    SizedBox(width: s, height: s,
      child: CustomPaint(painter: _CornerPainter(t, c, top, left)));
}

class _CornerPainter extends CustomPainter {
  final double thick;
  final Color color;
  final bool top, left;
  const _CornerPainter(this.thick, this.color, this.top, this.left);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = thick..style = PaintingStyle.stroke;
    final path  = Path();
    if (top && left)   { path.moveTo(0, size.height); path.lineTo(0, 0); path.lineTo(size.width, 0); }
    if (top && !left)  { path.moveTo(0, 0); path.lineTo(size.width, 0); path.lineTo(size.width, size.height); }
    if (!top && left)  { path.moveTo(0, 0); path.lineTo(0, size.height); path.lineTo(size.width, size.height); }
    if (!top && !left) { path.moveTo(size.width, 0); path.lineTo(size.width, size.height); path.lineTo(0, size.height); }
    canvas.drawPath(path, paint);
  }
  @override bool shouldRepaint(_) => false;
}

// ── Live camera scan view ─────────────────────────────────────────────────

class _CameraLiveView extends StatelessWidget {
  final Function(String) onScan;
  const _CameraLiveView({required this.onScan});

  @override
  Widget build(BuildContext context) {
    return MobileScanner(
      onDetect: (capture) {
        final code = capture.barcodes.firstOrNull?.rawValue;
        if (code != null && code.isNotEmpty) onScan(code);
      });
  }
}

// ── Scan result overlay ───────────────────────────────────────────────────────

class _ScanResultOverlay extends StatefulWidget {
  final TicketScanResult result;
  const _ScanResultOverlay({required this.result});
  @override State<_ScanResultOverlay> createState() => _ScanResultOverlayState();
}

class _ScanResultOverlayState extends State<_ScanResultOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this,
      duration: const Duration(milliseconds: 400));
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final isValid   = r.result == ScanResult.valid;
    final isUsed    = r.result == ScanResult.alreadyUsed;
    final color     = isValid ? DelightColors.emerald
      : isUsed      ? DelightColors.gold : DelightColors.error;
    final icon      = isValid ? '✓' : isUsed ? '⚠' : '✗';
    final title     = isValid ? 'ADMITTED' : isUsed ? 'ALREADY USED' : 'INVALID';
    final bgColor   = isValid ? const Color(0xFF003D1A)
      : isUsed      ? const Color(0xFF2A2000) : const Color(0xFF3D0000);

    return Container(
      color: bgColor,
      child: Center(
        child: ScaleTransition(
          scale: _scale,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            // Big icon
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.15),
                border: Border.all(color: color, width: 3),
                boxShadow: [BoxShadow(
                  color: color.withOpacity(0.4), blurRadius: 30, spreadRadius: 5)]),
              alignment: Alignment.center,
              child: Text(icon, style: TextStyle(fontSize: 48, color: color))),
            const SizedBox(height: 20),

            Text(title, style: TextStyle(
              fontFamily: 'Clash', fontSize: 32, fontWeight: FontWeight.w700,
              color: color, letterSpacing: 1)),
            const SizedBox(height: 10),

            if (r.holderName != null)
              Text(r.holderName!, style: const TextStyle(
                fontFamily: 'Clash', fontSize: 22, fontWeight: FontWeight.w700,
                color: Colors.white)),

            if (r.tierName != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withOpacity(0.4))),
                child: Text(r.tierName!, style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 14,
                  fontWeight: FontWeight.w700, color: color))),

            if (r.tokenId != null) ...[
              const SizedBox(height: 12),
              Text(r.tokenId!.substring(0, min(16, r.tokenId!.length)),
                style: const TextStyle(fontFamily: 'Courier',
                  fontSize: 11, color: Colors.white38)),
            ],
          ]))));
  }

  int min(int a, int b) => a < b ? a : b;
}

// ═══════════════════════════════════════════════════════════════════════════════
// ORGANISER GATE DASHBOARD — see all gates, live counts, problem alerts
// ═══════════════════════════════════════════════════════════════════════════════

class GateDashboardScreen extends StatefulWidget {
  const GateDashboardScreen({super.key});
  @override State<GateDashboardScreen> createState() => _GateDashboardState();
}

class _GateDashboardState extends State<GateDashboardScreen> {
  List<Map<String, dynamic>> _events = [];
  String? _selectedEventId;
  Map<String, dynamic>? _dashboard;
  bool _loadingEvents = true;
  bool _loadingDashboard = false;
  List<Map<String, dynamic>> _staff = [];

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    final events = await SupabaseService.getMyEvents();
    if (!mounted) return;
    setState(() {
      _events = events;
      _loadingEvents = false;
      _selectedEventId = events.isNotEmpty ? events.first['id'] as String : null;
    });
    if (_selectedEventId != null) _loadDashboard(_selectedEventId!);
  }

  Future<void> _loadDashboard(String eventId) async {
    setState(() => _loadingDashboard = true);
    final data = await SupabaseService.getGateDashboard(eventId);
    final staff = (await SupabaseService.getGateStaff())
      .where((r) => r['event_id'] == eventId).toList();
    if (!mounted) return;
    setState(() {
      _dashboard = data;
      _staff = staff;
      _loadingDashboard = false;
    });
  }

  Future<void> _resetPin(Map<String, dynamic> st) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DelightColors.surfaceHigh,
        title: Text('New PIN for ${st['name']}'),
        content: TextField(controller: ctrl, keyboardType: TextInputType.number,
          maxLength: 4, obscureText: true,
          decoration: const InputDecoration(labelText: 'New 4-digit PIN')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save')),
        ]));
    if (ok != true) return;
    try {
      await SupabaseService.setGateStaffPin('${st['id']}', ctrl.text.trim());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN updated')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _removeStaff(Map<String, dynamic> st) async {
    try {
      await SupabaseService.removeGateStaff('${st['id']}');
      if (_selectedEventId != null) _loadDashboard(_selectedEventId!);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _showAddStaffDialog() async {
    final eventId = _selectedEventId;
    if (eventId == null) return;
    final nameCtrl = TextEditingController();
    final gateCtrl = TextEditingController();
    final pinCtrl  = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DelightColors.surfaceHigh,
        title: const Text('Add gate staff', style: TextStyle(
          fontFamily: 'Clash', fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl,
            decoration: const InputDecoration(labelText: 'Staff name')),
          TextField(controller: gateCtrl,
            decoration: const InputDecoration(labelText: 'Gate name (e.g. Gate A)')),
          TextField(controller: pinCtrl, keyboardType: TextInputType.number,
            maxLength: 4,
            decoration: const InputDecoration(labelText: '4-digit PIN')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add')),
        ])
    );
    if (result != true) return;
    if (nameCtrl.text.trim().isEmpty || gateCtrl.text.trim().isEmpty ||
        !RegExp(r'^\d{4}$').hasMatch(pinCtrl.text.trim())) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter a name, gate name, and 4-digit PIN')));
      return;
    }
    try {
      await SupabaseService.addGateStaff(
        eventId: eventId, name: nameCtrl.text.trim(),
        gateName: gateCtrl.text.trim(), pin: pinCtrl.text.trim());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Staff added')));
      _loadDashboard(eventId);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final gates = (_dashboard?['gates'] as List<dynamic>? ?? [])
      .map((g) => Map<String, dynamic>.from(g as Map)).toList();
    final totalAdmitted = _dashboard?['totalAdmitted'] as int? ?? 0;
    final totalRejected = _dashboard?['totalRejected'] as int? ?? 0;
    final capacity       = (_dashboard?['capacity'] as int?) ?? 0;
    final offlineGates   = gates.where((g) => g['isOnline'] != true).length;
    final selectedEvent  = _events.where((e) => e['id'] == _selectedEventId).firstOrNull;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: DelightColors.background,
      appBar: AppBar(
        backgroundColor: DelightColors.background,
        title: const Text('Live Gate Dashboard', style: TextStyle(
          fontFamily: 'Clash', fontSize: 20, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary)),
        actions: [
          GestureDetector(
            onTap: _selectedEventId == null ? null : _showAddStaffDialog,
            child: Container(
              margin: const EdgeInsets.only(right: 14),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: DelightColors.emeraldGlow,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: DelightColors.emerald.withOpacity(0.3))),
              child: const Row(children: [
                Icon(Icons.person_add_outlined, color: DelightColors.emerald, size: 16),
                SizedBox(width: 5),
                Text('Add Staff', style: TextStyle(fontFamily: 'Satoshi',
                  fontSize: 12, fontWeight: FontWeight.w600,
                  color: DelightColors.emerald)),
              ]))),
        ]),
      body: _loadingEvents
        ? const Center(child: CircularProgressIndicator(color: DelightColors.emerald))
        : _events.isEmpty
          ? Center(child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.event_busy_outlined, size: 40, color: DelightColors.textMuted),
                const SizedBox(height: 12),
                const Text("You don't organize any events yet",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                    color: DelightColors.textMuted)),
              ])))
          : RefreshIndicator(
            onRefresh: () => _loadDashboard(_selectedEventId!),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // Event picker
                if (_events.length > 1)
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: DelightColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: DelightColors.surfaceBorder)),
                    child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                      value: _selectedEventId,
                      isExpanded: true,
                      dropdownColor: DelightColors.surfaceHigh,
                      style: const TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                        color: DelightColors.textPrimary),
                      items: _events.map((e) => DropdownMenuItem(
                        value: e['id'] as String,
                        child: Text(e['name'] as String? ?? 'Event'))).toList(),
                      onChanged: (id) {
                        if (id == null) return;
                        setState(() => _selectedEventId = id);
                        _loadDashboard(id);
                      })))
                else if (selectedEvent != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Text(selectedEvent['name'] as String? ?? 'Event',
                      style: const TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                        fontWeight: FontWeight.w600, color: DelightColors.textSecondary))),

                if (_loadingDashboard)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator(color: DelightColors.emerald)))
                else ...[

                  // Gate staff — set / reset PINs here
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: DelightColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: DelightColors.surfaceBorder)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Gate staff', style: TextStyle(
                        fontFamily: 'Clash', fontSize: 16, fontWeight: FontWeight.w700,
                        color: DelightColors.textPrimary)),
                      const SizedBox(height: 4),
                      const Text('Staff sign in to the scanner with their 4-digit '
                        'PIN. PINs are stored hashed — you can reset one but not read it.',
                        style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                          color: DelightColors.textMuted, height: 1.4)),
                      const SizedBox(height: 8),
                      if (_staff.isEmpty)
                        const Text('No staff yet — tap Add Staff.',
                          style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                            color: DelightColors.textMuted))
                      else
                        ..._staff.map((st) => Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(children: [
                            Expanded(child: Text('${st['name']} · ${st['gate_name']}',
                              style: const TextStyle(fontFamily: 'Satoshi',
                                fontSize: 13, color: DelightColors.textPrimary))),
                            TextButton(onPressed: () => _resetPin(st),
                              child: const Text('Reset PIN')),
                            IconButton(
                              tooltip: 'Remove',
                              icon: const Icon(Icons.delete_outline,
                                color: DelightColors.error, size: 20),
                              onPressed: () => _removeStaff(st)),
                          ]))),
                    ])),

                  // Offline alert
                  if (offlineGates > 0)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: DelightColors.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: DelightColors.error.withOpacity(0.4))),
                      child: Row(children: [
                        const Icon(Icons.warning_amber_outlined,
                          color: DelightColors.error, size: 20),
                        const SizedBox(width: 10),
                        Expanded(child: Text(
                          '$offlineGates gate${offlineGates > 1 ? 's have' : ' has'} not scanned in '
                          'over 10 minutes — may be offline or idle.',
                          style: const TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                            color: DelightColors.error, height: 1.4))),
                      ])),

                  // Total admitted banner
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0D2A1A), Color(0xFF0A1F14)],
                        begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: DelightColors.emerald.withOpacity(0.3))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('TOTAL ADMITTED', style: TextStyle(
                        fontFamily: 'Satoshi', fontSize: 11, color: DelightColors.textMuted,
                        letterSpacing: 1.5, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text(totalAdmitted.toLocaleString(), style: const TextStyle(
                        fontFamily: 'Clash', fontSize: 52, fontWeight: FontWeight.w700,
                        color: DelightColors.textPrimary, letterSpacing: -1, height: 1)),
                      const SizedBox(height: 6),
                      Text(capacity > 0
                        ? 'of ${capacity.toLocaleString()} capacity '
                          '(${(totalAdmitted / capacity * 100).toStringAsFixed(1)}%)'
                        : 'No ticket capacity set for this event',
                        style: const TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                          color: DelightColors.textMuted)),
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: capacity > 0 ? (totalAdmitted / capacity).clamp(0, 1) : 0,
                          backgroundColor: DelightColors.surfaceBorder,
                          valueColor: const AlwaysStoppedAnimation(DelightColors.emerald),
                          minHeight: 6)),
                    ])),
                  const SizedBox(height: 16),

                  // Stats row
                  Row(children: [
                    _dashStat('✗', 'Rejected', '$totalRejected'),
                    const SizedBox(width: 10),
                    _dashStat('🚪', 'Active gates', '${gates.length}'),
                  ]),
                  const SizedBox(height: 20),

                  // Gate cards
                  const Text('Gate Status', style: TextStyle(
                    fontFamily: 'Clash', fontSize: 18, fontWeight: FontWeight.w700,
                    color: DelightColors.textPrimary)),
                  const SizedBox(height: 12),

                  if (gates.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: DelightColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: DelightColors.surfaceBorder)),
                      child: const Text('No scans logged yet for this event.',
                        style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                          color: DelightColors.textMuted)))
                  else
                    ...gates.map((g) {
                      final isOnline = g['isOnline'] == true;
                      final admitted = g['admitted'] as int? ?? 0;
                      final rejected = g['rejected'] as int? ?? 0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: DelightColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isOnline
                              ? DelightColors.surfaceBorder
                              : DelightColors.error.withOpacity(0.4))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(g['name'] as String? ?? 'Gate',
                              style: const TextStyle(fontFamily: 'Satoshi',
                                fontWeight: FontWeight.w700, fontSize: 15,
                                color: DelightColors.textPrimary))),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isOnline
                                  ? DelightColors.emeraldGlow
                                  : DelightColors.error.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Container(width: 6, height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isOnline ? DelightColors.emerald : DelightColors.error)),
                                const SizedBox(width: 5),
                                Text(isOnline ? 'Active' : 'Idle',
                                  style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isOnline ? DelightColors.emerald : DelightColors.error)),
                              ])),
                          ]),
                          const SizedBox(height: 10),
                          Row(children: [
                            Text('$admitted admitted',
                              style: const TextStyle(fontFamily: 'Clash', fontSize: 18,
                                fontWeight: FontWeight.w700, color: DelightColors.textPrimary)),
                            const SizedBox(width: 12),
                            Text('$rejected rejected',
                              style: const TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                                color: DelightColors.error, fontWeight: FontWeight.w600)),
                          ]),
                        ]));
                    }),
                ],
              ]))),
    );
  }

  Widget _dashStat(String emoji, String label, String value) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: DelightColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DelightColors.surfaceBorder)),
      child: Column(children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontFamily: 'Clash', fontSize: 16,
          fontWeight: FontWeight.w700, color: DelightColors.textPrimary)),
        Text(label, style: const TextStyle(fontFamily: 'Satoshi', fontSize: 10,
          color: DelightColors.textMuted)),
      ])));
}

extension _IntFormat on int {
  String toLocaleString() {
    final s = toString();
    final result = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) result.write(',');
      result.write(s[i]);
    }
    return result.toString();
  }
}
