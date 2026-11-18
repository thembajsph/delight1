import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/models/models.dart';
import '../../../../core/services/xrpl_service.dart';
import '../../../../core/services/valr_service.dart';

String _txLabel(dynamic type) {
  final s = type.toString().toLowerCase();
  if (s.contains('send'))    return 'Sent';
  if (s.contains('receive')) return 'Received';
  if (s.contains('ticket'))  return 'Ticket';
  if (s.contains('topup'))   return 'Top Up';
  return 'Transfer';
}


class PaymentsScreen extends ConsumerWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(walletProvider);
    final txns   = ref.watch(transactionsProvider);
    // Same shared live ZAR rate the Wallet page uses — never diverges again.
    ValrService.getXrpPriceZAR(); // background refresh, non-blocking
    final zarRate = ValrService.cachedRateZAR;
    final zarBalance = (wallet?.balanceXRP ?? 0) * zarRate;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: DelightColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                const Text('Payments', style: TextStyle(
                  fontFamily: 'Clash', fontSize: 28, fontWeight: FontWeight.w700,
                  color: DelightColors.textPrimary)),
                const SizedBox(height: 20),

                // ── Balance card — ZAR is the HERO ──────────────────────
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0D2A1A), Color(0xFF0A1F14)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: DelightColors.emerald.withOpacity(0.25)),
                    boxShadow: [BoxShadow(
                      color: DelightColors.emerald.withOpacity(0.1),
                      blurRadius: 24, offset: const Offset(0, 8))],
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('YOUR BALANCE', style: TextStyle(
                      fontFamily: 'Satoshi', fontSize: 11,
                      color: DelightColors.textMuted,
                      letterSpacing: 1.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),

                    // ZAR — BIG
                    Text(
                      DelightCurrency.formatZAR(zarBalance),
                      style: const TextStyle(
                        fontFamily: 'Clash', fontSize: 48,
                        fontWeight: FontWeight.w700,
                        color: DelightColors.textPrimary,
                        letterSpacing: -1, height: 1.0)),

                    const SizedBox(height: 6),

                    // "Available to spend" — no jargon
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: DelightColors.emeraldGlow,
                          borderRadius: BorderRadius.circular(6)),
                        child: const Text(
                          '✓ Ready to spend',
                          style: TextStyle(
                            fontFamily: 'Satoshi', fontSize: 12,
                            color: DelightColors.emerald,
                            fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      Text(DelightCurrency.exchangeRate(),
                        style: const TextStyle(
                          fontFamily: 'Satoshi', fontSize: 11,
                          color: DelightColors.textMuted)),
                    ]),
                  ]),
                ),
                const SizedBox(height: 16),

                // ── Add Money + Cash Out ──────────────────────────────────
                Row(children: [
                  Expanded(child: _bigBtn(context,
                    Icons.add_circle_outline, 'Add Money',
                    DelightColors.emerald, () => context.push('/topup'))),
                  const SizedBox(width: 12),
                  Expanded(child: _bigBtn(context,
                    Icons.download_outlined, 'Cash Out',
                    DelightColors.gold, () => context.push('/cashout'))),
                ]),
                const SizedBox(height: 12),

                // ── Send / Receive / Scan / Tickets ─────────────────
                Row(children: [
                  Expanded(child: _actionTile(context,
                    Icons.north_east, 'Send',
                    DelightColors.emerald, () => context.push('/send'))),
                  const SizedBox(width: 10),
                  Expanded(child: _actionTile(context,
                    Icons.south_west, 'Receive',
                    DelightColors.gold, () => context.push('/receive'))),
                  const SizedBox(width: 10),
                  Expanded(child: _actionTile(context,
                    Icons.qr_code_scanner, 'Scan',
                    DelightColors.info, () async {
                      final scanned = await context.push<String>('/scan');
                      if (scanned != null && scanned.isNotEmpty && context.mounted) {
                        context.push('/send', extra: scanned);
                      }
                    })),
                  const SizedBox(width: 10),
                  Expanded(child: _actionTile(context,
                    Icons.confirmation_number_outlined, 'Tickets',
                    const Color(0xFFBF5FFF), () => context.push('/events'))),
                ]),
                const SizedBox(height: 24),

                // ── Fee schedule — in ZAR terms ───────────────────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: DelightColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: DelightColors.surfaceBorder)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    const Text('TRANSACTION FEES', style: TextStyle(
                      fontFamily: 'Satoshi', fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: DelightColors.textMuted, letterSpacing: 1.2)),
                    const SizedBox(height: 10),
                    ...[
                      ('Send to a friend',     '0.5%', DelightColors.emerald),
                      ('Pay a business',       '1.0%', DelightColors.gold),
                      ('Business to business', '1.0%', DelightColors.gold),
                      ('Buy event ticket',     '3.0%', DelightColors.info),
                      ('Cash out to bank',     '2.1%', DelightColors.textMuted),
                    ].map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Row(children: [
                        Expanded(child: Text(f.$1, style: const TextStyle(
                          fontFamily: 'Satoshi', fontSize: 13,
                          color: DelightColors.textSecondary))),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: f.$3.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6)),
                          child: Text(f.$2, style: TextStyle(
                            fontFamily: 'Satoshi', fontSize: 12,
                            fontWeight: FontWeight.w700, color: f.$3))),
                      ])))
                  ]),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: DelightColors.emeraldGlow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: DelightColors.emerald.withOpacity(0.3))),
                  child: const Row(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Text('⚡', style: TextStyle(fontSize: 14)),
                    SizedBox(width: 8),
                    Expanded(child: Text(
                      'Internal ledger — P2P, business, and ticket payments '
                      'never touch an exchange. No conversion. No network fees. '
                      'Only cash out when you need ZAR.',
                      style: TextStyle(fontFamily: 'Satoshi', fontSize: 11,
                        color: DelightColors.emerald, height: 1.5))),
                  ])),
                const SizedBox(height: 24),

                const Text('Recent', style: TextStyle(
                  fontFamily: 'Clash', fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: DelightColors.textPrimary)),
              ]),
            )),

            // ── Transaction list ─────────────────────────────────────────
            if (txns.isEmpty)
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(children: const [
                  Text('💸', style: TextStyle(fontSize: 48)),
                  SizedBox(height: 12),
                  Text('No transactions yet', style: TextStyle(
                    fontFamily: 'Satoshi', fontSize: 16,
                    color: DelightColors.textSecondary)),
                  SizedBox(height: 4),
                  Text('Add money and make your first payment',
                    style: TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                      color: DelightColors.textMuted)),
                ]),
              ))
            else
              SliverList(delegate: SliverChildBuilderDelegate(
                (_, i) => _TxTile(tx: txns[i], zarRate: zarRate),
                childCount: txns.length)),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Widget _bigBtn(BuildContext ctx, IconData icon, String label,
      Color color, VoidCallback onTap) =>
    GestureDetector(onTap: onTap, child: Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25))),
      child: Column(children: [
        Icon(icon, color: color, size: 26),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontFamily: 'Satoshi', fontSize: 13,
          fontWeight: FontWeight.w700, color: color)),
      ]),
    ));

  Widget _actionTile(BuildContext ctx, IconData icon, String label,
      Color color, VoidCallback onTap) =>
    GestureDetector(onTap: onTap, child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.18))),
      child: Column(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 5),
        Text(label, style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
          fontWeight: FontWeight.w600, color: color)),
      ]),
    ));
}

