import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/models/models.dart';
import '../../../../core/services/xrpl_service.dart';
import '../../../../core/services/valr_service.dart';
import '../../../../core/services/supabase_service.dart';

String _txLabel(dynamic type) {
  final s = type.toString().toLowerCase();
  if (s.contains('send'))    return 'Sent';
  if (s.contains('receive')) return 'Received';
  if (s.contains('ticket'))  return 'Ticket';
  if (s.contains('topup'))   return 'Top Up';
  return 'Transfer';
}


class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});
  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  double _rate = ValrService.cachedRateZAR;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _loadRate();
  }
  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _loadRate() async {
    final price = await ValrService.getXrpPriceZAR();
    if (mounted) setState(() => _rate = price);
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletProvider);
    final tickets = ref.watch(ticketsProvider);
    final txns = ref.watch(transactionsProvider);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: DelightColors.background,
      body: SafeArea(
        child: Column(children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('My Wallet', style: TextStyle(
                fontFamily: 'Clash', fontSize: 28, fontWeight: FontWeight.w700,
                color: DelightColors.textPrimary)),
              const SizedBox(height: 16),

              // Balance card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0D2A1A), Color(0xFF0A1F14)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: DelightColors.emerald.withOpacity(0.25)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('YOUR BALANCE', style: TextStyle(
                    fontFamily: 'Satoshi', fontSize: 11, color: DelightColors.textMuted,
                    letterSpacing: 1.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  // ZAR — hero number
                  Text(
                    DelightCurrency.formatZAR((wallet?.balanceXRP ?? 0) * _rate),
                    style: const TextStyle(fontFamily: 'Clash', fontSize: 40,
                      fontWeight: FontWeight.w700,
                      color: DelightColors.textPrimary, letterSpacing: -1)),
                  const SizedBox(height: 4),
                  // DC — small secondary
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: DelightColors.emeraldGlow,
                      borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      DelightCurrency.dcAmount(wallet?.balanceXRP ?? 0),
                      style: const TextStyle(fontFamily: 'Satoshi',
                        fontSize: 12, color: DelightColors.emerald,
                        fontWeight: FontWeight.w600))),
                  const SizedBox(height: 14),
                  Row(children: [
                    _quickBtn(Icons.north_east, 'Send', DelightColors.emerald, () => context.push('/send')),
                    const SizedBox(width: 10),
                    _quickBtn(Icons.south_west, 'Receive', DelightColors.gold, () => context.push('/receive')),
                    const SizedBox(width: 10),
                    _quickBtn(Icons.qr_code_scanner, 'Scan', DelightColors.info, () async {
                      final scanned = await context.push<String>('/scan');
                      if (scanned != null && scanned.isNotEmpty && context.mounted) {
                        context.push('/send', extra: scanned);
                      }
                    }),
                  ]),
                ]),
              ),
              const SizedBox(height: 12),
              _XrpAddressCard(wallet: wallet),
              const SizedBox(height: 16),

              // Tabs
              Container(
                decoration: BoxDecoration(
                  color: DelightColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: DelightColors.surfaceBorder),
                ),
                child: TabBar(
                  controller: _tab,
                  indicator: BoxDecoration(
                    gradient: const LinearGradient(colors: DelightColors.emeraldGradient),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelStyle: const TextStyle(fontFamily: 'Satoshi', fontWeight: FontWeight.w700, fontSize: 13),
                  unselectedLabelColor: DelightColors.textMuted,
                  labelColor: DelightColors.textInverse,
                  padding: const EdgeInsets.all(3),
                  tabs: [
                    Tab(child: FittedBox(fit: BoxFit.scaleDown,
                      child: Text('My Tickets (${tickets.length})', maxLines: 1))),
                    const Tab(child: FittedBox(fit: BoxFit.scaleDown,
                      child: Text('Marketplace', maxLines: 1))),
                    Tab(child: FittedBox(fit: BoxFit.scaleDown,
                      child: Text('Transactions (${txns.length})', maxLines: 1))),
                  ],
                ),
              ),
            ]),
          ),

          // Tab views
          Expanded(
            child: TabBarView(controller: _tab, children: [
              // Tickets tab
              tickets.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                    const Text('🎟', style: TextStyle(fontSize: 52)),
                    const SizedBox(height: 14),
                    const Text('No NFT tickets yet', style: TextStyle(
                      fontFamily: 'Clash', fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: DelightColors.textPrimary)),
                    const SizedBox(height: 6),
                    const Text('Buy a ticket — it lives on the blockchain forever',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                        color: DelightColors.textMuted)),
                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: () => context.push('/events'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: DelightColors.goldGradient),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(
                            color: DelightColors.gold.withOpacity(0.35),
                            blurRadius: 16, offset: const Offset(0, 4))]),
                        child: const Row(mainAxisSize: MainAxisSize.min,
                          children: [
                          Text('🎵', style: TextStyle(fontSize: 18)),
                          SizedBox(width: 8),
                          Text('Browse Events', style: TextStyle(
                            fontFamily: 'Satoshi', fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.black)),
                        ]))),
                  ]))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: tickets.length,
                    itemBuilder: (_, i) => _TicketCard(ticket: tickets[i]),
                  ),

              // Marketplace tab — all tickets listed for sale
              _MarketplaceTab(),

              // Transactions tab
              txns.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: const [
                    Text('💸', style: TextStyle(fontSize: 52)),
                    SizedBox(height: 12),
                    Text('No transactions yet', style: TextStyle(
                      fontFamily: 'Satoshi', fontSize: 16, color: DelightColors.textSecondary)),
                  ]))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: txns.length,
                    itemBuilder: (_, i) => _TxRow(tx: txns[i]),
                  ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _quickBtn(IconData icon, String label, Color color, VoidCallback onTap) =>
    Expanded(child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(
            fontFamily: 'Satoshi', fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    ));
}

