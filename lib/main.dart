import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

const String darvasTaskKey = "com.darvaspro.backgroundScanTask";

// Nifty 200 प्रमुख NSE स्टॉक्स की सूची (200 Stocks)
final List<String> defaultNifty200Stocks = [
  "RELIANCE", "TCS", "HDFCBANK", "ICICIBANK", "BHARTIARTL", "SBIN", "INFY",
  "LICI", "ITC", "HINDUNILVR", "LT", "BAJFINANCE", "HCLTECH", "MARUTI",
  "SUNPHARMA", "ADANIENT", "KOTAKBANK", "TITAN", "ONGC", "TATAMOTORS",
  "NTPC", "AXISBANK", "ADANIPORTS", "ULTRACEMCO", "M&M", "BAJAJFINSV",
  "ASIANPAINT", "COALINDIA", "POWERGRID", "WIPRO", "HAL", "DLF", "DMART",
  "SIEMENS", "TRENT", "BEL", "JSWSTEEL", "TATASTEEL", "VBL", "IOC",
  "IRFC", "ZOMATO", "JIOFIN", "GRASIM", "INDIGO", "TECHM", "HINDALCO",
  "PFC", "RECLTD", "ADANIPOWER", "ADANIGREEN", "PIDILITIND", "SBILIFE",
  "HDFCLIFE", "BAJAJ-AUTO", "CIPLA", "DIVISLAB", "DRREDDY", "EICHERMOT",
  "BPCL", "GAIL", "TATAPOWER", "ABB", "CHOLAFIN", "BANKBARODA", "PNB",
  "CANBK", "UNIONBANK", "IOB", "IDBI", "HAVELLS", "DABUR", "GODREJCP",
  "MARICO", "BRITANNIA", "NESTLEIND", "TATACONSUM", "COLPAL", "UNITDSPR",
  "MCDOWELL-N", "BERGEPAINT", "HEROMOTOCO", "TVSMOTOR", "BHARATFORG",
  "ASHOKLEY", "MOTHERSON", "BALKRISIND", "MRF", "APOLLOTYRE", "BOSCHLTD",
  "CUMMINSIND", "BHEL", "CGPOWER", "SUZLON", "NHPC", "SJVN", "TORNTPOWER",
  "JSWENERGY", "TATACHEM", "SRF", "PIIND", "UPL", "DEEPAKNTR", "NAVINFLUOR",
  "AARTIIND", "FLUOROCHEM", "ATUL", "COROMANDEL", "CHAMBLFERT", "GNFC",
  "INDHOTEL", "IRCTC", "CONCOR", "RVNL", "MAZDOCK", "COCHINSHIP", "BDL",
  "SOLARINDS", "ASTRAL", "POLYCAB", "KEI", "DIXON", "VOLTAS", "BLUESTARCO",
  "WHIRLPOOL", "CROMPTON", "BATAINDIA", "PAGEIND", "ABFRL", "MANYAVAR",
  "KALYANKJIL", "TITAGARH", "JINDALSTEL", "SAIL", "NMDC", "VEDL", "HINDZINC",
  "NATIONALUM", "APLAPOLLO", "RATNAMANI", "PERSISTENT", "COFORGE", "MPHASIS",
  "LTTS", "LTIM", "KPITTECH", "TATAELXSI", "OFSS", "CYIENT", "ZENSARTECH",
  "NAUKRI", "POLICYBZR", "PAYTM", "DELHIVERY", "NYKAA", "APOLLOHOSP",
  "MAXHEALTH", "FORTIS", "SYNGENE", "BIOCON", "LUPIN", "AUROPHARMA",
  "TORNTPHARM", "ALKEM", "GLENMARK", "IPCALAB", "LAURUSLABS", "GRANULES",
  "ZYDUSLIFE", "MANKIND", "ABBOTINDIA", "SANOFI", "PFIZER", "GLAXO",
  "SHRIRAMFIN", "MUTHOOTFIN", "MANAPPURAM", "BAJAJHLDNG", "SBICARD",
  "ICICIGI", "ICICIPRULI", "NIACL", "GICRE", "HDFCAMC", "NAM-INDIA",
  "CDSL", "BSE", "MCX", "CAMS", "ANGELONE", "IEX", "FEDERALBNK", "IDFCFIRSTB",
  "INDUSINDBK", "AUBANK", "BANDHANBNK", "RBLBANK", "KARURVYSYA", "CUB",
  "OBEROIRLTY", "GODREJPROP", "PRESTIGE", "BRIGADE", "PHOENIXLTD"
];

bool checkIsMarketOpenNow() {
  final now = DateTime.now();
  if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
    return false;
  }
  final currentMinutes = now.hour * 60 + now.minute;
  return currentMinutes >= (9 * 60) && currentMinutes <= (15 * 60 + 30);
}

