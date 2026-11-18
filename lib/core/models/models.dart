// ─── Delight Core Models ──────────────────────────────────────────────────

enum UserRole { consumer, business, organizer, admin }

class UserModel {
  final String id;
  final String username;
  final String displayName;
  final String email;
  final String? phone;
  final UserRole role;
  final String? avatarUrl;
  final String? bio;
  final int followersCount;
  final int followingCount;
  final DateTime createdAt;

  const UserModel({
    required this.id,
    required this.username,
    required this.displayName,
    required this.email,
    this.phone,
    this.role = UserRole.consumer,
    this.avatarUrl,
    this.bio,
    this.followersCount = 0,
    this.followingCount = 0,
    required this.createdAt,
  });

  UserModel copyWith({
    String? displayName,
    String? bio,
    String? avatarUrl,
    String? phone,
    UserRole? role,
    int? followersCount,
    int? followingCount,
  }) => UserModel(
    id: id,
    username: username,
    displayName: displayName ?? this.displayName,
    email: email,
    phone: phone ?? this.phone,
    role: role ?? this.role,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    bio: bio ?? this.bio,
    followersCount: followersCount ?? this.followersCount,
    followingCount: followingCount ?? this.followingCount,
    createdAt: createdAt,
  );
}

// ─── Wallet ───────────────────────────────────────────────────────────────

class WalletModel {
  final String address;
  final String? encryptedSeed;
  final double balanceXRP;
  final double balanceUSD;
  final bool isImported;

  const WalletModel({
    required this.address,
    this.encryptedSeed,
    this.balanceXRP = 0,
    this.balanceUSD = 0,
    this.isImported = false,
  });

  WalletModel copyWith({double? balanceXRP, double? balanceUSD}) => WalletModel(
    address: address,
    encryptedSeed: encryptedSeed,
    balanceXRP: balanceXRP ?? this.balanceXRP,
    balanceUSD: balanceUSD ?? this.balanceUSD,
    isImported: isImported,
  );
}

// ─── Transaction ──────────────────────────────────────────────────────────

enum TransactionType { send, receive, ticketPurchase, ticketSale, eventSpend }

enum TransactionStatus { pending, confirmed, failed }

class TransactionModel {
  final String id;
  final TransactionType type;
  final String fromAddress;
  final String toAddress;
  final double amountXRP;
  final double amountUSD;
  final double feeXRP;
  final String? memo;
  final TransactionStatus status;
  final DateTime timestamp;
  final String? txHash;

  const TransactionModel({
    required this.id,
    required this.type,
    required this.fromAddress,
    required this.toAddress,
    required this.amountXRP,
    required this.amountUSD,
    required this.feeXRP,
    this.memo,
    this.status = TransactionStatus.confirmed,
    required this.timestamp,
    this.txHash,
  });
}

// ─── NFT Ticket ───────────────────────────────────────────────────────────

class NFTTicket {
  final String id;
  final String eventId;
  final String eventName;
  final DateTime eventDate;
  final String eventVenue;
  final String eventCity;
  final String? eventImageUrl;
  final String tokenId;
  final String ownerAddress;
  final double priceXRP;
  final String tier;
  final String? seatInfo;
  final bool isUsed;
  final bool isForSale;
  final double? resalePriceXRP;
  final DateTime mintedAt;

  const NFTTicket({
    required this.id,
    required this.eventId,
    required this.eventName,
    required this.eventDate,
    required this.eventVenue,
    required this.eventCity,
    this.eventImageUrl,
    required this.tokenId,
    required this.ownerAddress,
    required this.priceXRP,
    required this.tier,
    this.seatInfo,
    this.isUsed = false,
    this.isForSale = false,
    this.resalePriceXRP,
    required this.mintedAt,
  });

  NFTTicket copyWith({bool? isUsed, bool? isForSale, double? resalePriceXRP}) => NFTTicket(
    id: id, eventId: eventId, eventName: eventName, eventDate: eventDate,
    eventVenue: eventVenue, eventCity: eventCity, eventImageUrl: eventImageUrl,
    tokenId: tokenId, ownerAddress: ownerAddress, priceXRP: priceXRP,
    tier: tier, seatInfo: seatInfo,
    isUsed: isUsed ?? this.isUsed,
    isForSale: isForSale ?? this.isForSale,
    resalePriceXRP: resalePriceXRP ?? this.resalePriceXRP,
    mintedAt: mintedAt,
  );
}

// ─── Event ────────────────────────────────────────────────────────────────

class TicketTier {
  final String id;
  final String name;
  final double priceXRP;
  final int totalTickets;
  final int soldTickets;
  final List<String> perks;

  const TicketTier({
    required this.id,
    required this.name,
    required this.priceXRP,
    required this.totalTickets,
    this.soldTickets = 0,
    this.perks = const [],
  });

  int get available => totalTickets - soldTickets;
  double get soldPercentage => totalTickets > 0 ? soldTickets / totalTickets : 0;
}

class EventModel {
  final String id;
  final String organizerId;
  final String organizerName;
  final String title;
  final String description;
  final String? coverImageUrl;
  final String venue;
  final String city;
  final String country;
  final DateTime date;
  final DateTime? endDate;
  final String category;
  final List<TicketTier> ticketTiers;
  final bool isPublished;

  const EventModel({
    required this.id,
    required this.organizerId,
    required this.organizerName,
    required this.title,
    required this.description,
    this.coverImageUrl,
    required this.venue,
    required this.city,
    required this.country,
    required this.date,
    this.endDate,
    required this.category,
    required this.ticketTiers,
    this.isPublished = true,
  });

  int get totalTickets => ticketTiers.fold(0, (s, t) => s + t.totalTickets);
  int get soldTickets => ticketTiers.fold(0, (s, t) => s + t.soldTickets);
  double get lowestPrice => ticketTiers.isEmpty ? 0 : ticketTiers.map((t) => t.priceXRP).reduce((a, b) => a < b ? a : b);
  bool get isSoldOut => totalTickets > 0 && soldTickets >= totalTickets;
}

// ─── Social Post ──────────────────────────────────────────────────────────

class SocialPost {
  final String id;
  final String userId;
  final String userDisplayName;
  final String? userAvatarUrl;
  final String? eventId;
  final String? eventName;
  final String content;
  final List<String> imageUrls;
  final String? nftTokenId;

  // NFT Memory fields — set when post is a verified on-chain memory
  final bool isNftMemory;           // true = minted from attended ticket
  final String? memoryTokenId;      // the new Memory NFT token ID
  final String? attendedEventName;  // the event they attended
  final String? attendedEventVenue; // venue
  final String? attendedTier;       // VIP / General / Table
  final String? attendedTicketId;   // original ticket that proves attendance
  final DateTime? eventDate;        // when the event happened
  final bool hasVideo;              // video attached to memory
  final String? memoryStyle;        // visual style: 'Electric' 'Midnight' 'Gold' 'Neon'

  int likesCount;
  int commentsCount;
  bool isLiked;
  final DateTime timestamp;

  SocialPost({
    required this.id,
    required this.userId,
    required this.userDisplayName,
    this.userAvatarUrl,
    this.eventId,
    this.eventName,
    required this.content,
    this.imageUrls = const [],
    this.nftTokenId,
    this.isNftMemory = false,
    this.memoryTokenId,
    this.attendedEventName,
    this.attendedEventVenue,
    this.attendedTier,
    this.attendedTicketId,
    this.eventDate,
    this.hasVideo = false,
    this.memoryStyle,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.isLiked = false,
    required this.timestamp,
  });
}

// ─── Seed Data ────────────────────────────────────────────────────────────