class _TicketCard extends StatelessWidget {
  final NFTTicket ticket;
  const _TicketCard({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('MMM d, yyyy');
    return GestureDetector(
      onTap: () => context.push('/ticket/${ticket.id}', extra: ticket),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: DelightColors.surfaceHigh,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: ticket.isUsed ? DelightColors.surfaceBorder : DelightColors.emerald.withOpacity(0.3)),
        ),
        child: Row(children: [
          // Color stripe
          Container(
            width: 6,
            height: 90,
            decoration: BoxDecoration(
              gradient: ticket.isUsed
                ? const LinearGradient(colors: [DelightColors.textMuted, DelightColors.surfaceBorder])
                : const LinearGradient(colors: DelightColors.emeraldGradient),
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(18)),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ticket.eventName, style: const TextStyle(
                  fontFamily: 'Clash', fontSize: 15, fontWeight: FontWeight.w700,
                  color: DelightColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text('${ticket.eventVenue} · ${ticket.eventCity}', maxLines: 1,
                  overflow: TextOverflow.ellipsis, style: const TextStyle(
                  fontFamily: 'Satoshi', fontSize: 12, color: DelightColors.textMuted)),
                Text(dateFmt.format(ticket.eventDate), style: const TextStyle(
                  fontFamily: 'Satoshi', fontSize: 12, color: DelightColors.textMuted)),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: DelightColors.goldGlow,
                      borderRadius: BorderRadius.circular(6)),
                    child: Text(ticket.tier, style: const TextStyle(
                      fontFamily: 'Satoshi', fontSize: 10,
                      fontWeight: FontWeight.w700, color: DelightColors.gold))),
                  const SizedBox(width: 6),
                  if (ticket.isUsed)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: DelightColors.surfaceBorder,
                        borderRadius: BorderRadius.circular(6)),
                      child: const Text('USED', style: TextStyle(
                        fontFamily: 'Satoshi', fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: DelightColors.textMuted))),
                  if (ticket.isForSale) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A1F00),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: DelightColors.gold.withOpacity(0.5))),
                      child: Text(
                        'FOR SALE · R${(ticket.resalePriceXRP ?? 0).toStringAsFixed(0)}',
                        style: const TextStyle(fontFamily: 'Satoshi',
                          fontSize: 10, fontWeight: FontWeight.w800,
                          color: DelightColors.gold))),
                  ],
                ])),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Column(children: [
              const Icon(Icons.qr_code_2, color: DelightColors.emerald, size: 32),
              const SizedBox(height: 4),
              Text(ticket.tokenId.substring(0, 8), style: const TextStyle(
                fontFamily: 'Courier', fontSize: 9, color: DelightColors.textMuted)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _TxRow extends StatelessWidget {
  final TransactionModel tx;
  const _TxRow({required this.tx});

  @override
  Widget build(BuildContext context) {
    final isSend = tx.type == TransactionType.send || tx.type == TransactionType.ticketPurchase;
    final color = isSend ? DelightColors.error : DelightColors.emerald;
    final fmt = DateFormat('MMM d · HH:mm');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: DelightColors.surfaceBorder, width: 0.5))),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(isSend ? Icons.north_east : Icons.south_west, color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_txLabel(tx.type), style: const TextStyle(
            fontFamily: 'Satoshi', fontWeight: FontWeight.w600,
            color: DelightColors.textPrimary, fontSize: 14)),
          Text(fmt.format(tx.timestamp), style: const TextStyle(
            fontFamily: 'Satoshi', fontSize: 11, color: DelightColors.textMuted)),
        ])),
        Text('${isSend ? '−' : '+'}${DelightCurrency.formatZAR(tx.amountXRP * ValrService.cachedRateZAR)}',
          style: TextStyle(fontFamily: 'Satoshi', fontWeight: FontWeight.w700, color: color, fontSize: 13)),
      ]),
    );
  }
}