Future<void> triggerNotification(String title, String body) async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'darvas_channel_id',
    'Darvas Alerts',
    channelDescription: 'Real-time High Accuracy Darvas Signals',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
  );
  const NotificationDetails notificationDetails =
      NotificationDetails(android: androidDetails);
  await flutterLocalNotificationsPlugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    notificationDetails,
  );
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    const AndroidInitializationSettings initAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings =
        InitializationSettings(android: initAndroid);
    await flutterLocalNotificationsPlugin.initialize(initSettings);

    if (!checkIsMarketOpenNow()) {
      return Future.value(true);
    }

    final prefs = await SharedPreferences.getInstance();
    final List<String> watchlist =
        prefs.getStringList('custom_watchlist') ?? defaultNifty200Stocks;
    final double volMultiplierReq = prefs.getDouble('vol_multiplier') ?? 1.30;
    final double max52wDist = prefs.getDouble('max_52w_dist') ?? 15.0;

    // बैकग्राउंड में टॉप 40 स्टॉक्स का त्वरित स्कैन
    final scanSubset = watchlist.take(40).toList();

    for (String symbol in scanSubset) {
      try {
        final url = Uri.parse(
            'https://query1.finance.yahoo.com/v8/finance/chart/$symbol.NS?interval=1d&range=1y');
        final response = await http.get(url, headers: {
          'User-Agent':
              'Mozilla/5.0 (Android; Mobile; rv:109.0) Gecko/109.0 Firefox/119.0'
        }).timeout(const Duration(seconds: 6));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final quote = data['chart']['result'][0]['indicators']['quote'][0];

          List<double> closes = [];
          List<double> highs = [];
          List<double> lows = [];
          List<double> volumes = [];

          for (int i = 0; i < quote['close'].length; i++) {
            if (quote['close'][i] != null &&
                quote['high'][i] != null &&
                quote['low'][i] != null &&
                quote['volume'][i] != null) {
              closes.add(quote['close'][i].toDouble());
              highs.add(quote['high'][i].toDouble());
              lows.add(quote['low'][i].toDouble());
              volumes.add(quote['volume'][i].toDouble());
            }
          }

          if (closes.length >= 60) {
            double currentPrice = closes.last;
            double currentHigh = highs.last;
            double currentLow = lows.last;
            double currentVol = volumes.last;

            double high52w = highs.reduce((a, b) => a > b ? a : b);
            double distFrom52w = ((high52w - currentPrice) / high52w) * 100;
            bool isNear52wHigh = distFrom52w <= max52wDist;

            double avgVol20 = volumes
                    .sublist(volumes.length - 21, volumes.length - 1)
                    .reduce((a, b) => a + b) /
                20;
            double ema50 =
                closes.sublist(closes.length - 35).reduce((a, b) => a + b) / 35;

            double boxTop = highs
                .sublist(highs.length - 20, highs.length - 2)
                .reduce((a, b) => a > b ? a : b);
            double boxBottom = lows
                .sublist(lows.length - 20, lows.length - 2)
                .reduce((a, b) => a < b ? a : b);

            double candleRange = currentHigh - currentLow;
            double upperWick = currentHigh - currentPrice;
            bool isCleanBody =
                candleRange > 0 ? (upperWick / candleRange) <= 0.35 : true;

            if (currentPrice > boxTop &&
                isNear52wHigh &&
                currentPrice > ema50 &&
                currentVol >= (avgVol20 * volMultiplierReq) &&
                isCleanBody) {
              await triggerNotification(
                "🟢 BUY ALERT: $symbol @ ₹${currentPrice.toStringAsFixed(1)}",
                "डार्वस ब्रेकआउट! Entry: ₹$boxTop | SL: ₹$boxBottom",
              );
            } else if (currentPrice < boxBottom) {
              await triggerNotification(
                "🔴 EXIT ALERT: $symbol @ ₹${currentPrice.toStringAsFixed(1)}",
                "बॉक्स बॉटम टूटा! तुरंत बाहर निकलें।",
              );
            }
          }
        }
      } catch (_) {}
    }

    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const AndroidInitializationSettings initAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings =
      InitializationSettings(android: initAndroid);
  await flutterLocalNotificationsPlugin.initialize(initSettings);

  final androidImpl = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.requestNotificationsPermission();

  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: false,
  );

  await Workmanager().registerPeriodicTask(
    "darvas_bg_periodic_task",
    darvasTaskKey,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
  );

  runApp(const DarvasProApp());
}

class DarvasProApp extends StatefulWidget {
  const DarvasProApp({super.key});

  @override
  State<DarvasProApp> createState() => _DarvasProAppState();
}

class _DarvasProAppState extends State<DarvasProApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void _toggleTheme() {
    setState(() {
      if (_themeMode == ThemeMode.dark) {
        _themeMode = ThemeMode.light;
      } else if (_themeMode == ThemeMode.light) {
        _themeMode = ThemeMode.system;
      } else {
        _themeMode = ThemeMode.dark;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Darvas Pro Terminal',
      themeMode: _themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
        cardColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF0F172A),
          elevation: 1,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: Color(0xFF059669),
          unselectedItemColor: Colors.black54,
        ),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF059669),
          secondary: Color(0xFF0284C7),
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0E17),
        cardColor: const Color(0xFF141C2E),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF101726),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF101726),
          selectedItemColor: Color(0xFF00E676),
          unselectedItemColor: Colors.white54,
        ),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E676),
          secondary: Color(0xFF00B0FF),
        ),
      ),
      home: DarvasTerminalScreen(
        onToggleTheme: _toggleTheme,
        currentThemeMode: _themeMode,
      ),
    );
  }
}

class DarvasSignal {
  final String symbol;
  final String status;
  final double currentPrice;
  final double entryPrice;
  final double stopLoss;
  final double target1;
  final double addLevel;
  final double nextTarget;
  final int suggestedQty;
  final String reason;
  final double near52wPercent;
  final double volumeSurgeX;
  final String riskRewardRatio;

  DarvasSignal({
    required this.symbol,
    required this.status,
    required this.currentPrice,
    required this.entryPrice,
    required this.stopLoss,
    required this.target1,
    required this.addLevel,
    required this.nextTarget,
    required this.suggestedQty,
    required this.reason,
    required this.near52wPercent,
    required this.volumeSurgeX,
    required this.riskRewardRatio,
  });
}

class VirtualPosition {
  final String id;
  final String symbol;
  final double buyPrice;
  double currentPrice;
  double currentSL;
  final double targetPrice;
  int qty;
  final String buyTime;