// ── Transaction tile — ZAR primary, DC secondary ──────────────────────────────

class _TxTile extends StatelessWidget {
  final TransactionModel tx;
  final double zarRate;
  const _TxTile({required this.tx, required this.zarRate});

  @override
  Widget build(BuildContext context) {
    final isSend = tx.type == TransactionType.send ||
                   tx.type == TransactionType.ticketPurchase;
    final color  = isSend ? DelightColors.error : DelightColors.emerald;
    final sign   = isSend ? '−' : '+';
    final fmt    = DateFormat('MMM d · HH:mm');
    final zarAmt = tx.amountXRP * zarRate;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(
          color: DelightColors.surfaceBorder, width: 0.5))),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(
            isSend ? Icons.north_east : Icons.south_west,
            color: color, size: 18)),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_txLabel(tx.type), style: const TextStyle(
            fontFamily: 'Satoshi', fontWeight: FontWeight.w600,
            color: DelightColors.textPrimary, fontSize: 14)),
          Text(
            isSend
              ? 'To · ${XrplService.maskAddress(tx.toAddress)}'
              : 'From · ${XrplService.maskAddress(tx.fromAddress)}',
            style: const TextStyle(fontFamily: 'Satoshi',
              fontSize: 12, color: DelightColors.textMuted)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          // ZAR — big
          Text('$sign${DelightCurrency.formatZAR(zarAmt)}',
            style: TextStyle(fontFamily: 'Clash', fontSize: 16,
              fontWeight: FontWeight.w700, color: color)),
          // DC — small
          Text('$sign${DelightCurrency.dcAmount(tx.amountXRP)}',
            style: const TextStyle(fontFamily: 'Satoshi',
              fontSize: 11, color: DelightColors.textMuted)),
          Text(fmt.format(tx.timestamp), style: const TextStyle(
            fontFamily: 'Satoshi', fontSize: 10,
            color: DelightColors.textMuted)),
        ]),
      ]),
    );
  }
}