// ── XRP Testnet Address Card ─────────────────────────────────────────────────
// ── Add Money / Cash Out ─────────────────────────────────────────────────────
// Custodial model: Delight holds the actual XRPL wallet server-side, so
// consumers never see an address, a seed phrase, or a block explorer link —
// just their ZAR balance and a normal bank-transfer in/out flow.
class _XrpAddressCard extends StatelessWidget {
  final dynamic wallet;
  const _XrpAddressCard({required this.wallet});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: _BankActionButton(
        icon: Icons.add_circle_outline,
        label: 'Add Money',
        color: DelightColors.emerald,
        onTap: () => context.push('/topup'),
      )),
      const SizedBox(width: 10),
      Expanded(child: _BankActionButton(
        icon: Icons.account_balance_outlined,
        label: 'Cash Out',
        color: DelightColors.gold,
        onTap: () => context.push('/cashout'),
      )),
    ]);
  }
}

class _BankActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _BankActionButton({
    required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.3))),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 13, fontWeight: FontWeight.w700,
              color: color)),
          ]),
        ),
      ),
    );
  }
}

// ── Marketplace Tab ────────────────────────────────────────────────────────────
// Real cross-user resale listings — queries Supabase for every ticket where
// is_for_sale = true (RLS explicitly allows reading any user's listed
// tickets, see the `tickets_for_sale` policy). The local ticketsProvider
// only ever holds the signed-in user's own tickets, so it can't be used
// here — that was the earlier bug: the marketplace could only ever show
// your own listings back to you.
class _MarketplaceTab extends ConsumerStatefulWidget {
  const _MarketplaceTab();
  @override
  ConsumerState<_MarketplaceTab> createState() => _MarketplaceTabState();
}

class _MarketplaceTabState extends ConsumerState<_MarketplaceTab> {
  List<NFTTicket> _listings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final rows = await SupabaseService.getTicketsForSale();
    final myId = ref.read(authProvider)?.id;
    final listings = rows
      .where((r) => r['user_id'] != myId) // can't buy your own listing
      .map((r) {
        final ev = r['events'] as Map<String, dynamic>? ?? {};
        return NFTTicket(
          id:            r['id'] as String,
          eventId:       r['event_id'] as String,
          eventName:     ev['name'] as String? ?? 'Event',
          eventDate:     DateTime.tryParse(ev['event_date'] as String? ?? '')
                          ?? DateTime.now(),
          eventVenue:    ev['venue'] as String? ?? '',
          eventCity:     ev['city']  as String? ?? '',
          eventImageUrl: ev['image_url'] as String?,
          tokenId:       r['token_id'] as String? ?? '',
          ownerAddress:  r['owner_address'] as String? ?? '',
          priceXRP:      (r['price_zar'] as num? ?? 0).toDouble() / 9.5,
          tier:          r['tier'] as String? ?? 'General',
          isUsed:        r['is_used'] as bool? ?? false,
          isForSale:     r['is_for_sale'] as bool? ?? false,
          resalePriceXRP: (r['resale_price_zar'] as num?)?.toDouble(),
          mintedAt:      DateTime.tryParse(r['minted_at'] as String? ?? '')
                          ?? DateTime.now(),
        );
      }).toList();
    if (mounted) setState(() { _listings = listings; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: DelightColors.emerald));
    }

    if (_listings.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 60),
              const Text('🏷', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 14),
              const Text('No tickets for sale yet',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Clash', fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: DelightColors.textPrimary)),
              const SizedBox(height: 6),
              const Text('When someone lists a ticket, it appears here.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                  color: DelightColors.textMuted)),
              const SizedBox(height: 12),
              const Text('List your own ticket: tap it then choose List for Resale',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                  color: DelightColors.textMuted, height: 1.5)),
            ])));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _listings.length,
        itemBuilder: (_, i) => _MarketplaceCard(
          ticket: _listings[i], onBought: _load),
      ));
  }
}

