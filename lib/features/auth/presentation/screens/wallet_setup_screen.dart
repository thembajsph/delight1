import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xrpl_dart/xrpl_dart.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/services/xrpl_service.dart';

class WalletSetupScreen extends ConsumerStatefulWidget {
  const WalletSetupScreen({super.key});
  @override
  ConsumerState<WalletSetupScreen> createState() => _WalletSetupScreenState();
}

class _WalletSetupScreenState extends ConsumerState<WalletSetupScreen> {
  bool _isCreating = true;
  bool _loading = false;
  bool _walletCreated = false;
  String? _newAddress;
  String? _newSeed;
  bool _confirmedBackup = false;
  final _importAddressCtrl = TextEditingController();
  final _importSeedCtrl = TextEditingController();

  @override
  void dispose() { _importAddressCtrl.dispose(); _importSeedCtrl.dispose(); super.dispose(); }

  Future<void> _createWallet() async {
    setState(() => _loading = true);
    try {
      final wallet = XRPPrivateKey.random();
      final address = wallet.getPublic().toClassicAddress().address;
      final seed = wallet.toHex();

      await const FlutterSecureStorage().write(key: 'xrp_pk_$address', value: seed);

      setState(() {
        _newAddress = address;
        _newSeed = seed;
        _walletCreated = true;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create wallet: $e')));
      }
    }
  }

  void _confirmAndProceed() {
    if (_newAddress != null && _newSeed != null) {
      ref.read(walletProvider.notifier).createWallet(_newAddress!, _newSeed!);
      ref.read(analyticsProvider.notifier).track('wallet_created');
      context.go('/feed');
    }
  }

  bool _importing = false;

  Future<void> _importWallet() async {
    final seed = _importSeedCtrl.text.trim();
    if (seed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your secret key')));
      return;
    }
    setState(() => _importing = true);
    try {
      final wallet = XRPPrivateKey.fromHex(seed);
      final derivedAddress = wallet.getPublic().toClassicAddress().address;

      await const FlutterSecureStorage().write(
        key: 'xrp_pk_$derivedAddress', value: seed);

      final realBalance = await XrplService.getBalance(derivedAddress);

      ref.read(walletProvider.notifier).importWallet(
        derivedAddress, seed, realBalance);
      ref.read(analyticsProvider.notifier).track('wallet_imported');
      if (mounted) context.go('/feed');
    } catch (e) {
      setState(() => _importing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed — check your secret key: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: DelightColors.background,
      appBar: AppBar(
        title: const Text('Set Up Wallet'),
        backgroundColor: DelightColors.background,
        leading: _walletCreated ? null : const BackButton(),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tab toggle
              Container(
                height: 52,
                decoration: BoxDecoration(
                  color: DelightColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: DelightColors.surfaceBorder),
                ),
                child: Row(
                  children: [
                    _tab('Create Wallet', true),
                    _tab('Import Wallet', false),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              if (_isCreating) _buildCreateFlow() else _buildImportFlow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(String label, bool isCreate) {
    final selected = _isCreating == isCreate;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() { _isCreating = isCreate; _walletCreated = false; }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            gradient: selected ? const LinearGradient(colors: DelightColors.emeraldGradient) : null,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(
            fontFamily: 'Satoshi', fontSize: 14, fontWeight: FontWeight.w700,
            color: selected ? DelightColors.textInverse : DelightColors.textMuted,
          )),
        ),
      ),
    );
  }

  Widget _buildCreateFlow() {
    if (!_walletCreated) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your DC Wallet', style: TextStyle(
            fontFamily: 'Clash', fontSize: 26, fontWeight: FontWeight.w700,
            color: DelightColors.textPrimary,
          )),
          const SizedBox(height: 10),
          const Text(
            'We\'ll generate a secure DC wallet for you. This wallet stores your DC, NFT tickets, and transaction history.',
            style: TextStyle(fontFamily: 'Satoshi', fontSize: 14, color: DelightColors.textSecondary, height: 1.6),
          ),
          const SizedBox(height: 32),

          // Feature pills
          ...[
            ('⚡', 'Near-instant payments with DC'),
            ('🎟️', 'Store your NFT event tickets'),
            ('🔒', 'Encrypted, secure key storage'),
            ('💳', 'Low platform fees (1.5–3%)'),
          ].map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              Text(item.$1, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 12),
              Text(item.$2, style: const TextStyle(
                fontFamily: 'Satoshi', fontSize: 14, color: DelightColors.textPrimary,
              )),
            ]),
          )),

          const SizedBox(height: 40),

          GestureDetector(
            onTap: _loading ? null : _createWallet,
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: DelightColors.emeraldGradient),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [BoxShadow(
                  color: DelightColors.emerald.withOpacity(0.4),
                  blurRadius: 20, offset: const Offset(0, 6),
                )],
              ),
              alignment: Alignment.center,
              child: _loading
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(
                    color: DelightColors.textInverse, strokeWidth: 2.5))
                : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.account_balance_wallet, color: DelightColors.textInverse, size: 20),
                    SizedBox(width: 10),
                    Text('Generate My Wallet', style: TextStyle(
                      fontFamily: 'Satoshi', fontSize: 17, fontWeight: FontWeight.w700,
                      color: DelightColors.textInverse,
                    )),
                  ]),
            ),
          ),
        ],
      );
    }

    // Wallet created — show seed phrase backup
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: DelightColors.emeraldGlow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: DelightColors.emerald.withOpacity(0.4)),
          ),
          child: const Row(children: [
            Icon(Icons.check_circle, color: DelightColors.emerald, size: 22),
            SizedBox(width: 10),
            Expanded(child: Text('Wallet created successfully!', style: TextStyle(
              fontFamily: 'Satoshi', fontWeight: FontWeight.w600, color: DelightColors.emerald,
            ))),
          ]),
        ),
        const SizedBox(height: 24),

        const Text('⚠️ Back up your secret key', style: TextStyle(
          fontFamily: 'Clash', fontSize: 20, fontWeight: FontWeight.w700,
          color: DelightColors.gold,
        )),
        const SizedBox(height: 8),
        const Text(
          'Write this down and store it somewhere safe. Anyone with this key can access your wallet.',
          style: TextStyle(fontFamily: 'Satoshi', fontSize: 13, color: DelightColors.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 16),

        // Seed display
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: _newSeed ?? ''));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Copied to clipboard')));
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: DelightColors.surfaceHigh,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: DelightColors.surfaceBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Secret Key', style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 11, fontWeight: FontWeight.w600,
                  color: DelightColors.textMuted, letterSpacing: 0.8,
                )),
                const SizedBox(height: 8),
                Text(_newSeed ?? '', style: const TextStyle(
                  fontFamily: 'Courier', fontSize: 13, color: DelightColors.gold,
                  letterSpacing: 0.5,
                )),
                const SizedBox(height: 8),
                Row(children: const [
                  Icon(Icons.copy, size: 14, color: DelightColors.textMuted),
                  SizedBox(width: 4),
                  Text('Tap to copy', style: TextStyle(
                    fontFamily: 'Satoshi', fontSize: 12, color: DelightColors.textMuted,
                  )),
                ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Address
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: DelightColors.surfaceHigh,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: DelightColors.surfaceBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Wallet Address', style: TextStyle(
                fontFamily: 'Satoshi', fontSize: 11, fontWeight: FontWeight.w600,
                color: DelightColors.textMuted, letterSpacing: 0.8,
              )),
              const SizedBox(height: 6),
              Text(_newAddress ?? '', style: const TextStyle(
                fontFamily: 'Courier', fontSize: 12, color: DelightColors.textSecondary,
              )),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Confirm backup checkbox
        GestureDetector(
          onTap: () => setState(() => _confirmedBackup = !_confirmedBackup),
          child: Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22, height: 22,
              decoration: BoxDecoration(
                color: _confirmedBackup ? DelightColors.emerald : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _confirmedBackup ? DelightColors.emerald : DelightColors.surfaceBorder,
                  width: 1.5,
                ),
              ),
              child: _confirmedBackup ? const Icon(Icons.check, size: 14, color: DelightColors.textInverse) : null,
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('I have safely backed up my secret key', style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 14, color: DelightColors.textPrimary,
            ))),
          ]),
        ),
        const SizedBox(height: 28),

        GestureDetector(
          onTap: _confirmedBackup ? _confirmAndProceed : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 60,
            decoration: BoxDecoration(
              gradient: _confirmedBackup
                ? const LinearGradient(colors: DelightColors.emeraldGradient)
                : null,
              color: _confirmedBackup ? null : DelightColors.surfaceHigh,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _confirmedBackup ? Colors.transparent : DelightColors.surfaceBorder),
            ),
            alignment: Alignment.center,
            child: Text('Continue to Delight →', style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 17, fontWeight: FontWeight.w700,
              color: _confirmedBackup ? DelightColors.textInverse : DelightColors.textMuted,
            )),
          ),
        ),
      ],
    );
  }

  Widget _buildImportFlow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Import Existing Wallet', style: TextStyle(
          fontFamily: 'Clash', fontSize: 26, fontWeight: FontWeight.w700,
          color: DelightColors.textPrimary,
        )),
        const SizedBox(height: 8),
        const Text('Enter your DC wallet address and secret key to connect your existing wallet.',
          style: TextStyle(fontFamily: 'Satoshi', fontSize: 14, color: DelightColors.textSecondary, height: 1.6)),
        const SizedBox(height: 32),

        TextFormField(
          controller: _importAddressCtrl,
          style: const TextStyle(fontFamily: 'Satoshi', color: DelightColors.textPrimary, fontSize: 14),
          decoration: const InputDecoration(
            labelText: 'XRP Wallet Address',
            hintText: 'rXXXX...',
            prefixIcon: Icon(Icons.account_balance_wallet_outlined, color: DelightColors.textMuted, size: 20),
          ),
        ),
        const SizedBox(height: 14),

        TextFormField(
          controller: _importSeedCtrl,
          obscureText: true,
          style: const TextStyle(fontFamily: 'Satoshi', color: DelightColors.textPrimary, fontSize: 14),
          decoration: const InputDecoration(
            labelText: 'Secret Key',
            hintText: 'sXXXX...',
            prefixIcon: Icon(Icons.key_outlined, color: DelightColors.textMuted, size: 20),
          ),
        ),
        const SizedBox(height: 32),

        GestureDetector(
          onTap: _importing ? null : _importWallet,
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: DelightColors.goldGradient),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(
                color: DelightColors.gold.withOpacity(0.3),
                blurRadius: 16, offset: const Offset(0, 5),
              )],
            ),
            alignment: Alignment.center,
            child: const Text('Import Wallet', style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 17, fontWeight: FontWeight.w700,
              color: DelightColors.textInverse,
            )),
          ),
        ),
      ],
    );
  }
}
