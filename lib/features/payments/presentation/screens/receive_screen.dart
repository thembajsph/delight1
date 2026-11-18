import '../../../../core/config/env.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/services/supabase_service.dart';

// Reads the phone straight from the profile row, so the QR does not depend on
// the cached auth state having loaded it.
final _myPhoneProvider = FutureProvider.autoDispose<String>((ref) async {
  final uid = SupabaseService.currentUser?.id;
  if (uid == null) return '';
  final p = await SupabaseService.getProfile(uid);
  return ((p?['phone'] as String?) ?? '').trim();
});

// ─── Receive Screen ───────────────────────────────────────────────────────

class ReceiveScreen extends ConsumerWidget {
  const ReceiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Custodial model: P2P payments are matched by phone number (see
    // send_payment edge function), not an on-chain address — there isn't
    // one per user. The QR just encodes the phone so Scan → Send prefills it.
    final user = ref.watch(authProvider);
    final dbPhone = ref.watch(_myPhoneProvider);
    final cached = (user?.phone ?? '').trim();
    final phone = cached.isNotEmpty ? cached : (dbPhone.valueOrNull ?? '');
    final loadingPhone = phone.isEmpty && dbPhone.isLoading;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: DelightColors.background,
      appBar: AppBar(
        title: const Text('Receive DC'),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => context.pop()),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              const Text('Your QR Code', style: TextStyle(
                fontFamily: 'Clash', fontSize: 24, fontWeight: FontWeight.w700,
                color: DelightColors.textPrimary,
              )),
              const SizedBox(height: 6),
              const Text('Others can scan this to pay you instantly',
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 14, color: DelightColors.textSecondary)),
              const SizedBox(height: 36),

              if (loadingPhone)
                const Padding(padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator())
              else if (phone.isEmpty)
                _PhoneCapture(onSaved: (v) {
                  ref.invalidate(_myPhoneProvider);
                  final u = ref.read(authProvider);
                  if (u != null) ref.read(authProvider.notifier).update(u.copyWith(phone: v));
                })
              else ...[
                // QR Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [BoxShadow(
                      color: DelightColors.emerald.withOpacity(0.2),
                      blurRadius: 32, spreadRadius: 4,
                    )],
                  ),
                  child: Column(children: [
                    QrImageView(
                      key: ValueKey(phone),
                      data: phone,
                      version: QrVersions.auto,
                      size: 220,
                      errorStateBuilder: (ctx, err) => SizedBox(
                        width: 220, height: 220,
                        child: Center(child: Text('QR error: $err',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red, fontSize: 12)))),
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Color(0xFF060F0A),
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Color(0xFF060F0A),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      phone,
                      style: const TextStyle(
                        fontFamily: 'Courier', fontSize: 13, color: Color(0xFF060F0A),
                        letterSpacing: 0.5, fontWeight: FontWeight.w600,
                      ),
                    ),
                  ]),
                ),

                const SizedBox(height: 16),

                // Copy phone number
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: phone));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Phone number copied')));
                  },
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      color: DelightColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: DelightColors.surfaceBorder),
                    ),
                    alignment: Alignment.center,
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
                      Icon(Icons.copy, color: DelightColors.emerald, size: 18),
                      SizedBox(width: 8),
                      Text('Copy Number', style: TextStyle(
                        fontFamily: 'Satoshi', fontSize: 16, fontWeight: FontWeight.w600,
                        color: DelightColors.emerald,
                      )),
                    ]),
                  ),
                ),
              ],
              const SizedBox(height: 12),

              const Text('Share your number via QR code or copy it',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 12, color: DelightColors.textMuted)),
          ],
          )),
        ),
      ),
    );
  }
}

// ─── Scan Screen ──────────────────────────────────────────────────────────

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});
  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final MobileScannerController _ctrl = MobileScannerController();
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final code = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (code == null) return;
    _handled = true;
    HapticFeedback.mediumImpact();
    // Business pay links open the item-picking screen directly.
    final uri = Uri.tryParse(code);
    if (uri != null && uri.host == Env.linkHost &&
        uri.pathSegments.length == 2 && uri.pathSegments.first == 'pay') {
      final v = uri.queryParameters['v'];
      context.pushReplacement(
        '/pay/${uri.pathSegments[1]}${v == null ? '' : '?v=$v'}');
      return;
    }
    Navigator.pop(context, code);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text('Scan QR Code',
          style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _ctrl.toggleTorch()),
          IconButton(
            icon: const Icon(Icons.cameraswitch_outlined),
            onPressed: () => _ctrl.switchCamera()),
        ]),
      body: Stack(children: [
        MobileScanner(controller: _ctrl, onDetect: _onDetect),
        Center(child: Container(
          width: 250, height: 250,
          decoration: BoxDecoration(
            border: Border.all(color: DelightColors.emerald, width: 3),
            borderRadius: BorderRadius.circular(16)))),
        Positioned(bottom: 60, left: 0, right: 0,
          child: Column(children: [
            const Text('Point at a DC wallet QR code',
              style: TextStyle(color: Colors.white, fontSize: 15,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(blurRadius: 6)])),
            const SizedBox(height: 4),
            const Text('or scan an NFT ticket',
              style: TextStyle(color: Colors.white70, fontSize: 13,
                shadows: [Shadow(blurRadius: 6)])),
          ])),
      ]));
  }
}


// Shown when the profile has no phone yet: P2P payments are matched by phone,
// so the QR needs one. Saving it here makes the QR appear immediately.
class _PhoneCapture extends StatefulWidget {
  final void Function(String phone) onSaved;
  const _PhoneCapture({required this.onSaved});
  @override State<_PhoneCapture> createState() => _PhoneCaptureState();
}

class _PhoneCaptureState extends State<_PhoneCapture> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _err;

  Future<void> _save() async {
    final v = _ctrl.text.replaceAll(RegExp(r'[\s-]'), '');
    if (!RegExp(r'^\+?[0-9]{9,15}$').hasMatch(v)) {
      setState(() => _err = 'Enter a valid number, e.g. +27821234567');
      return;
    }
    final uid = SupabaseService.currentUser?.id;
    if (uid == null) return;
    setState(() { _busy = true; _err = null; });
    try {
      await SupabaseService.updateProfile(uid, {'phone': v});
      widget.onSaved(v);
    } catch (e) {
      if (mounted) setState(() { _busy = false; _err = 'Could not save — is this number already used?'; });
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: DelightColors.surfaceHigh,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: DelightColors.surfaceBorder)),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Add your phone number to get your QR code. People pay you by this number.',
        textAlign: TextAlign.center,
        style: TextStyle(fontFamily: 'Satoshi', fontSize: 14, color: DelightColors.textSecondary)),
      const SizedBox(height: 14),
      TextField(
        controller: _ctrl, keyboardType: TextInputType.phone,
        decoration: InputDecoration(labelText: 'Phone number', errorText: _err)),
      const SizedBox(height: 12),
      SizedBox(width: double.infinity, height: 46,
        child: ElevatedButton(
          onPressed: _busy ? null : _save,
          child: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Save & show QR'))),
    ]));
}