class _MarketplaceCard extends ConsumerWidget {
  final NFTTicket ticket;
  final VoidCallback onBought;
  const _MarketplaceCard({required this.ticket, required this.onBought});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFmt = DateFormat('MMM d, yyyy');
    final price    = ticket.resalePriceXRP ?? 0;   // stored as ZAR
    final youPay   = price;                         // buyer pays full price
    final feeEarned = price * 0.03;                 // Delight earns 3%

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: DelightColors.surfaceHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DelightColors.gold.withOpacity(0.35))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Ticket info
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ticket.eventName,
                style: const TextStyle(fontFamily: 'Clash', fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: DelightColors.textPrimary)),
              const SizedBox(height: 2),
              Text('${ticket.eventVenue} · ${ticket.eventCity}',
                style: const TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                  color: DelightColors.textMuted)),
              Text(dateFmt.format(ticket.eventDate),
                style: const TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                  color: DelightColors.textMuted)),
              const SizedBox(height: 6),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: DelightColors.goldGlow,
                    borderRadius: BorderRadius.circular(6)),
                  child: Text(ticket.tier, style: const TextStyle(
                    fontFamily: 'Satoshi', fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: DelightColors.gold))),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: DelightColors.emeraldGlow,
                    borderRadius: BorderRadius.circular(6)),
                  child: const Row(mainAxisSize: MainAxisSize.min,
                    children: [
                    Icon(Icons.diamond_outlined,
                      size: 9, color: DelightColors.emerald),
                    SizedBox(width: 3),
                    Text('NFT Verified', style: TextStyle(
                      fontFamily: 'Satoshi', fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: DelightColors.emerald)),
                  ])),
              ]),
            ])),
            // Price
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(DelightCurrency.formatZAR(youPay),
                style: const TextStyle(fontFamily: 'Clash', fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: DelightColors.gold)),
              const Text('listed price', style: TextStyle(
                fontFamily: 'Satoshi', fontSize: 10,
                color: DelightColors.textMuted)),
            ]),
          ])),

        // Buy button
        Padding(
          padding: const EdgeInsets.all(14),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _buyTicket(context, ref),
              child: Container(
                height: 50, width: double.infinity,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: DelightColors.goldGradient),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(
                    color: DelightColors.gold.withOpacity(0.3),
                    blurRadius: 12, offset: const Offset(0, 4))]),
                alignment: Alignment.center,
                child: Text(
                  'Buy for ${DelightCurrency.formatZAR(youPay)}',
                  style: const TextStyle(fontFamily: 'Satoshi',
                    fontSize: 15, fontWeight: FontWeight.w800,
                    color: Colors.black))))),
        ),
      ]));
  }

  Future<void> _buyTicket(BuildContext context, WidgetRef ref) async {
    final wallet = ref.read(walletProvider);
    final price  = ticket.resalePriceXRP ?? 0;
    final dcCost = price / 9.5;

    if (wallet == null || wallet.balanceXRP < dcCost) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Not enough balance — add money first')));
      return;
    }

    try {
      // Real atomic transfer: moves the ZAR ledger balance between buyer
      // and seller and flips ticket ownership, all server-side (RLS
      // otherwise blocks a buyer's own session from touching someone
      // else's ticket or wallet row).
      await SupabaseService.buyResaleTicket(ticket.id);
      // Refresh the buyer's own ticket list and wallet balance from Supabase
      // — don't fabricate a local copy of the purchased ticket.
      final user = ref.read(authProvider);
      if (user != null) {
        ref.read(ticketsProvider.notifier).loadFromDB(user.id);
        ref.read(walletProvider.notifier).autoInit(user.id, user.email);
      }
      onBought();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Ticket purchased! Check My Tickets. '
            '${DelightCurrency.formatZAR(price)} paid.'),
          backgroundColor: DelightColors.emerald));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not complete purchase — it may have just sold.')));
      }
      onBought(); // refresh the list either way
    }
  }
}