  VirtualPosition({
    required this.id,
    required this.symbol,
    required this.buyPrice,
    required this.currentPrice,
    required this.currentSL,
    required this.targetPrice,
    required this.qty,
    required this.buyTime,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'symbol': symbol,
        'buyPrice': buyPrice,
        'currentPrice': currentPrice,
        'currentSL': currentSL,
        'targetPrice': targetPrice,
        'qty': qty,
        'buyTime': buyTime,
      };

  factory VirtualPosition.fromMap(Map<String, dynamic> map) => VirtualPosition(
        id: map['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
        symbol: map['symbol'],
        buyPrice: (map['buyPrice'] as num).toDouble(),
        currentPrice: (map['currentPrice'] as num).toDouble(),
        currentSL: (map['currentSL'] as num).toDouble(),
        targetPrice: (map['targetPrice'] as num?)?.toDouble() ?? 0.0,
        qty: map['qty'] as int,
        buyTime: map['buyTime'] ?? '',
      );
}

class TradeHistoryItem {
  final String id;
  final String symbol;
  final double buyPrice;
  final double sellPrice;
  final double targetPrice;
  final int qty;
  final double pnl;
  final String buyTime;
  final String sellTime;

  TradeHistoryItem({
    required this.id,
    required this.symbol,
    required this.buyPrice,
    required this.sellPrice,
    required this.targetPrice,
    required this.qty,
    required this.pnl,
    required this.buyTime,
    required this.sellTime,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'symbol': symbol,
        'buyPrice': buyPrice,
        'sellPrice': sellPrice,
        'targetPrice': targetPrice,
        'qty': qty,
        'pnl': pnl,
        'buyTime': buyTime,
        'sellTime': sellTime,
      };

  factory TradeHistoryItem.fromMap(Map<String, dynamic> map) =>
      TradeHistoryItem(
        id: map['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
        symbol: map['symbol'],
        buyPrice: (map['buyPrice'] as num).toDouble(),
        sellPrice: (map['sellPrice'] as num).toDouble(),
        targetPrice: (map['targetPrice'] as num?)?.toDouble() ?? 0.0,
        qty: map['qty'] as int,
        pnl: (map['pnl'] as num).toDouble(),
        buyTime: map['buyTime'] ?? '',
        sellTime: map['sellTime'] ?? '',
      );
}

class DarvasTerminalScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final ThemeMode currentThemeMode;

  const DarvasTerminalScreen({
    super.key,
    required this.onToggleTheme,
    required this.currentThemeMode,
  });

  @override
  State<DarvasTerminalScreen> createState() => _DarvasTerminalScreenState();
}

class _DarvasTerminalScreenState extends State<DarvasTerminalScreen> {
  int currentTabIndex = 0;

  // यूज़र प्रोफाइल व सेटिंग्स वेरिएबल्स
  String traderName = "Rituraj Patel";
  double initialCapital = 100000.0;
  double virtualCash = 100000.0;
  double riskPercentPerTrade = 1.0; // प्रति ट्रेड रिस्क %
  double volMultiplierReq = 1.30; // वॉल्यूम सर्ज गुणक
  double max52wDist = 15.0; // 52W हाई से दूरी %
  String defaultDematBroker = "Ask Every Time"; // डिफ़ॉल्ट ब्रोकर
  String lastBackupTimestamp = "अभी तक नहीं";

  List<String> watchlist = List.from(defaultNifty200Stocks);

  bool isScanning = false;
  int scannedCount = 0;
  String marketStatus = "मार्केट जाँचा जा रहा है...";
  List<DarvasSignal> signalList = [];
  List<VirtualPosition> activePositions = [];
  List<TradeHistoryItem> tradeHistory = [];

  final TextEditingController searchController = TextEditingController();
  String searchQuery = "";

  @override
  void initState() {
    super.initState();
    loadAllUserData();
    updateMarketStatusMessage();
    runFullDarvasScan();
  }

  Future<void> loadAllUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      traderName = prefs.getString('trader_name') ?? "Rituraj Patel";
      initialCapital = prefs.getDouble('initial_capital') ?? 100000.0;
      virtualCash = prefs.getDouble('virtual_cash') ?? 100000.0;
      riskPercentPerTrade = prefs.getDouble('risk_percent') ?? 1.0;
      volMultiplierReq = prefs.getDouble('vol_multiplier') ?? 1.30;
      max52wDist = prefs.getDouble('max_52w_dist') ?? 15.0;
      defaultDematBroker = prefs.getString('default_broker') ?? "Ask Every Time";
      lastBackupTimestamp =
          prefs.getString('last_backup_time') ?? "ऑटो-सिंक सक्रिय";

      final savedList = prefs.getStringList('custom_watchlist');
      if (savedList != null && savedList.isNotEmpty) {
        watchlist = savedList;
      }

      final activeStr = prefs.getString('active_positions');
      if (activeStr != null && activeStr.isNotEmpty) {
        final List decoded = json.decode(activeStr);
        activePositions =
            decoded.map((e) => VirtualPosition.fromMap(e)).toList();
      }

      final histStr = prefs.getString('trade_history');
      if (histStr != null && histStr.isNotEmpty) {
        final List decoded = json.decode(histStr);
        tradeHistory =
            decoded.map((e) => TradeHistoryItem.fromMap(e)).toList();
      }
    });
  }

  Future<void> saveAllUserDataAndAutoBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final formattedTime =
        "${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}";

    await prefs.setString('trader_name', traderName);
    await prefs.setDouble('initial_capital', initialCapital);
    await prefs.setDouble('virtual_cash', virtualCash);
    await prefs.setDouble('risk_percent', riskPercentPerTrade);
    await prefs.setDouble('vol_multiplier', volMultiplierReq);
    await prefs.setDouble('max_52w_dist', max52wDist);
    await prefs.setString('default_broker', defaultDematBroker);
    await prefs.setStringList('custom_watchlist', watchlist);
    await prefs.setString('last_backup_time', formattedTime);

    await prefs.setString('active_positions',
        json.encode(activePositions.map((e) => e.toMap()).toList()));
    await prefs.setString('trade_history',
        json.encode(tradeHistory.map((e) => e.toMap()).toList()));

    // ऑटो वॉल्ट बैकअप
    final autoBackupVault = {
      'traderName': traderName,
      'initialCapital': initialCapital,
      'virtualCash': virtualCash,
      'activePositions': activePositions.map((e) => e.toMap()).toList(),
      'tradeHistory': tradeHistory.map((e) => e.toMap()).toList(),
      'lastBackupTime': formattedTime,
    };
    await prefs.setString('auto_backup_vault', json.encode(autoBackupVault));

    setState(() {
      lastBackupTimestamp = formattedTime;
    });
  }

  void updateMarketStatusMessage() {
    final now = DateTime.now();
    final timeStr =
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    setState(() {
      if (checkIsMarketOpenNow()) {
        marketStatus = "🟢 बाजार चालू है (IST: $timeStr)";
      } else {
        marketStatus = "🔴 बाजार बंद है (IST: $timeStr)";
      }
    });
  }

  Future<void> openTradingView(String symbol) async {
    await Clipboard.setData(ClipboardData(text: symbol));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("📈 $symbol का चार्ट खोला जा रहा है (कॉपी किया गया)"),
        backgroundColor: const Color(0xFF00B0FF),
        duration: const Duration(seconds: 2),
      ),
    );

    final Uri tvAppUri = Uri.parse("tradingview://chart?symbol=NSE%3A$symbol");
    final Uri tvWebUri =
        Uri.parse("https://in.tradingview.com/chart/?symbol=NSE%3A$symbol");

    try {
      final launched =
          await launchUrl(tvAppUri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(tvWebUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      await launchUrl(tvWebUri, mode: LaunchMode.externalApplication);
    }
  }

  void launchDirectBroker(String symbol, String broker) {
    Clipboard.setData(ClipboardData(text: symbol));
    if (broker == "Dhan") {
      launchUrl(Uri.parse("https://tv.dhan.co/?symbol=$symbol"),
              mode: LaunchMode.externalApplication)
          .catchError((_) => launchUrl(Uri.parse("dhan://trade/$symbol")));
    } else if (broker == "Angel One") {
      launchUrl(Uri.parse("angelone://spark/search?query=$symbol"),
              mode: LaunchMode.externalApplication)
          .catchError(
              (_) => launchUrl(Uri.parse("https://trade.angelone.in/")));
    } else if (broker == "Paytm Money") {
      launchUrl(Uri.parse("paytmmoney://stocks/detail?symbol=$symbol"),
              mode: LaunchMode.externalApplication)
          .catchError(
              (_) => launchUrl(Uri.parse("https://www.paytmmoney.com/stocks")));
    }
  }

  void handleDematAction(String symbol) {
    Clipboard.setData(ClipboardData(text: symbol));

    if (defaultDematBroker != "Ask Every Time") {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              "🚀 '$symbol' कॉपीड! डिफ़ॉल्ट ब्रोकर ($defaultDematBroker) खुल रहा है..."),
          backgroundColor: const Color(0xFF00E676),
        ),
      );
      launchDirectBroker(symbol, defaultDematBroker);
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("🚀 $symbol ट्रेड करें",
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: const Color(0xFF00E676).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF00E676))),
                    child: const Text("सिंबल कॉपीड",
                        style: TextStyle(
                            color: Color(0xFF00E676),
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  )
                ],
              ),
              const SizedBox(height: 6),
              const Text("शेयर का नाम कॉपी हो चुका है। अपना ऐप चुनें:",
                  style: TextStyle(fontSize: 13)),
              const SizedBox(height: 16),
              ListTile(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                tileColor: isDark ? const Color(0xFF1E293B) : Colors.grey[200],
                leading: const Icon(Icons.share,
                    color: Colors.amberAccent, size: 28),
                title: const Text("सभी ऐप्स में खोजें (Android Chooser)",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text("मोबाइल के किसी भी अन्य ऐप में भेजें"),
                onTap: () async {
                  Navigator.pop(ctx);
                  final uri = Uri.parse(
                      "intent:#Intent;action=android.intent.action.SEND;type=text/plain;S.android.intent.extra.TEXT=$symbol;end");
                  try {
                    await launchUrl(uri);
                  } catch (_) {}
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        launchDirectBroker(symbol, "Dhan");
                      },
                      child: const Text("Dhan",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0038FF),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        launchDirectBroker(symbol, "Angel One");
                      },
                      child: const Text("Angel One",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00B9F1),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        launchDirectBroker(symbol, "Paytm Money");
                      },
                      child: const Text("Paytm Money",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void executeBuyOrder(DarvasSignal s) {
    int orderQty = s.suggestedQty;
    double totalCost = s.currentPrice * orderQty;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text("⚡ बाय ऑर्डर: ${s.symbol}",
                style: const TextStyle(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("वर्तमान भाव: ₹${s.currentPrice.toStringAsFixed(2)}",
                    style: const TextStyle(
                        fontSize: 16,
                        color: Color(0xFF00E676),
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text("🎯 टारगेट 1: ₹${s.target1.toStringAsFixed(1)}",
                    style: const TextStyle(
                        fontSize: 13, color: Colors.amberAccent)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("क्वांटिटी (Shares):"),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle,
                              color: Colors.redAccent),
                          onPressed: orderQty > 1
                              ? () {
                                  setDialogState(() {
                                    orderQty--;
                                    totalCost = s.currentPrice * orderQty;
                                  });
                                }
                              : null,
                        ),
                        Text("$orderQty",
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.add_circle,
                              color: Color(0xFF00E676)),
                          onPressed: () {
                            setDialogState(() {
                              orderQty++;
                              totalCost = s.currentPrice * orderQty;
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("कुल निवेश:"),
                    Text("₹${totalCost.toStringAsFixed(2)}",
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("उपलब्ध कैश:"),
                    Text("₹${virtualCash.toStringAsFixed(2)}",
                        style: TextStyle(
                            color: virtualCash >= totalCost
                                ? const Color(0xFF00E676)
                                : Colors.redAccent,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("रद्द करें"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: virtualCash >= totalCost
                    ? () async {
                        final now = DateTime.now();
                        final timeString =
                            "${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}";

                        setState(() {
                          virtualCash -= totalCost;
                          activePositions.add(VirtualPosition(
                            id: DateTime.now()
                                .millisecondsSinceEpoch
                                .toString(),
                            symbol: s.symbol,
                            buyPrice: s.currentPrice,
                            currentPrice: s.currentPrice,
                            currentSL: s.stopLoss,
                            targetPrice: s.target1,
                            qty: orderQty,
                            buyTime: timeString,
                          ));
                        });

                        await saveAllUserDataAndAutoBackup();
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                "✅ ${s.symbol} ($orderQty शेयर्स) पोर्टफोलियो में सुरक्षित जुड़ गया!"),
                            backgroundColor: const Color(0xFF00E676),
                          ),
                        );
                      }
                    : null,
                child: const Text("बाय कन्फर्म करें",
                    style: TextStyle(
                        color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> exitPositionAndRecordHistory(VirtualPosition pos) async {
    final now = DateTime.now();
    final timeString =
        "${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}";
    final double saleProceeds = pos.currentPrice * pos.qty;
    final double pnl = (pos.currentPrice - pos.buyPrice) * pos.qty;

    setState(() {
      virtualCash += saleProceeds;
      activePositions.removeWhere((item) => item.id == pos.id);

      tradeHistory.insert(
        0,
        TradeHistoryItem(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          symbol: pos.symbol,
          buyPrice: pos.buyPrice,
          sellPrice: pos.currentPrice,
          targetPrice: pos.targetPrice,
          qty: pos.qty,
          pnl: pnl,
          buyTime: pos.buyTime,
          sellTime: timeString,
        ),
      );
    });

    await saveAllUserDataAndAutoBackup();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "🚪 ${pos.symbol} एग्जिट! P&L: ₹${pnl.toStringAsFixed(2)} (ऑटो-सेव हुआ)",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor:
            pnl >= 0 ? const Color(0xFF00E676) : Colors.redAccent,
      ),
    );
  }

  Future<void> deleteHistoryItem(String id) async {
    setState(() {
      tradeHistory.removeWhere((item) => item.id == id);
    });
    await saveAllUserDataAndAutoBackup();
  }

  // एकल स्टॉक डेटा फेच हेल्पर (बैच प्रोसेसिंग के लिए)
  Future<DarvasSignal?> fetchSingleStockSignal(String symbol) async {
    try {
      final url = Uri.parse(
          'https://query1.finance.yahoo.com/v8/finance/chart/$symbol.NS?interval=1d&range=1y');
      final response = await http.get(url, headers: {
        'User-Agent':
            'Mozilla/5.0 (Android; Mobile; rv:109.0) Gecko/109.0 Firefox/119.0'
      }).timeout(const Duration(seconds: 7));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final quote = data['chart']['result'][0]['indicators']['quote'][0];

        List<double> closes = [];
        List<double> highs = [];
        List<double> lows = [];
        List<double> volumes = [];

        for (int i = 0; i < quote['close'].length; i++) {
          if (quote['close'][i] != null &&
              quote['high'][i] != null &&
              quote['low'][i] != null &&
              quote['volume'][i] != null) {
            closes.add(quote['close'][i].toDouble());
            highs.add(quote['high'][i].toDouble());
            lows.add(quote['low'][i].toDouble());
            volumes.add(quote['volume'][i].toDouble());
          }
        }

        if (closes.length >= 60) {
          double currentPrice = closes.last;
          double currentHigh = highs.last;
          double currentLow = lows.last;
          double currentVol = volumes.last;

          double high52w = highs.reduce((a, b) => a > b ? a : b);
          double distFrom52w = ((high52w - currentPrice) / high52w) * 100;
          bool isNear52w = distFrom52w <= max52wDist;

          double avgVol20 = volumes
                  .sublist(volumes.length - 21, volumes.length - 1)
                  .reduce((a, b) => a + b) /
              20;
          double volumeMultiplier = currentVol / avgVol20;

          double ema50 =
              closes.sublist(closes.length - 35).reduce((a, b) => a + b) / 35;

          double boxTop = highs
              .sublist(highs.length - 20, highs.length - 2)
              .reduce((a, b) => a > b ? a : b);
          double boxBottom = lows
              .sublist(lows.length - 20, lows.length - 2)
              .reduce((a, b) => a < b ? a : b);
          double boxHeight = boxTop - boxBottom;

          double candleRange = currentHigh - currentLow;
          double upperWick = currentHigh - currentPrice;
          bool isCleanBody =
              candleRange > 0 ? (upperWick / candleRange) <= 0.35 : true;

          // कस्टम रिस्क % के अनुसार क्वांटिटी गणना
          double riskAmount = initialCapital * (riskPercentPerTrade / 100);
          double riskPerShare = (currentPrice - boxBottom).abs();
          if (riskPerShare < 1.0) riskPerShare = currentPrice * 0.02;
          int qty = (riskAmount / riskPerShare).floor().clamp(1, 100000);

          double target1 = boxTop + (boxHeight * 2);
          double addLevel = boxTop + boxHeight;
          double nextTarget = addLevel + (boxHeight * 2);

          double rewardDistance = target1 - currentPrice;
          double riskRatio =
              rewardDistance / (riskPerShare > 0 ? riskPerShare : 1);
          String rrText = "1:${riskRatio.toStringAsFixed(1)}";

          for (var pos in activePositions) {
            if (pos.symbol == symbol) {
              pos.currentPrice = currentPrice;
              if (currentPrice > addLevel && pos.currentSL < boxTop) {
                pos.currentSL = boxTop;
              }
            }
          }

          if (currentPrice > boxTop &&
              isNear52w &&
              currentPrice > ema50 &&
              volumeMultiplier >= volMultiplierReq &&
              isCleanBody) {
            return DarvasSignal(
              symbol: symbol,
              status: "BUY (High Accuracy)",
              currentPrice: currentPrice,
              entryPrice: boxTop,
              stopLoss: boxBottom,
              target1: target1,
              addLevel: addLevel,
              nextTarget: nextTarget,
              suggestedQty: qty,
              reason: "52W हाई के पास क्लीन ब्रेकआउट + वॉल्यूम पुष्टि!",
              near52wPercent: distFrom52w,
              volumeSurgeX: volumeMultiplier,
              riskRewardRatio: rrText,
            );
          } else if (currentPrice >= (boxTop * 0.985) &&
              currentPrice <= boxTop &&
              isNear52w) {
            return DarvasSignal(
              symbol: symbol,
              status: "RADAR (Pre-Breakout)",
              currentPrice: currentPrice,
              entryPrice: boxTop,
              stopLoss: boxBottom,
              target1: target1,
              addLevel: addLevel,
              nextTarget: nextTarget,
              suggestedQty: qty,
              reason: "ब्रेकआउट की कगार पर! बॉक्स टॉप के 1.5% भीतर।",
              near52wPercent: distFrom52w,
              volumeSurgeX: volumeMultiplier,
              riskRewardRatio: rrText,
            );
          } else if (currentPrice > addLevel) {
            return DarvasSignal(
              symbol: symbol,
              status: "ADD (Pyramid)",
              currentPrice: currentPrice,
              entryPrice: addLevel,
              stopLoss: boxTop,
              target1: nextTarget,
              addLevel: addLevel + boxHeight,
              nextTarget: nextTarget + boxHeight,
              suggestedQty: (qty * 0.5).floor().clamp(1, 50000),
              reason: "नया बॉक्स ब्रेकआउट! पोजीशन में और शेयर जोड़ें।",
              near52wPercent: distFrom52w,
              volumeSurgeX: volumeMultiplier,
              riskRewardRatio: rrText,
            );
          } else if (currentPrice < boxBottom) {
            return DarvasSignal(
              symbol: symbol,
              status: "EXIT",
              currentPrice: currentPrice,
              entryPrice: boxTop,
              stopLoss: boxBottom,
              target1: target1,
              addLevel: addLevel,
              nextTarget: nextTarget,
              suggestedQty: 0,
              reason: "बॉक्स बॉटम टूटा! एग्जिट करें।",
              near52wPercent: distFrom52w,
              volumeSurgeX: volumeMultiplier,
              riskRewardRatio: "N/A",
            );
          } else {
            return DarvasSignal(
              symbol: symbol,
              status: "HOLD",
              currentPrice: currentPrice,
              entryPrice: boxTop,
              stopLoss: boxBottom,
              target1: target1,
              addLevel: addLevel,
              nextTarget: nextTarget,
              suggestedQty: qty,
              reason: "डार्वस कंसॉलिडेशन बॉक्स के अंदर चल रहा है।",
              near52wPercent: distFrom52w,
              volumeSurgeX: volumeMultiplier,
              riskRewardRatio: rrText,
            );
          }
        }
      }
    } catch (_) {}
    return null;
  }

  // Nifty 200 त्वरित बैच स्कैनिंग (15 स्टॉक्स प्रति बैच)
  Future<void> runFullDarvasScan() async {
    if (isScanning) return;
    setState(() {
      isScanning = true;
      scannedCount = 0;
    });

    List<DarvasSignal> tempResults = [];
    const int batchSize = 15;

    for (int i = 0; i < watchlist.length; i += batchSize) {
      final batch = watchlist.skip(i).take(batchSize).toList();
      final batchFutures = batch.map((sym) => fetchSingleStockSignal(sym));
      final results = await Future.wait(batchFutures);

      for (var item in results) {
        if (item != null) {
          tempResults.add(item);
        }
      }

      if (mounted) {
        setState(() {
          scannedCount = (i + batch.length).clamp(0, watchlist.length);
          // BUY और RADAR सिग्नल्स को सबसे ऊपर दिखाना
          tempResults.sort((a, b) {
            int priority(String st) {
              if (st.contains("BUY")) return 1;
              if (st.contains("RADAR")) return 2;
              if (st.contains("ADD")) return 3;
              if (st == "EXIT") return 4;
              return 5;
            }
            return priority(a.status).compareTo(priority(b.status));
          });
          signalList = List.from(tempResults);
        });
      }
    }

    await saveAllUserDataAndAutoBackup();

    if (mounted) {
      setState(() {
        isScanning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    IconData themeIcon;
    if (widget.currentThemeMode == ThemeMode.dark) {
      themeIcon = Icons.dark_mode;
    } else if (widget.currentThemeMode == ThemeMode.light) {
      themeIcon = Icons.light_mode;
    } else {
      themeIcon = Icons.brightness_auto;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.candlestick_chart, color: Color(0xFF00E676)),
            SizedBox(width: 8),
            Text('DARVAS PRO 200',
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                    fontSize: 17)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: "डे/नाइट/सिस्टम थीम",
            icon: Icon(themeIcon, color: const Color(0xFF00B0FF)),
            onPressed: widget.onToggleTheme,
          ),
          IconButton(
            tooltip: "टेस्ट अलर्ट",
            icon: const Icon(Icons.notifications_active,
                color: Color(0xFF00E676)),
            onPressed: () {
              triggerNotification(
                "🔔 Darvas Pro 200 Active",
                "निफ्टी 200 स्कैनर और ऑटो-बैकअप सिस्टम सक्रिय हैं!",
              );
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: currentTabIndex,
        children: [
          buildScannerTab(),
          buildPortfolioTab(),
          buildJournalTab(),
          buildProfileAndSettingsTab(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white12, width: 0.5)),
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: currentTabIndex,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          onTap: (index) => setState(() => currentTabIndex = index),
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.radar),
              label: "स्कैनर (200)",
            ),
            BottomNavigationBarItem(
              icon: Stack(
                children: [
                  const Icon(Icons.account_balance_wallet),
                  if (activePositions.isNotEmpty)
                    const Positioned(
                      right: 0,
                      top: 0,
                      child: CircleAvatar(
                        radius: 5,
                        backgroundColor: Colors.redAccent,
                      ),
                    )
                ],
              ),
              label: "पोर्टफोलियो",
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.history_edu),
              label: "जर्नल",
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.person_pin),
              label: "प्रोफ़ाइल / सेटिंग",
            ),
          ],
        ),
      ),
      floatingActionButton: currentTabIndex == 0
          ? FloatingActionButton.extended(
              onPressed: isScanning ? null : runFullDarvasScan,
              backgroundColor: const Color(0xFF00E676),
              foregroundColor: Colors.black,
              icon: const Icon(Icons.bolt),
              label: Text(
                  isScanning
                      ? "स्कैन: $scannedCount/${watchlist.length}"
                      : "Nifty 200 स्कैन",
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }

  // 1. लाइव स्कैनर टैब
  Widget buildScannerTab() {
    final filteredSignals = signalList.where((s) {
      return s.symbol.toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: TextField(
            controller: searchController,
            decoration: InputDecoration(
              hintText:
                  "Nifty 200 में शेयर सर्च करें (उदा. HAL, TRENT, TATASTEEL)...",
              prefixIcon: const Icon(Icons.search, color: Color(0xFF00E676)),
              suffixIcon: searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        searchController.clear();
                        setState(() => searchQuery = "");
                      },
                    )
                  : null,
              filled: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (val) {
              setState(() => searchQuery = val);
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(marketStatus,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold)),
              Text(
                "कैश: ₹${virtualCash.toStringAsFixed(0)}",
                style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF00E676),
                    fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
        if (isScanning)
          LinearProgressIndicator(
            value: watchlist.isNotEmpty ? scannedCount / watchlist.length : 0,
            color: const Color(0xFF00E676),
          ),
        Expanded(
          child: signalList.isEmpty && !isScanning
              ? Center(
                  child: ElevatedButton.icon(
                    onPressed: runFullDarvasScan,
                    icon: const Icon(Icons.refresh, color: Colors.black),
                    label: const Text("Nifty 200 स्कैन शुरू करें",
                        style: TextStyle(
                            color: Colors.black, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E676)),
                  ),
                )
              : filteredSignals.isEmpty
                  ? Center(
                      child: Text("'$searchQuery' का कोई शेयर नहीं मिला।"),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: filteredSignals.length,
                      itemBuilder: (ctx, index) =>
                          buildInteractiveStockCard(filteredSignals[index]),
                    ),
        ),
      ],
    );
  }

  // 2. डीमैट पोर्टफोलियो टैब
  Widget buildPortfolioTab() {
    double totalInvested = 0;
    double currentHoldingValue = 0;

    for (var pos in activePositions) {
      totalInvested += (pos.buyPrice * pos.qty);
      currentHoldingValue += (pos.currentPrice * pos.qty);
    }

    double totalPortfolioValue = virtualCash + currentHoldingValue;
    double totalUnrealizedPnL = currentHoldingValue - totalInvested;
    double pnlPercent = totalInvested > 0
        ? (totalUnrealizedPnL / totalInvested) * 100
        : 0.0;
    bool isOverallProfit = totalUnrealizedPnL >= 0;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("कुल पोर्टफोलियो नेटवर्थ",
                      style: TextStyle(fontSize: 13)),
                  Text("₹${totalPortfolioValue.toStringAsFixed(2)}",
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("इन्वेस्टेड",
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 2),
                      Text("₹${totalInvested.toStringAsFixed(1)}",
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("कैश बैलेंस",
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 2),
                      Text("₹${virtualCash.toStringAsFixed(1)}",
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF00E676))),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text("कुल P&L (अनरियलाइज्ड)",
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 2),
                      Text(
                        "${isOverallProfit ? '+' : ''}₹${totalUnrealizedPnL.toStringAsFixed(1)} (${pnlPercent.toStringAsFixed(2)}%)",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: isOverallProfit
                              ? const Color(0xFF00E676)
                              : Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: activePositions.isEmpty
              ? const Center(
                  child: Text(
                      "कोई सक्रिय पोजीशन नहीं है!\nस्कैनर में जाकर 'वर्चुअल खरीदें' बटन से पोजीशन बनाएं।",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, height: 1.6)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: activePositions.length,
                  itemBuilder: (context, index) {
                    final pos = activePositions[index];
                    final pnl = (pos.currentPrice - pos.buyPrice) * pos.qty;
                    final itemPnlPercent =
                        ((pos.currentPrice - pos.buyPrice) / pos.buyPrice) *
                            100;
                    final isProfit = pnl >= 0;

                    return Card(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(pos.symbol,
                                    style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold)),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: (isProfit
                                            ? const Color(0xFF00E676)
                                            : Colors.redAccent)
                                        .withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isProfit
                                          ? const Color(0xFF00E676)
                                          : Colors.redAccent,
                                    ),
                                  ),
                                  child: Text(
                                    "${isProfit ? '+' : ''}₹${pnl.toStringAsFixed(1)} (${itemPnlPercent.toStringAsFixed(2)}%)",
                                    style: TextStyle(
                                      color: isProfit
                                          ? const Color(0xFF00E676)
                                          : Colors.redAccent,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                    "खरीद: ₹${pos.buyPrice.toStringAsFixed(1)}"),
                                Text(
                                    "LTP: ₹${pos.currentPrice.toStringAsFixed(1)}",
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF00B0FF))),
                                Text("मात्रा: ${pos.qty} शेयर्स"),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                    "🛑 ट्रेलिंग SL: ₹${pos.currentSL.toStringAsFixed(1)}",
                                    style: const TextStyle(
                                        color: Colors.orangeAccent,
                                        fontWeight: FontWeight.bold)),
                                Text(
                                    "🎯 Target: ₹${pos.targetPrice.toStringAsFixed(1)}",
                                    style: const TextStyle(
                                        color: Colors.amberAccent,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const Divider(height: 20),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => openTradingView(pos.symbol),
                                    icon: const Icon(Icons.show_chart,
                                        size: 16, color: Color(0xFF00B0FF)),
                                    label: const Text("चार्ट",
                                        style: TextStyle(
                                            color: Color(0xFF00B0FF))),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                          color: Color(0xFF00B0FF)),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () =>
                                        exitPositionAndRecordHistory(pos),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.redAccent,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ),
                                    icon: const Icon(Icons.close,
                                        size: 16, color: Colors.white),
                                    label: const Text("Exit Position",
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // 3. ट्रेड जर्नल व हिस्ट्री टैब
  Widget buildJournalTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).cardColor,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("📜 क्लोज्ड ट्रेड्स हिस्ट्री",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text("🛡️ ऑटो-बैकअप एक्टिव",
                    style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF00E676),
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        Expanded(
          child: tradeHistory.isEmpty
              ? const Center(
                  child: Text(
                      "अभी तक कोई ट्रेड क्लोज नहीं हुआ है।\nजब भी आप कोई पोजीशन बेचेंगे, उसका पूरा लाभ/हानि व टारगेट रिकॉर्ड यहाँ हमेशा रहेगा।",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, height: 1.6)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: tradeHistory.length,
                  itemBuilder: (context, index) {
                    final item = tradeHistory[index];
                    final isProfit = item.pnl >= 0;

                    return Card(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(item.symbol,
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold)),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: (isProfit
                                                ? const Color(0xFF00E676)
                                                : Colors.redAccent)
                                            .withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        "${isProfit ? '+' : ''}₹${item.pnl.toStringAsFixed(1)}",
                                        style: TextStyle(
                                          color: isProfit
                                              ? const Color(0xFF00E676)
                                              : Colors.redAccent,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          size: 18, color: Colors.grey),
                                      onPressed: () =>
                                          deleteHistoryItem(item.id),
                                    ),
                                  ],
                                )
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                    "बाय: ₹${item.buyPrice.toStringAsFixed(1)}"),
                                Text(
                                    "सेल: ₹${item.sellPrice.toStringAsFixed(1)}"),
                                Text(
                                    "🎯 Target: ₹${item.targetPrice.toStringAsFixed(1)}",
                                    style: const TextStyle(
                                        color: Colors.amberAccent,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("मात्रा: ${item.qty} Sh."),
                                Text("बाय: ${item.buyTime}",
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.grey)),
                                Text("सेल: ${item.sellTime}",
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // 4. प्रोफ़ाइल और सेटिंग्स टैब (Profile, Performance & Strategy Settings)
  Widget buildProfileAndSettingsTab() {
    int totalClosed = tradeHistory.length;
    int winningTrades = tradeHistory.where((t) => t.pnl > 0).length;
    double winRate =
        totalClosed > 0 ? (winningTrades / totalClosed) * 100 : 0.0;
    double bestTrade = totalClosed > 0
        ? tradeHistory.map((t) => t.pnl).reduce((a, b) => a > b ? a : b)
        : 0.0;
    double netRealizedPnL = totalClosed > 0
        ? tradeHistory.map((t) => t.pnl).reduce((a, b) => a + b)
        : 0.0;

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // 1. ट्रेडर प्रोफ़ाइल कार्ड
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor:
                          const Color(0xFF00E676).withOpacity(0.2),
                      child: const Icon(Icons.person,
                          size: 32, color: Color(0xFF00E676)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(traderName,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          const Text("Momentum & Darvas Swing Trader",
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit, color: Color(0xFF00B0FF)),
                      onPressed: () {
                        final nameCtrl =
                            TextEditingController(text: traderName);
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text("प्रोफ़ाइल नाम बदलें"),
                            content: TextField(
                              controller: nameCtrl,
                              decoration: const InputDecoration(
                                  labelText: "आपका नाम"),
                            ),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text("रद्द")),
                              ElevatedButton(
                                onPressed: () async {
                                  if (nameCtrl.text.trim().isNotEmpty) {
                                    setState(() =>
                                        traderName = nameCtrl.text.trim());
                                    await saveAllUserDataAndAutoBackup();
                                  }
                                  Navigator.pop(ctx);
                                },
                                child: const Text("सेव"),
                              ),
                            ],
                          ),
                        );
                      },
                    )
                  ],
                ),
                const Divider(height: 24),
                // विन-रेट और एक्यूरेसी मीटर
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text("${winRate.toStringAsFixed(1)}%",
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF00E676))),
                        const Text("विन-रेट (Win Rate)",
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                    Column(
                      children: [
                        Text(
                            "${netRealizedPnL >= 0 ? '+' : ''}₹${netRealizedPnL.toStringAsFixed(0)}",
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: netRealizedPnL >= 0
                                    ? const Color(0xFF00E676)
                                    : Colors.redAccent)),
                        const Text("कुल रियलाइज्ड P&L",
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                    Column(
                      children: [
                        Text("+₹${bestTrade.toStringAsFixed(0)}",
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Colors.amberAccent)),
                        const Text("सर्वश्रेष्ठ ट्रेड",
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 2. ट्रेडिंग व अल्गोरिदम सेटिंग्स
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("⚙️ ट्रेडिंग व रिस्क सेटिंग्स",
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),

                // प्रति ट्रेड रिस्क स्लाइडर
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("प्रति ट्रेड रिस्क (Risk %):"),
                    Text("${riskPercentPerTrade.toStringAsFixed(1)}%",
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00E676))),
                  ],
                ),
                Slider(
                  value: riskPercentPerTrade,
                  min: 0.5,
                  max: 3.0,
                  divisions: 5,
                  activeColor: const Color(0xFF00E676),
                  onChanged: (val) async {
                    setState(() => riskPercentPerTrade = val);
                    await saveAllUserDataAndAutoBackup();
                  },
                ),

                // वॉल्यूम सर्ज गुणक स्लाइडर
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("न्यूनतम वॉल्यूम सर्ज:"),
                    Text("${volMultiplierReq.toStringAsFixed(1)}x Avg",
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00B0FF))),
                  ],
                ),
                Slider(
                  value: volMultiplierReq,
                  min: 1.1,
                  max: 2.5,
                  divisions: 14,
                  activeColor: const Color(0xFF00B0FF),
                  onChanged: (val) async {
                    setState(() => volMultiplierReq = val);
                    await saveAllUserDataAndAutoBackup();
                  },
                ),

                // 52-वीक हाई रेंज स्लाइडर
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("52-वीक हाई से अधिकतम दूरी:"),
                    Text("${max52wDist.toStringAsFixed(0)}%",
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.amberAccent)),
                  ],
                ),
                Slider(
                  value: max52wDist,
                  min: 5.0,
                  max: 25.0,
                  divisions: 4,
                  activeColor: Colors.amberAccent,
                  onChanged: (val) async {
                    setState(() => max52wDist = val);
                    await saveAllUserDataAndAutoBackup();
                  },
                ),
                const Divider(height: 20),

                // डिफ़ॉल्ट डीमैट ब्रोकर चयन
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("डिफ़ॉल्ट डीमैट खाता:"),
                    DropdownButton<String>(
                      value: defaultDematBroker,
                      underline: const SizedBox(),
                      items: ["Ask Every Time", "Dhan", "Angel One", "Paytm Money"]
                          .map((b) => DropdownMenuItem(
                              value: b,
                              child: Text(b,
                                  style: const TextStyle(fontSize: 13))))
                          .toList(),
                      onChanged: (val) async {
                        if (val != null) {
                          setState(() => defaultDematBroker = val);
                          await saveAllUserDataAndAutoBackup();
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 3. वॉचलिस्ट व कैपिटल कंट्रोल
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("📊 वॉचलिस्ट व पूंजी प्रबंधन (${watchlist.length} शेयर्स)",
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.add_circle_outline, size: 18),
                        label: const Text("नया शेयर जोड़ें"),
                        onPressed: () {
                          final symCtrl = TextEditingController();
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text("वॉचलिस्ट में NSE शेयर जोड़ें"),
                              content: TextField(
                                controller: symCtrl,
                                textCapitalization:
                                    TextCapitalization.characters,
                                decoration: const InputDecoration(
                                    hintText: "उदा. SUZLON, TATAMOTORS"),
                              ),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text("रद्द")),
                                ElevatedButton(
                                  onPressed: () async {
                                    final sym =
                                        symCtrl.text.trim().toUpperCase();
                                    if (sym.isNotEmpty &&
                                        !watchlist.contains(sym)) {
                                      setState(() => watchlist.insert(0, sym));
                                      await saveAllUserDataAndAutoBackup();
                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                              content: Text(
                                                  "✅ $sym वॉचलिस्ट में जुड़ गया!")));
                                    }
                                  },
                                  child: const Text("जोड़ें"),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.account_balance, size: 18),
                        label: const Text("पूंजी रीसेट करें"),
                        onPressed: () {
                          final capCtrl = TextEditingController(
                              text: initialCapital.toStringAsFixed(0));
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text("वर्चुअल पूंजी सेट करें"),
                              content: TextField(
                                controller: capCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    labelText: "नई कुल पूंजी (₹)"),
                              ),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text("रद्द")),
                                ElevatedButton(
                                  onPressed: () async {
                                    final newCap =
                                        double.tryParse(capCtrl.text) ??
                                            100000.0;
                                    setState(() {
                                      initialCapital = newCap;
                                      virtualCash = newCap;
                                    });
                                    await saveAllUserDataAndAutoBackup();
                                    Navigator.pop(ctx);
                                  },
                                  child: const Text("अपडेट करें"),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text("🛡️ आखिरी ऑटो-बैकअप: $lastBackupTimestamp",
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // मॉडर्न स्टॉक कार्ड
  Widget buildInteractiveStockCard(DarvasSignal s) {
    Color badgeColor;
    if (s.status.contains("BUY")) {
      badgeColor = const Color(0xFF00E676);
    } else if (s.status.contains("RADAR")) {
      badgeColor = Colors.purpleAccent;
    } else if (s.status.contains("ADD")) {
      badgeColor = const Color(0xFF00B0FF);
    } else if (s.status == "EXIT") {
      badgeColor = Colors.redAccent;
    } else {
      badgeColor = Colors.orangeAccent;
    }

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(s.symbol,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w900)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00B0FF).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        "52W: -${s.near52wPercent.toStringAsFixed(1)}%",
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF00B0FF)),
                      ),
                    )
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: badgeColor),
                  ),
                  child: Text(s.status,
                      style: TextStyle(
                          color: badgeColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("₹${s.currentPrice.toStringAsFixed(2)}",
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w900)),
                Text(
                  "वॉल्यूम: ${s.volumeSurgeX.toStringAsFixed(1)}x Avg",
                  style: TextStyle(
                    fontSize: 12,
                    color: s.volumeSurgeX >= volMultiplierReq
                        ? const Color(0xFF00E676)
                        : Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("🎯 Entry: ₹${s.entryPrice.toStringAsFixed(1)}",
                          style: const TextStyle(
                              color: Color(0xFF00E676), fontSize: 13)),
                      const SizedBox(height: 4),
                      Text("🛑 SL: ₹${s.stopLoss.toStringAsFixed(1)}",
                          style: const TextStyle(
                              color: Colors.redAccent, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text("🏁 Target: ₹${s.target1.toStringAsFixed(1)}",
                          style: const TextStyle(
                              color: Colors.amberAccent, fontSize: 13)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("➕ Add: ₹${s.addLevel.toStringAsFixed(1)}",
                          style: const TextStyle(
                              color: Color(0xFF00B0FF), fontSize: 13)),
                      const SizedBox(height: 4),
                      Text("⚖️ R:R: ${s.riskRewardRatio}",
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                          "📦 Qty (${riskPercentPerTrade.toStringAsFixed(1)}%): ${s.suggestedQty} Sh.",
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              "विवरण: ${s.reason}",
              style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: ElevatedButton(
                    onPressed: () => executeBuyOrder(s),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E676),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text(
                      "वर्चुअल खरीदें",
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    onPressed: () => openTradingView(s.symbol),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Color(0xFF00B0FF)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text(
                      "चार्ट",
                      style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF00B0FF),
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    onPressed: () => handleDematAction(s.symbol),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Colors.orangeAccent),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text(
                      "डीमैट",
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.orangeAccent,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
