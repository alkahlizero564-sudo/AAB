import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../analysis/sr_levels.dart';
import '../analysis/king_indicator.dart';
import '../analysis/aab_algo.dart';
import '../analysis/alka.dart';
import '../analysis/st_indicator.dart';
import '../analysis/star_indicator.dart';
import '../analysis/zero_one.dart';
import '../analysis/sm_indicator.dart';
import '../analysis/all_indicator.dart';
import '../analysis/forecast.dart';
import '../analysis/mtf.dart';
import '../analysis/fz_indicator.dart';
import '../analysis/vote_indicator.dart';
import '../analysis/q_indicator.dart';
import '../analysis/q_model.dart' show qH;
import '../analysis/indicators.dart';
import '../models.dart';
import '../theme.dart';

class ChartLayers {
  bool fib = false, vp = false, zones = false, vwap = false, levels = false, ce = false;
  bool sigs = false, fc = true, pats = false, ema = false;
  bool algo = true; // مؤشر AAB Algo: تلوين الشموع + خط الاتجاه + مناطق الانعكاس
  bool alka = false; // مؤشر Alka: شموع الانعكاس عند الدعم/المقاومة و Volume Profile
  bool all = false; // مؤشر ALL: دمج AAB و Alka + فلتر الشمعة الصغيرة
  bool mp = true; // مؤشر Mp: دمج مؤشراتنا الأربعة (ALL + 0.1) — الأقوى
  bool dm = false; // مؤشر DM: خاص بالذهب (Mp مع الترند اليومي في السوق الهادئ)
  bool star = false; // مؤشر النجوم: كل إشارات Mp مع نجوم بعدد المؤشرات الموافقة (SM و KM و ST و DM)
  bool st = false; // مؤشر ST: إشارات Mp عالية الثقة حسب النموذج المتعلّم
  bool km = false; // مؤشر KM: إشارات SM في السوق الهادئ (الأدق، صفقات قليلة)
  bool sm = false; // مؤشر SM: إشارات Mp التي يوافقها شريط المتوسطات + رسم الشريط
  bool zero = false; // مؤشر 0.1: مصيدة سيولة + شمعة رفض (أزرق شراء، أصفر بيع)
  bool vol = true; // أعمدة الحجم أسفل الشارت
  bool sr = false; // مستويات الدعم والمقاومة (زر في أعلى الشارت)
  bool lt = false; // مؤشر LT بعيد المدى (يُرسم على الفريم اليومي)
  bool pq = false; // مؤشر PQ: النجوم + SM + Alka
  bool king = false; // مؤشر King: ذكاء اصطناعي
  bool aiak = false; // مؤشر AK: توصيات AAB في أعلى 15% حسب King
  bool q = false; // مؤشر Q: خريطة الاحتمالات للـ 12 شمعة القادمة
  bool vote = false; // الإجماع: 5 مؤشرات أو أكثر من 7 متفقة — شراء/بيع مع نجوم
  bool fz = false; // FZ: مناطق الفيبوناتشي (خضراء/حمراء) + شراء/بيع عند الارتداد أو الكسر
  bool fast = false; // Fast: King أعلى 50% من 5m و15m و1h — إشارات كثيرة
  bool mtf = false; // King متعدد الفريمات (5m و15m و1h): علامات شراء/بيع فقط
  String type = 'candle'; // candle | ha (Heikin Ashi) | line
  String sub = 'rsi'; // none | rsi | macd — اللوحة السفلية

  /// نسخة بنفس الإعدادات (لإخفاء مؤقت بدون تغيير اختيار المستخدم).
  ChartLayers copyWith({bool? sigs, bool? alka, bool? all, bool? zero, bool? mp, bool? sm, bool? km, bool? dm, bool? st, bool? star}) => ChartLayers()
    ..fib = fib
    ..vp = vp
    ..zones = zones
    ..vwap = vwap
    ..levels = levels
    ..ce = ce
    ..sigs = sigs ?? this.sigs
    ..fc = fc
    ..pats = pats
    ..ema = ema
    ..algo = algo
    ..alka = alka ?? this.alka
    ..all = all ?? this.all
    ..zero = zero ?? this.zero
    ..mp = mp ?? this.mp
    ..sm = sm ?? this.sm
    ..km = km ?? this.km
    ..dm = dm ?? this.dm
    ..st = st ?? this.st
    ..star = star ?? this.star
    ..vol = vol
    ..sr = sr
    ..lt = lt
    ..pq = pq
    ..king = king
    ..aiak = aiak
    ..q = q
    ..mtf = mtf
    ..fast = fast
    ..fz = fz
    ..vote = vote
    ..type = type
    ..sub = sub;
}

/// ألوان مؤشر 0.1: أزرق للصعود وأصفر للهبوط.
const zeroUp = Color(0xFF2E8BFF), zeroDown = Color(0xFFFFD60A);

/// خط الكتابة في الشارت (null = خط النظام). يُغيَّر في اختبارات لقطات الشاشة فقط.
String? chartFont = 'Cairo';

const _tfMin = {'1m': 1, '5m': 5, '15m': 15, '30m': 30, '1h': 60, '4h': 240, '1d': 1440};

/// خطوة "جميلة" للمحور (1 ، 2 ، 2.5 ، 5 × 10^n).
double _niceStep(double raw) {
  if (raw <= 0 || raw.isNaN) return 1;
  final e = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final f = raw / e;
  final m = f <= 1 ? 1.0 : f <= 2 ? 2.0 : f <= 2.5 ? 2.5 : f <= 5 ? 5.0 : 10.0;
  return m * e;
}

/// Our own candlestick chart (no TradingView, no WebView).
/// Pinch = zoom, drag = scroll, long-press = crosshair, double-tap = reset.
class NativeChart extends StatefulWidget {
  final List<Candle> candles;
  final TradeSignal? signal;
  final Forecast? forecast;
  final AlgoResult? algo;
  final AlkaResult? alka;
  final AllResult? allR;
  final ZeroResult? zero;
  final AllResult? mpR;
  final AllResult? smR;
  final AllResult? kmR;
  final AllResult? dmR;
  final StResult? stR;
  final StarResult? starR;
  final AllResult? ltR;
  final AllResult? pqR;
  final AllResult? akR;
  final QResult? qR;
  final KingResult? kingR;
  final AllResult? mtfR;
  final AllResult? fastR;
  final FzResult? fzR;
  final AllResult? voteR;
  final MarketSymbol sym;
  final String tf;
  final ChartLayers layers;
  final ValueChanged<int?>? onSelect; // رقم الشمعة تحت المؤشر المتقاطع (null عند الإخفاء)
  final Listenable? repaint; // يعيد الرسم فوراً مع كل سعر لحظي
  const NativeChart({
    super.key,
    required this.candles,
    required this.signal,
    this.forecast,
    this.algo,
    this.alka,
    this.allR,
    this.zero,
    this.mpR,
    this.smR,
    this.kmR,
    this.dmR,
    this.stR,
    this.starR,
    this.ltR,
    this.pqR,
    this.akR,
    this.qR,
    this.kingR,
    this.mtfR,
    this.fastR,
    this.fzR,
    this.voteR,
    this.onSelect,
    this.repaint,
    required this.sym,
    required this.tf,
    required this.layers,
  });

  @override
  State<NativeChart> createState() => _NativeChartState();
}

/// حالة الحركة الناعمة بين الإطارات: مدى السعر يتحرك تدريجياً بدل القفز،
/// وإغلاق الشمعة الحية يتحرك بنعومة مع كل سعر جديد.
class _Smooth {
  String key = '';
  double hi = double.nan, lo = double.nan;
  int closeTs = 0;
  double close = double.nan;
  bool moving = false;
  VoidCallback? onMove;
}

class _NativeChartState extends State<NativeChart> with TickerProviderStateMixin {
  static const _homeShift = -6.0;
  double visible = 70, shift = _homeShift, _baseVisible = 70;
  double yZoom = 1, _baseYZoom = 1; // تكبير عمودي يدوي (اسحب على محور السعر)
  bool _axisDrag = false;
  double _chartW = 1;
  Offset? cross;
  late final Ticker _ticker;
  final _sm = _Smooth();
  late final Ticker _smTicker;
  final _smTick = ValueNotifier<int>(0);
  late final AnimationController _home;
  double _hs0 = 0, _hv0 = 70, _hy0 = 1, _hs1 = 0, _hv1 = 70, _hy1 = 1;
  double _vel = 0; // سرعة التمرير بعد رفع الإصبع (شموع/ثانية)
  Duration _lastTick = Duration.zero;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    visible = _baseVisible = _defVisible(widget.tf);
    shift = _home0;
    _ticker = createTicker(_onTick);
    // إطارات إضافية فقط أثناء الحركة الناعمة (مدى السعر أو الشمعة الحية)
    _smTicker = createTicker((_) {
      if (_sm.moving) {
        _smTick.value++;
      } else {
        _smTicker.stop();
      }
    });
    _sm.onMove = () {
      if (_smTicker.isActive) return;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_smTicker.isActive && _sm.moving) _smTicker.start();
      });
    };
    // رجوع ناعم لآخر سعر (نقرتان أو زر "آخر سعر")
    _home = AnimationController(vsync: this, duration: const Duration(milliseconds: 380))
      ..addListener(() {
        final t = Curves.easeOutCubic.transform(_home.value);
        setState(() {
          shift = _hs0 + (_hs1 - _hs0) * t;
          visible = _hv0 + (_hv1 - _hv0) * t;
          yZoom = _hy0 + (_hy1 - _hy0) * t;
        });
      });
    // تحديث العدّاد التنازلي لإغلاق الشمعة كل ثانية
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && cross == null) setState(() {});
    });
  }

  /// عدد الشموع على الشاشة: أكثر في الفريمات الصغيرة حتى تظهر الإشارات
  static double _defVisible(String tf) => tf == '1m' || tf == '5m' ? 120 : 70;

  @override
  void didUpdateWidget(covariant NativeChart old) {
    super.didUpdateWidget(old);
    if (old.tf != widget.tf) {
      visible = _baseVisible = _defVisible(widget.tf);
      shift = _home0;
    } else if (old.layers.q != widget.layers.q && shift.abs() < 20) {
      shift = _home0;
    }
  }

  /// مع Q نترك مساحة أكبر يمين آخر شمعة لرسم الخريطة.
  double get _home0 => widget.layers.q ? -14.0 : _homeShift;

  void _goHome({bool resetZoom = false}) {
    _stopFling();
    _hs0 = shift;
    _hv0 = visible;
    _hy0 = yZoom;
    _hs1 = _home0;
    _hv1 = resetZoom ? _defVisible(widget.tf) : visible;
    _hy1 = resetZoom ? 1 : yZoom;
    _home.forward(from: 0);
  }

  @override
  void dispose() {
    _home.dispose();
    _smTicker.dispose();
    _smTick.dispose();
    _ticker.dispose();
    _clock?.cancel();
    super.dispose();
  }

  double get _maxShift => math.max(0, widget.candles.length - 20).toDouble();

  void _onTick(Duration t) {
    final dt = (t - _lastTick).inMicroseconds / 1e6;
    _lastTick = t;
    if (dt <= 0 || dt > 0.1) return;
    setState(() {
      shift = (shift + _vel * dt).clamp(-12.0, _maxShift).toDouble();
      _vel *= math.pow(0.04, dt).toDouble(); // احتكاك
    });
    if (_vel.abs() < 2 || shift <= -12 || shift >= _maxShift) {
      _ticker.stop();
    }
  }

  int? _lastSel;
  void _setCross(Offset? p) {
    cross = p;
    int? idx;
    if (p != null && widget.candles.isNotEmpty) {
      final n = widget.candles.length;
      final barW = _chartW / visible;
      final left = n - 1 - shift - visible + 1;
      idx = (p.dx.clamp(0.0, _chartW) / barW + left - 0.5).round().clamp(0, n - 1).toInt();
    }
    if (idx != _lastSel) {
      _lastSel = idx;
      widget.onSelect?.call(idx);
    }
  }

  void _stopFling() {
    if (_ticker.isActive) _ticker.stop();
    _vel = 0;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      _chartW = math.max(1.0, box.maxWidth - _Painter.axisW);
      return Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            onScaleStart: (d) {
              _stopFling();
              _baseVisible = visible;
              _baseYZoom = yZoom;
              _axisDrag = d.pointerCount == 1 && d.localFocalPoint.dx > _chartW;
            },
            onScaleUpdate: (d) {
              final n = widget.candles.length;
              setState(() {
                if (_axisDrag) {
                  // سحب عمودي على محور السعر = تكبير/تصغير السعر
                  yZoom = (yZoom * math.exp(d.focalPointDelta.dy / 150))
                      .clamp(0.2, 6.0)
                      .toDouble();
                  return;
                }
                final barW0 = _chartW / visible;
                if (d.pointerCount >= 2) {
                  // تكبير حول نقطة الإصبعين: الشمعة تحت الأصابع تبقى مكانها
                  final fx = d.localFocalPoint.dx.clamp(0.0, _chartW);
                  final right0 = n - 1 - shift;
                  final left0 = right0 - visible + 1;
                  final idxF = left0 + fx / barW0 - 0.5;
                  visible = (_baseVisible / d.horizontalScale).clamp(20.0, 320.0).toDouble();
                  final bw = _chartW / visible;
                  final left1 = idxF - fx / bw + 0.5;
                  shift = n - 1 - (left1 + visible - 1);
                  if (d.verticalScale > 0 && (d.verticalScale - 1).abs() > 0.15 &&
                      (d.horizontalScale - 1).abs() < 0.05) {
                    yZoom = (_baseYZoom / d.verticalScale).clamp(0.2, 6.0).toDouble();
                  }
                }
                final barW = _chartW / visible;
                shift = (shift + d.focalPointDelta.dx / barW)
                    .clamp(-12.0, _maxShift)
                    .toDouble();
              });
            },
            onScaleEnd: (d) {
              if (_axisDrag || d.pointerCount > 0) return;
              final barW = _chartW / visible;
              _vel = d.velocity.pixelsPerSecond.dx / barW;
              if (_vel.abs() > 8) {
                _lastTick = Duration.zero;
                _ticker.start();
              }
            },
            onTapDown: (_) => _stopFling(),
            onTap: () {
              if (cross != null) setState(() => _setCross(null));
            },
            onLongPressStart: (d) => setState(() => _setCross(d.localPosition)),
            onLongPressMoveUpdate: (d) => setState(() => _setCross(d.localPosition)),
            onDoubleTap: () {
              setState(() => _setCross(null));
              _goHome(resetZoom: true);
            },
            child: CustomPaint(
              size: Size.infinite,
              painter: _Painter(widget.candles, widget.signal, widget.forecast,
                  widget.sym, widget.tf, visible, shift, cross, widget.layers, yZoom,
                  DateTime.now().toUtc(), widget.algo,
                  widget.repaint == null ? _smTick : Listenable.merge([widget.repaint, _smTick]), widget.alka, widget.allR, widget.zero, widget.mpR, widget.smR, widget.kmR, widget.dmR, widget.stR, widget.starR, widget.ltR, _sm, widget.pqR, widget.kingR, widget.akR, widget.qR, widget.mtfR, widget.fastR, widget.fzR, widget.voteR),
            ),
          ),
        ),
        // زر الرجوع لآخر سعر عند التمرير للخلف
        if (shift > 4)
          Positioned(
            right: _Painter.axisW + 8,
            bottom: _Painter.timeH + 8,
            child: Material(
              color: AppColors.card.withOpacity(0.92),
              shape: const StadiumBorder(side: BorderSide(color: AppColors.border)),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => _goHome(),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('آخر سعر', style: TextStyle(color: AppColors.text, fontSize: 11)),
                    SizedBox(width: 4),
                    Icon(Icons.keyboard_double_arrow_right, size: 16, color: AppColors.accent),
                  ]),
                ),
              ),
            ),
          ),
        // الضغط مطولاً يُبقي المؤشر ظاهراً؛ زر لإخفائه
        if (cross != null)
          Positioned(
            left: 6,
            bottom: _Painter.timeH + 8,
            child: Material(
              color: AppColors.card.withOpacity(0.92),
              shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => setState(() => _setCross(null)),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.close, size: 16, color: AppColors.muted),
                ),
              ),
            ),
          ),
      ]);
    });
  }
}

class _Painter extends CustomPainter {
  static const axisW = 62.0, timeH = 20.0;
  final List<Candle> c;
  final TradeSignal? s;
  final Forecast? f;
  final MarketSymbol sym;
  final String tf;
  final double visible, shift;
  final Offset? cross;
  final ChartLayers L;
  final double yZoom;
  final DateTime now;
  final AlgoResult? al;
  final AlkaResult? ak;
  final AllResult? ar;
  final ZeroResult? zr;
  final AllResult? mr;
  final AllResult? smr;
  final AllResult? kmr;
  final AllResult? dmr;
  final StResult? str;
  final StarResult? starr;
  final AllResult? ltr;
  final _Smooth? sm;
  final AllResult? pqr;
  final AllResult? akr;
  final QResult? qr;
  final KingResult? kingr;
  final AllResult? mtfr;
  final AllResult? fastr;
  final FzResult? fzr;
  final AllResult? voter;
  _Painter(this.c, this.s, this.f, this.sym, this.tf, this.visible, this.shift,
      this.cross, this.L, this.yZoom, this.now, this.al, Listenable? repaint, [this.ak, this.ar, this.zr, this.mr, this.smr, this.kmr, this.dmr, this.str, this.starr, this.ltr, this.sm, this.pqr, this.kingr, this.akr, this.qr, this.mtfr, this.fastr, this.fzr, this.voter])
      : super(repaint: repaint);

  // يبقى التلوين ثابتاً لحظة فتح شمعة جديدة قبل وصول التحليل التالي
  bool get _algoOn =>
      L.algo && al != null && al!.trend.length <= c.length && al!.trend.length >= c.length - 3;

  // ألوان AAB Algo حسب الاتجاه وقوته
  static const _algoUp = [Color(0xFF2E7D6B), Color(0xFF16C784), Color(0xFF00E676)];
  static const _algoDn = [Color(0xFF8E3B46), Color(0xFFEA3943), Color(0xFFFF1744)];

  static const _up = AppColors.up, _down = AppColors.down;

  /// علامات النجوم: «ضغط» و«قاع أعلى»/«قمة أدنى» و«+» للإشارة الإضافية
  String _starTag(StarResult r, int i, int d, bool extra) => [
        if (r.isHot(i, d)) 'ضغط',
        if (r.isHeld(i, d)) d > 0 ? 'قاع أعلى' : 'قمة أدنى',
        if (r.isNear(i, d)) 'ممتاز',
        if (extra) '+',
      ].join(' ');

  void _txt(Canvas cv, String t, Offset o,
      {Color color = AppColors.muted, double size = 10, Color? bg, bool bold = false,
      bool rtl = false, bool endAt = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: t,
          style: TextStyle(
              fontFamily: chartFont,
              color: color,
              fontSize: size,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
    )..layout();
    if (endAt) o = Offset(o.dx - tp.width, o.dy); // o = نهاية النص (يمينه)
    if (bg != null) {
      cv.drawRect(Rect.fromLTWH(o.dx - 2, o.dy - 1, tp.width + 4, tp.height + 2),
          Paint()..color = bg);
    }
    tp.paint(cv, o);
  }

  void _dashed(Canvas cv, double x1, double x2, double y, Paint p,
      {double dash = 5, double gap = 4}) {
    var x = x1;
    while (x < x2) {
      cv.drawLine(Offset(x, y), Offset(math.min(x + dash, x2), y), p);
      x += dash + gap;
    }
  }

  int _idxOf(int ts) {
    var lo = 0, hi = c.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (c[mid].ts < ts) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  String _time(DateTime t) {
    if (tf == '1d') return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  /// لافتات على محور السعر (دخول/وقف/هدف) تُرسم في النهاية بدون تداخل.
  final _axis = <(double, String, String, Color)>[];

  @override
  void paint(Canvas canvas, Size size) {
    _axis.clear();
    sm?.moving = false;
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.bg);
    final n = c.length;
    if (n < 2) {
      _txt(canvas, 'جاري تحميل البيانات…', Offset(size.width / 2 - 55, size.height / 2),
          size: 12);
      return;
    }
    final fullH = size.height - timeH;
    final subH = L.sub == 'none' ? 0.0 : math.max(50.0, fullH * 0.16);
    final w = size.width - axisW, h = fullH - subH;
    final rightIdx = n - 1 - shift;
    final leftIdx = rightIdx - visible + 1;
    final barW = w / visible;
    double xOf(double i) => (i - leftIdx + 0.5) * barW;
    final i0 = math.max(0, leftIdx.floor()), i1 = math.min(n - 1, rightIdx.ceil());
    if (i0 > i1) return;

    // الشموع المعروضة: عادية أو Heikin Ashi
    final k = L.type == 'ha' ? _heikin() : c;

    double hi = -double.infinity, lo = double.infinity;
    for (var i = i0; i <= i1; i++) {
      hi = math.max(hi, k[i].high);
      lo = math.min(lo, k[i].low);
    }
    if (!(hi > lo)) hi = lo + 1;
    final hasVol = L.vol && c.sublist(i0, i1 + 1).any((e) => e.volume > 0);
    final pad = (hi - lo) * 0.08;
    hi += pad;
    lo -= pad * (hasVol ? 2.5 : 1); // مساحة لأعمدة الحجم
    if (yZoom != 1) {
      final mid = (hi + lo) / 2, half = (hi - lo) / 2 * yZoom;
      hi = mid + half;
      lo = mid - half;
    }
    // حركة ناعمة لمدى السعر: يتجه للهدف تدريجياً بدل القفز أثناء التمرير والتكبير
    final smo = sm;
    if (smo != null) {
      final key = '${sym.code}|$tf|${L.type}|${L.sub}|${L.vol}';
      if (smo.key != key || smo.hi.isNaN || cross != null) {
        smo
          ..key = key
          ..hi = hi
          ..lo = lo;
      } else {
        final eps = (hi - lo) * 0.0015;
        final dh = hi - smo.hi, dl = lo - smo.lo;
        if (dh.abs() > eps || dl.abs() > eps) {
          smo.hi += dh * 0.32;
          smo.lo += dl * 0.32;
          smo.moving = true;
          smo.onMove?.call();
        } else {
          smo.hi = hi;
          smo.lo = lo;
        }
        hi = smo.hi;
        lo = smo.lo;
      }
    }
    double yOf(double p) => h * (hi - p) / (hi - lo);
    bool inY(double p) => p <= hi && p >= lo;

    // خلفية بتدرج خفيف جداً
    canvas.drawRect(
        Rect.fromLTWH(0, 0, w, fullH),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF111117), AppColors.bg],
          ).createShader(Rect.fromLTWH(0, 0, w, fullH)));
    // ── علامة مائية
    _txt(canvas, '${sym.code}  ${tf.toUpperCase()}', Offset(w / 2 - 70, h / 2 - 16),
        color: AppColors.accent.withOpacity(0.045), size: 26, bold: true);

    // ── شبكة + محور السعر بخطوات منتظمة
    // شبكة أهدأ
    final gridP = Paint()
      ..color = AppColors.border.withOpacity(0.28)
      ..strokeWidth = 0.7;
    final step = _niceStep((hi - lo) / 7);
    // لا نكتب رقم المحور تحت لافتة السعر الحالي والعدّاد (حتى لا يتداخلا)
    final lastPy = yOf(c.last.close).clamp(0.0, h - 26).toDouble();
    for (var p = (lo / step).ceil() * step; p <= hi; p += step) {
      final y = yOf(p);
      canvas.drawLine(Offset(0, y), Offset(w, y), gridP);
      if (y > lastPy - 16 && y < lastPy + 26) continue;
      if (y < 16) continue; // تحت شريط الأسعار العلوي
      _txt(canvas, sym.fmt(p), Offset(w + 4, y - 6));
    }
    // خطوط زمنية عمودية + محور الوقت
    final tStep = math.max(1, (75 / barW).ceil());
    DateTime? prevLabel;
    for (var i = i0; i <= i1; i++) {
      if (i % tStep != 0) continue;
      final x = xOf(i.toDouble());
      canvas.drawLine(Offset(x, 0), Offset(x, fullH), gridP);
      final t = c[i].time;
      final newDay = prevLabel != null && prevLabel.day != t.day;
      _txt(canvas, newDay && tf != '1d' ? _date(t) : _time(t), Offset(x - 14, fullH + 4),
          color: newDay ? AppColors.text : AppColors.muted, bold: newDay);
      prevLabel = t;
    }
    // فاصل الأيام (على الفريمات اليومية الداخلية): خط متقطع خفيف عند بداية كل يوم
    if (tf != '1d' && tf != '4h') {
      final sepP = Paint()
        ..color = AppColors.gold.withOpacity(0.16)
        ..strokeWidth = 1;
      for (var i = math.max(i0, 1); i <= i1; i++) {
        if (c[i].time.day == c[i - 1].time.day) continue;
        final x = xOf(i - 0.5);
        for (var y = 0.0; y < fullH; y += 8) {
          canvas.drawLine(Offset(x, y), Offset(x, math.min(y + 4, fullH)), sepP);
        }
      }
    }
    canvas.drawLine(Offset(w, 0), Offset(w, fullH), Paint()..color = AppColors.border);
    if (subH > 0) {
      canvas.drawLine(Offset(0, h), Offset(size.width, h), Paint()..color = AppColors.border);
    }

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w, h));

    // ── أعمدة الحجم (أسفل منطقة السعر)
    if (hasVol) {
      double maxV = 0;
      for (var i = i0; i <= i1; i++) {
        maxV = math.max(maxV, c[i].volume);
      }
      final vw = math.max(1.0, barW * 0.7);
      for (var i = i0; i <= i1 && maxV > 0; i++) {
        final x = xOf(i.toDouble());
        final vh = h * 0.16 * c[i].volume / maxV;
        canvas.drawRRect(
            RRect.fromRectAndCorners(Rect.fromLTRB(x - vw / 2, h - vh, x + vw / 2, h),
                topLeft: const Radius.circular(1.5), topRight: const Radius.circular(1.5)),
            Paint()..color = (c[i].close >= c[i].open ? _up : _down).withOpacity(0.22));
      }
    }

    // ── volume profile histogram (right side)
    if (L.vp && s != null && s!.vpBins.isNotEmpty) {
      double maxW = 0;
      for (final b in s!.vpBins) {
        maxW = math.max(maxW, b.w);
      }
      for (final b in s!.vpBins) {
        if (b.hi < lo || b.lo > hi || maxW <= 0) continue;
        final y1 = yOf(math.min(b.hi, hi)), y2 = yOf(math.max(b.lo, lo));
        final bw = w * 0.20 * b.w / maxW;
        final isPoc = !s!.poc.isNaN && s!.poc >= b.lo && s!.poc <= b.hi;
        canvas.drawRect(
          Rect.fromLTRB(w - bw, y1 + 0.5, w, y2 - 0.5),
          Paint()
            ..color = const Color(0xFFA06BFF).withOpacity(isPoc ? 0.55 : 0.25),
        );
      }
    }

    // ── zones (OB / FVG / S&R / EQH-EQL)
    if (L.zones && s != null) {
      for (final z in s!.zones) {
        if (z.top < lo || z.bottom > hi) continue;
        final idx = _idxOf(z.t1);
        final x1 = math.max(0.0, xOf(idx.toDouble()) - barW / 2);
        if (x1 > w) continue;
        Color col;
        if (z.kind == 'FVG') {
          col = AppColors.gold;
        } else if (z.kind == 'SR') {
          col = z.bias > 0 ? AppColors.accent : const Color(0xFFFF7850);
        } else if (z.kind == 'EQH' || z.kind == 'EQL') {
          col = const Color(0xFFC8C8DC);
        } else {
          col = z.bias > 0 ? _up : _down;
        }
        final y1 = yOf(z.top), y2 = yOf(z.bottom);
        final r = Rect.fromLTRB(x1, y1, w, math.max(y2, y1 + 2));
        canvas.drawRect(r, Paint()..color = col.withOpacity(0.16));
        canvas.drawRect(
            r,
            Paint()
              ..color = col.withOpacity(0.7)
              ..style = PaintingStyle.stroke);
        _txt(canvas, z.label, Offset(x1 + 4, y1 + 1), color: col, size: 9);
      }
    }

    // ── Fibonacci
    if (L.fib && s != null && s!.fibs.isNotEmpty) {
      double? p618, p786;
      for (final f in s!.fibs) {
        if (f.ratio == 0.618) p618 = f.price;
        if (f.ratio == 0.786) p786 = f.price;
      }
      if (p618 != null && p786 != null) {
        final y1 = yOf(math.max(p618, p786)), y2 = yOf(math.min(p618, p786));
        canvas.drawRect(Rect.fromLTRB(0, y1, w, y2),
            Paint()..color = AppColors.gold.withOpacity(0.08));
      }
      for (final f in s!.fibs) {
        if (!inY(f.price)) continue;
        final y = yOf(f.price);
        final key = f.ratio == 0.5 || f.ratio == 0.618 || f.ratio == 0.786;
        _dashed(
            canvas,
            0,
            w,
            y,
            Paint()
              ..color = AppColors.gold.withOpacity(key ? 0.8 : 0.4)
              ..strokeWidth = key ? 1.2 : 0.8);
        _txt(canvas, 'Fib ${f.ratio}  ${sym.fmt(f.price)}', Offset(4, y - 11),
            color: AppColors.gold.withOpacity(0.9), size: 9);
      }
    }

    // ── الدعم والمقاومة (المقاومة العليا والدعم السفلي أوضح، وتظهر على حافة الشارت لو خارج المدى)
    if (L.sr && c.length >= 40) {
      for (final l in srLevels(c)) {
        final col = l.resistance ? _down : _up;
        final name = l.major ? (l.resistance ? 'مقاومة عليا' : 'دعم سفلي') : (l.resistance ? 'مقاومة' : 'دعم');
        final label = '$name ${sym.fmt(l.price)}${l.touches > 1 ? '  ×${l.touches}' : ''}';
        if (!inY(l.price)) {
          if (!l.major) continue;
          // خارج المدى المرئي: علامة على الحافة
          final above = l.price > hi;
          final yy = above ? 50.0 : h - 20;
          _txt(canvas, '$label (${above ? 'فوق' : 'تحت'} الشاشة)', Offset(w - 72, yy), color: col, size: 10, bold: true, rtl: true, bg: Colors.black87, endAt: true);
          continue;
        }
        final yT = yOf(l.hi), yB = yOf(l.lo);
        canvas.drawRect(Rect.fromLTRB(0, math.min(yT, yB) - 1.5, w, math.max(yT, yB) + 1.5),
            Paint()..color = col.withOpacity(l.major ? 0.22 : 0.08 + 0.03 * math.min(3, l.touches - 1)));
        final y = yOf(l.price);
        canvas.drawLine(Offset(0, y), Offset(w, y), Paint()
          ..color = col.withOpacity(l.major ? 1 : 0.6)
          ..strokeWidth = l.major ? 2.2 : (l.touches >= 3 ? 1.3 : 0.9));
        _txt(canvas, label, Offset(w - 72, y - (l.major ? 15 : 13)),
            color: col, size: l.major ? 11 : 9.5, bold: true, rtl: true, bg: Colors.black54, endAt: true);
      }
    }

    // ── key levels (PDH/PDL, Asia, London, POC, VWAP ...)
    if (L.levels && s != null) {
      for (final k in s!.keyLevels) {
        if (k.kind == 'vwap' || !inY(k.price)) continue;
        final col = k.kind == 'vp'
            ? const Color(0xFFA06BFF)
            : k.kind == 'session'
                ? const Color(0xFF4FC3F7)
                : AppColors.muted;
        final y = yOf(k.price);
        _dashed(canvas, 0, w, y, Paint()
          ..color = col.withOpacity(0.8)
          ..strokeWidth = 1, dash: 2, gap: 3);
        _txt(canvas, k.name, Offset(w - 62, y - 11), color: col, size: 9);
      }
    }

    // ── VWAP
    if (L.vwap && s != null && s!.vwap.isNotEmpty) {
      final path = Path();
      var open = false;
      for (var i = i0; i <= i1 && i < s!.vwap.length; i++) {
        final v = s!.vwap[i];
        if (v.isNaN) {
          open = false;
          continue;
        }
        final o = Offset(xOf(i.toDouble()), yOf(v));
        if (open) {
          path.lineTo(o.dx, o.dy);
        } else {
          path.moveTo(o.dx, o.dy);
          open = true;
        }
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xFFFFD54F)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6);
    }

    // ── Chandelier Exit lines
    if (L.ce && s != null) {
      void line(List<double> arr, Color col) {
        final path = Path();
        var open = false;
        for (var i = i0; i <= i1 && i < arr.length; i++) {
          final v = arr[i];
          if (v.isNaN) {
            open = false;
            continue;
          }
          final o = Offset(xOf(i.toDouble()), yOf(v));
          if (open) {
            path.lineTo(o.dx, o.dy);
          } else {
            path.moveTo(o.dx, o.dy);
            open = true;
          }
        }
        canvas.drawPath(
            path,
            Paint()
              ..color = col
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);
      }

      line(s!.ceLong, _up);
      line(s!.ceShort, _down);
    }

    // ── EMA 20 / 50 / 200
    if (L.ema && f != null) {
      void ln(List<double> arr, Color col, double sw) {
        final path = Path();
        var open = false;
        for (var i = i0; i <= i1 && i < arr.length; i++) {
          final v = arr[i];
          if (v.isNaN) {
            open = false;
            continue;
          }
          final o = Offset(xOf(i.toDouble()), yOf(v));
          if (open) {
            path.lineTo(o.dx, o.dy);
          } else {
            path.moveTo(o.dx, o.dy);
            open = true;
          }
        }
        canvas.drawPath(
            path,
            Paint()
              ..color = col
              ..style = PaintingStyle.stroke
              ..strokeWidth = sw);
      }

      ln(f!.ema20, const Color(0xFF4FC3F7), 1.2);
      ln(f!.ema50, const Color(0xFFFFB74D), 1.4);
      ln(f!.ema200, const Color(0xFFE040FB), 1.6);
    }

    // ── شريط SM (8 متوسطات): أخضر صاعد، أحمر هابط، رمادي متشابك
    if (L.sm || L.km) {
      final rib = smRibbon(c);
      final rd = smDirFast(rib, n);
      Color col(int i) => rd[i] > 0
          ? const Color(0xFF00C853)
          : rd[i] < 0
              ? const Color(0xFFFF1744)
              : AppColors.muted;
      for (var i = math.max(i0, 1); i <= i1; i++) {
        final top = rib.first[i], bot = rib.last[i], top0 = rib.first[i - 1], bot0 = rib.last[i - 1];
        if (top.isNaN || bot.isNaN || top0.isNaN || bot0.isNaN) continue;
        final x0 = xOf(i - 1.0), x1 = xOf(i.toDouble());
        final fill = Path()
          ..moveTo(x0, yOf(top0))
          ..lineTo(x1, yOf(top))
          ..lineTo(x1, yOf(bot))
          ..lineTo(x0, yOf(bot0))
          ..close();
        canvas.drawPath(fill, Paint()..color = col(i).withOpacity(0.10));
        // بداية لون جديد للشريط (أخضر بعد أحمر أو العكس، متجاهلين الرمادي بينهما)
        if (rd[i] != 0 && rd[i - 1] != rd[i]) {
          var prev = 0;
          for (var q = i - 1; q >= 0 && q >= i - 300; q--) {
            if (rd[q] != 0) {
              prev = rd[q];
              break;
            }
          }
          if (prev == -rd[i]) {
            final up = rd[i] > 0;
            final cc = up ? const Color(0xFF00C853) : const Color(0xFFFF1744);
            final yy = up ? yOf(math.min(bot, c[i].low)) + 10 : yOf(math.max(top, c[i].high)) - 10;
            final tri = Path();
            if (up) {
              tri..moveTo(x1, yy)..lineTo(x1 - 6, yy + 9)..lineTo(x1 + 6, yy + 9)..close();
            } else {
              tri..moveTo(x1, yy)..lineTo(x1 - 6, yy - 9)..lineTo(x1 + 6, yy - 9)..close();
            }
            canvas.drawPath(tri, Paint()..color = cc);
            final tp = TextPainter(
                text: TextSpan(
                    text: up ? 'بداية صعود' : 'بداية هبوط',
                    style: TextStyle(fontFamily: chartFont, color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                textDirection: TextDirection.rtl)
              ..layout();
            final ty = up ? yy + 11 : yy - 11 - tp.height - 2;
            final tx = (x1 - tp.width / 2).clamp(4.0, math.max(4.0, w - tp.width - 4)).toDouble();
            canvas.drawRRect(
                RRect.fromRectAndRadius(Rect.fromLTWH(tx - 4, ty, tp.width + 8, tp.height + 2), const Radius.circular(4)),
                Paint()..color = cc.withOpacity(0.85));
            tp.paint(canvas, Offset(tx, ty + 1));
          }
        }
        for (final r in rib) {
          if (r[i].isNaN || r[i - 1].isNaN) continue;
          canvas.drawLine(Offset(x0, yOf(r[i - 1])), Offset(x1, yOf(r[i])),
              Paint()
                ..color = col(i).withOpacity(0.55)
                ..strokeWidth = 1);
        }
      }
    }

    // ── AAB Algo: مناطق الانعكاس + خط الاتجاه
    if (_algoOn) {
      final a = al!;
      final zp = Paint()
        ..color = AppColors.accent.withOpacity(0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      for (final z in [a.zoneHi, a.zoneLo]) {
        final p = Path();
        var open = false;
        for (var i = i0; i <= i1 && i < z.length; i++) {
          if (z[i].isNaN) {
            open = false;
            continue;
          }
          final o = Offset(xOf(i.toDouble()), yOf(z[i]));
          open ? p.lineTo(o.dx, o.dy) : p.moveTo(o.dx, o.dy);
          open = true;
        }
        canvas.drawPath(p, zp);
      }
      // خط الاتجاه بلون الاتجاه + تظليل خفيف بينه وبين السعر
      for (var i = math.max(i0, 1); i <= i1 && i < a.line.length; i++) {
        final l0 = a.line[i - 1], l1 = a.line[i];
        if (l0.isNaN || l1.isNaN || a.trend[i] != a.trend[i - 1]) continue;
        final col = a.trend[i] > 0 ? _up : _down;
        final x0 = xOf(i - 1.0), x1 = xOf(i.toDouble());
        final fill = Path()
          ..moveTo(x0, yOf(l0))
          ..lineTo(x1, yOf(l1))
          ..lineTo(x1, yOf(c[i].close))
          ..lineTo(x0, yOf(c[i - 1].close))
          ..close();
        canvas.drawPath(fill, Paint()..color = col.withOpacity(0.07));
        canvas.drawLine(Offset(x0, yOf(l0)), Offset(x1, yOf(l1)),
            Paint()
              ..color = col
              ..strokeWidth = 2.2
              ..strokeCap = StrokeCap.round);
      }
    }

    // ── السعر: شموع / Heikin Ashi / خطي
    if (L.type == 'line') {
      final path = Path(), area = Path();
      for (var i = i0; i <= i1; i++) {
        final o = Offset(xOf(i.toDouble()), yOf(c[i].close));
        if (i == i0) {
          path.moveTo(o.dx, o.dy);
          area.moveTo(o.dx, h);
          area.lineTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
          area.lineTo(o.dx, o.dy);
        }
      }
      area.lineTo(xOf(i1.toDouble()), h);
      area.close();
      canvas.drawPath(
          area,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.accent.withOpacity(0.28), AppColors.accent.withOpacity(0)],
            ).createShader(Rect.fromLTWH(0, 0, w, h)));
      canvas.drawPath(
          path,
          Paint()
            ..color = AppColors.accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8);
    } else {
      final bodyW = math.max(1.0, barW * 0.72);
      final upP = Paint()..color = _up, dnP = Paint()..color = _down;
      final wickUp = Paint()
        ..color = _up
        ..strokeWidth = math.max(1.0, barW * 0.08);
      final wickDn = Paint()
        ..color = _down
        ..strokeWidth = math.max(1.0, barW * 0.08);
      // الشمعة الحية: الإغلاق يتحرك بنعومة نحو السعر الجديد
      var liveClose = k[n - 1].close;
      final smo2 = sm;
      if (smo2 != null && L.type == 'candle' && i1 == n - 1) {
        final ts = k[n - 1].time.millisecondsSinceEpoch;
        if (smo2.closeTs != ts || smo2.close.isNaN) {
          smo2
            ..closeTs = ts
            ..close = liveClose;
        } else {
          final d = liveClose - smo2.close;
          final a = (k[n - 1].high - k[n - 1].low).abs();
          if (d.abs() > math.max(1e-9, a * 0.01)) {
            smo2.close += d * 0.3;
            smo2.moving = true;
            smo2.onMove?.call();
          } else {
            smo2.close = liveClose;
          }
          liveClose = smo2.close;
        }
      }
      for (var i = i0; i <= i1; i++) {
        final q0 = k[i];
        final q = i == n - 1 && liveClose != q0.close
            ? Candle(q0.time, q0.open, q0.high, q0.low, liveClose, q0.volume)
            : q0;
        final x = xOf(i.toDouble());
        final bull = q.close >= q.open;
        if (_algoOn && i < al!.trend.length && al!.trend[i] != 0) {
          // تلوين AAB Algo: لون الاتجاه ودرجته حسب قوته
          final col = (al!.trend[i] > 0 ? _algoUp : _algoDn)[al!.power[i]];
          final fill = Paint()..color = bull ? col : col.withOpacity(0.55);
          canvas.drawLine(Offset(x, yOf(q.high)), Offset(x, yOf(q.low)),
              Paint()
                ..color = col
                ..strokeWidth = math.max(1.0, barW * 0.08));
          final yo = yOf(q.open), yc = yOf(q.close);
          final top = math.min(yo, yc), bot = math.max(yo, yc);
          canvas.drawRect(
              Rect.fromLTRB(x - bodyW / 2, top, x + bodyW / 2, math.max(bot, top + 1)), fill);
          continue;
        }
        canvas.drawLine(Offset(x, yOf(q.high)), Offset(x, yOf(q.low)), bull ? wickUp : wickDn);
        final yo = yOf(q.open), yc = yOf(q.close);
        final top = math.min(yo, yc), bot = math.max(yo, yc);
        final r = Rect.fromLTRB(x - bodyW / 2, top, x + bodyW / 2, math.max(bot, top + 1));
        if (barW >= 6) {
          canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(1.2)), bull ? upP : dnP);
        } else {
          canvas.drawRect(r, bull ? upP : dnP);
        }
      }
    }

    // ── أعلى وأدنى سعر في المدى الظاهر (مثل TradingView)
    if (L.type != 'line' && i1 > i0 + 5) {
      var hiI = i0, loI = i0;
      for (var i = i0; i <= i1; i++) {
        if (k[i].high > k[hiI].high) hiI = i;
        if (k[i].low < k[loI].low) loI = i;
      }
      void mark(int i, double p, bool top) {
        final x = xOf(i.toDouble()), y = yOf(p);
        final left = x > w * 0.6; // قرب الحافة اليمنى: النص على اليسار
        final tp = TextPainter(
          text: TextSpan(
              text: sym.fmt(p),
              style: TextStyle(fontFamily: chartFont, color: AppColors.text.withOpacity(0.85), fontSize: 9.5, fontWeight: FontWeight.w700)),
          textDirection: TextDirection.ltr,
        )..layout();
        final x2 = left ? x - 16 : x + 16;
        // لا يختبئ تحت سطر الأسعار والدقة أعلى الشارت
        final ty = math.max(58.0, y - tp.height / 2 + (top ? -2 : 2));
        canvas.drawLine(Offset(x + (left ? -2 : 2), y), Offset(x2, ty + tp.height / 2),
            Paint()
              ..color = AppColors.text.withOpacity(0.5)
              ..strokeWidth = 0.8);
        tp.paint(canvas, Offset(left ? x2 - tp.width - 2 : x2 + 2, ty));
      }

      mark(hiI, k[hiI].high, true);
      mark(loI, k[loI].low, false);
    }

    // ── markers (CE flips, sweeps, S/R breaks) — من المحرك القديم، تُخفى مع المحرك الجديد
    if (s != null && f == null) {
      for (final m in s!.marks) {
        final idx = _idxOf(m.ts);
        if (idx < i0 || idx > i1 || c[idx].ts != m.ts) continue;
        final x = xOf(idx.toDouble());
        final col = m.bias > 0 ? _up : _down;
        final path = Path();
        if (m.bias > 0) {
          final y = yOf(c[idx].low) + 5;
          path
            ..moveTo(x, y)
            ..lineTo(x - 5, y + 9)
            ..lineTo(x + 5, y + 9)
            ..close();
          canvas.drawPath(path, Paint()..color = col);
          _txt(canvas, m.text, Offset(x - 10, y + 10), color: col, size: 8, bold: true);
        } else {
          final y = yOf(c[idx].high) - 5;
          path
            ..moveTo(x, y)
            ..lineTo(x - 5, y - 9)
            ..lineTo(x + 5, y - 9)
            ..close();
          canvas.drawPath(path, Paint()..color = col);
          _txt(canvas, m.text, Offset(x - 10, y - 20), color: col, size: 8, bold: true);
        }
      }
    }

    if (f != null) _paintForecast(canvas, w, h, barW, xOf, yOf, inY, i0, i1);
    if (L.alka && ak != null) {
      _paintTagged(canvas, w, barW, xOf, yOf, inY, i0, i1, ak!.signals, ak!.pending, 'Alka', null);
    }
    if (L.all && ar != null) {
      _paintTagged(canvas, w, barW, xOf, yOf, inY, i0, i1, ar!.signals, ar!.pending, 'ALL', AppColors.gold);
    }
    // صندوق صفقة SM المفتوحة (مثل DTC): أحمر للوقف، أخضر للأهداف
    // ── Mp / SM / KM / DM: نفس الإشارات بعد فلترة → علامة واحدة مشتركة على كل شمعة تذكر كل
    // المؤشرات المتفقة (مثل "Mp·SM·KM شراء") بدل رسمها فوق بعض. الترتيب من الأدق للأعم.
    final groups = <(String, AllResult)>[
      if (L.km && kmr != null) ('KM', kmr!),
      if (L.dm && dmr != null) ('DM', dmr!),
      if (L.st && str != null) ('ST', str!.res),
      if (L.sm && smr != null) ('SM', smr!),
      if (L.mp && mr != null) ('Mp', mr!),
    ];
    if (groups.isNotEmpty) {
      final bySig = <(int, int), (PastSignal, String, List<String>)>{};
      final byPend = <(int, int), (PendingSetup, String, List<String>)>{};
      for (final (tag, r) in groups) {
        for (final (q, sg) in r.signals.indexed) {
          final key = (sg.i, sg.dir);
          final cur = bySig[key];
          if (cur == null) {
            bySig[key] = (sg, q < r.sources.length ? r.sources[q] : '', [tag]);
          } else {
            cur.$3.add(tag);
          }
        }
        for (final (q, p) in r.pending.indexed) {
          final key = (p.i, p.dir);
          final cur = byPend[key];
          if (cur == null) {
            byPend[key] = (p, q < r.pendingSrc.length ? r.pendingSrc[q] : '', [tag]);
          } else {
            cur.$3.add(tag);
          }
        }
      }
      // ترتيب العلامات داخل الاسم من الأعم للأدق: Mp·SM·KM
      const order = ['Mp', 'SM', 'ST', 'DM', 'KM'];
      // ST يُظهر درجة ثقته بعد الأسماء (مثل "Mp·ST 58%")
      String nameOf(List<String> t, int i) {
        final j = (List.of(t)..sort((x, y) => order.indexOf(x).compareTo(order.indexOf(y)))).join('·');
        final cf = t.contains('ST') ? str?.conf[i] : null;
        return cf == null ? j : '$j ${(cf * 100).round()}%';
      }
      final keys = bySig.keys.toList()..sort((x, y) => x.$1.compareTo(y.$1));
      final sigs = [for (final k in keys) bySig[k]!.$1];
      final srcs = [for (final k in keys) bySig[k]!.$2];
      // إشارة SM القوية (شريط عريض، أو قاع أعلى، أو ضغط): ~61% بدل ~56%
      final smRib = L.sm && starr != null ? smRibbon(c) : null;
      final smAt = smRib == null ? null : atr(c, 14);
      bool strong(int i, int d, List<String> tags) =>
          smRib != null && tags.contains('SM') && smStrong(c, smRib, smAt!, starr!, i, d);
      final names = [
        for (final k in keys)
          '${(mr?.extra.contains(k.$1) ?? false) ? '+ ' : ''}${nameOf(bySig[k]!.$3, k.$1)}${strong(k.$1, k.$2, bySig[k]!.$3) ? ' قوي' : ''}'
      ];
      final pk = byPend.keys.toList();
      final pends = [for (final k in pk) byPend[k]!.$1];
      final pSrcs = [for (final k in pk) byPend[k]!.$2];
      final pNames = [for (final k in pk) nameOf(byPend[k]!.$3, k.$1)];
      // صندوق الصفقة المفتوحة (مرة واحدة)
      for (final sg in sigs.where((x) => x.exitI < 0 && (L.sm || L.km || L.dm || L.st))) {
        final x0 = math.max(0.0, math.min(xOf(sg.i.toDouble()), w - 110));
        if (x0 < w) {
          final st = sg.curStop.isNaN ? sg.sl : sg.curStop;
          final yE = yOf(sg.entry), yS = yOf(st), yT = yOf(sg.tp2);
          canvas.drawRect(Rect.fromLTRB(x0, math.min(yE, yS), w, math.max(yE, yS)),
              Paint()..color = _down.withOpacity(0.13));
          canvas.drawRect(Rect.fromLTRB(x0, math.min(yE, yT), w, math.max(yE, yT)),
              Paint()..color = _up.withOpacity(0.11));
        }
      }
      _paintTagged(canvas, w, barW, xOf, yOf, inY, i0, i1, sigs, pends, groups.first.$1, AppColors.gold,
          sources: srcs, pendingSrc: pSrcs, tagPer: names, pendTagPer: pNames);
    }
    if (L.star && starr != null) {
      final r = starr!.res;
      _paintTagged(canvas, w, barW, xOf, yOf, inY, i0, i1, r.signals, r.pending, 'نجوم', AppColors.gold,
          sources: r.sources,
          pendingSrc: r.pendingSrc,
          tagPer: [for (final sg in r.signals) _starTag(starr!, sg.i, sg.dir, (mr?.extra.contains(sg.i) ?? false))],
          pendTagPer: [for (final p in r.pending) '${_starTag(starr!, p.i, p.dir, false)} نجوم ${starr!.of(p.i, p.dir)}'.trim()],
          starsPer: [for (final sg in r.signals) starr!.of(sg.i, sg.dir)]);
    }
    // ── King: إشارات أعلى 30% ثقة مع نجوم القوة (⭐ 30% • ⭐⭐ 15% • ⭐⭐⭐ 7%)
    if (L.king && kingr != null) {
      final r = kingr!.res;
      _paintTagged(canvas, w, barW, xOf, yOf, inY, i0, i1, r.signals, r.pending, 'King', AppColors.gold,
          tagPer: List.filled(r.signals.length, 'King'),
          starsPer: [for (final sg in r.signals) math.max(1, kingr!.stars(sg.i, sg.dir))],
          pendTagPer: [for (final p in r.pending) 'King ${'⭐' * math.max(1, kingr!.stars(p.i, p.dir))}']);
    }
    // ── PQ: نفس إشارات النجوم و SM و Alka مجتمعة في مؤشر واحد (أخضر شراء، أحمر بيع)
    if (L.pq && pqr != null) {
      final r = pqr!;
      final smKeys = {for (final x in smr?.signals ?? const <PastSignal>[]) (x.i, x.dir)};
      final stK = starr == null ? const <(int, int)>{} : starr!.stars.keys.toSet();
      bool inStars(PastSignal sg) => stK.contains((sg.i, sg.dir));
      _paintTagged(canvas, w, barW, xOf, yOf, inY, i0, i1, r.signals, r.pending, 'PQ', null,
          tagPer: [
            for (final sg in r.signals)
              'PQ${starr != null && inStars(sg) ? ' ${_starTag(starr!, sg.i, sg.dir, false)}' : ''}${smKeys.contains((sg.i, sg.dir)) ? ' SM' : ''}'.trim()
          ],
          pendTagPer: [for (final _ in r.pending) 'PQ'],
          starsPer: starr == null ? null : [for (final sg in r.signals) inStars(sg) ? starr!.of(sg.i, sg.dir) : -1]);
    }
    // ── King متعدد الفريمات: «شراء» أو «بيع» فقط
    if (L.mtf && mtfr != null) {
      final r = mtfr!;
      _paintTagged(canvas, w, barW, xOf, yOf, inY, i0, i1, r.signals, const [], '', null,
          tagPer: List.filled(r.signals.length, ''),
          starsPer: [for (var q = 0; q < r.signals.length; q++) mtfStarsOf(r, q)]);
    }
    // ── الإجماع: «شراء» أو «بيع» مع نجوم (5 / 6 / 7 مؤشرات متفقة)
    if (L.vote && voter != null) {
      final r = voter!;
      _paintTagged(canvas, w, barW, xOf, yOf, inY, i0, i1, r.signals, const [], '', null,
          tagPer: List.filled(r.signals.length, ''),
          starsPer: [for (var q = 0; q < r.signals.length; q++) voteStarsOf(r, q)]);
    }
    // ── FZ: مناطق الفيبوناتشي — خضراء بعد موجة صاعدة، حمراء بعد موجة هابطة، وخط متقطع عند 0.786
    if (L.fz && fzr != null) {
      final f = fzr!;
      for (final z in f.zones) {
        if (z.to < i0 || z.from > i1) continue;
        final col = z.dir > 0 ? _up : _down;
        final x1 = math.max(0.0, xOf(z.from.toDouble()) - barW / 2);
        final x2 = math.min(w, xOf(z.to.toDouble()) + barW / 2);
        if (x2 <= x1) continue;
        final top = math.max(z.z5, z.z618), bot = math.min(z.z5, z.z618);
        final y1 = yOf(top), y2 = yOf(bot);
        final r = Rect.fromLTRB(x1, y1, x2, math.max(y2, y1 + 2));
        canvas.drawRect(r, Paint()..color = col.withOpacity(0.18));
        canvas.drawRect(r, Paint()
          ..color = col.withOpacity(0.75)
          ..style = PaintingStyle.stroke);
        final y7 = yOf(z.z786);
        for (var x = x1; x < x2; x += 6) {
          canvas.drawLine(Offset(x, y7), Offset(math.min(x + 3, x2), y7), Paint()
            ..color = col.withOpacity(0.6)
            ..strokeWidth = 1);
        }
      }
      _paintTagged(canvas, w, barW, xOf, yOf, inY, i0, i1, f.res.signals, const [], '', null,
          tagPer: List.filled(f.res.signals.length, ''));
    }
    // ── Fast: «شراء» أو «بيع» فقط (النجوم للإشارات الأقوى)
    if (L.fast && fastr != null) {
      final r = fastr!;
      _paintTagged(canvas, w, barW, xOf, yOf, inY, i0, i1, r.signals, const [], '', null,
          tagPer: List.filled(r.signals.length, ''),
          starsPer: [for (var q = 0; q < r.signals.length; q++) mtfStarsOf(r, q)]);
    }
    // ── AK: علامات شراء (أخضر) وبيع (أحمر) — توصيات AAB في أعلى 15% حسب King
    if (L.aiak && akr != null) {
      final r = akr!;
      _paintTagged(canvas, w, barW, xOf, yOf, inY, i0, i1, r.signals, r.pending, 'AK', null,
          tagPer: [for (final _ in r.signals) 'AK'], pendTagPer: [for (final _ in r.pending) 'AK']);
    }
    // ── Q (مبسّط): صندوق «السعر غالباً سيكون هنا» بخطين: أعلى متوقع وأدنى متوقع
    if (L.q && qr != null && qr!.i < n) {
      final q = qr!;
      final x0 = xOf((n - 1).toDouble()) + barW * 0.6;
      final xe = math.min(w - 4, x0 + math.max(barW * qH, 60));
      final top = q.band(3, qH), bot = q.band(1, qH);
      final yT = yOf(top), yB = yOf(bot);
      final gold = AppColors.gold;
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, w, h));
      final box = RRect.fromRectAndRadius(Rect.fromLTRB(x0, yT, xe, yB), const Radius.circular(6));
      canvas.drawRRect(box, Paint()..color = gold.withOpacity(0.12));
      final lp = Paint()
        ..color = gold
        ..strokeWidth = 1.4;
      _dashed(canvas, x0, xe, yT, lp, dash: 5, gap: 3);
      _dashed(canvas, x0, xe, yB, lp, dash: 5, gap: 3);
      // سهم الاتجاه في وسط الصندوق (فقط إذا الميل واضح)
      if (q.leanUp || q.leanDown) {
        final up = q.leanUp;
        final cx = (x0 + xe) / 2, cy = (yT + yB) / 2, s0 = math.min(10.0, (yB - yT) / 4);
        final path = Path()
          ..moveTo(cx, cy + (up ? -s0 : s0))
          ..lineTo(cx - s0, cy + (up ? s0 : -s0) * 0.6)
          ..lineTo(cx + s0, cy + (up ? s0 : -s0) * 0.6)
          ..close();
        canvas.drawPath(path, Paint()..color = (up ? _up : _down).withOpacity(0.85));
      }
      canvas.restore();
      // أسهم Q السابقة على الشموع مع ✓ (صح) أو ✗ (خطأ)
      for (final ar in q.arrows) {
        if (ar.i < i0 || ar.i > i1) continue;
        final x = xOf(ar.i.toDouble());
        final up = ar.dir > 0;
        final y = up ? yOf(c[ar.i].low) + 10 : yOf(c[ar.i].high) - 10;
        final s0 = math.max(4.0, math.min(7.0, barW * 0.45));
        final col = up ? _up : _down;
        final tri = Path()
          ..moveTo(x, up ? y : y)
          ..lineTo(x - s0, up ? y + s0 * 1.4 : y - s0 * 1.4)
          ..lineTo(x + s0, up ? y + s0 * 1.4 : y - s0 * 1.4)
          ..close();
        canvas.drawPath(tri, Paint()..color = col.withOpacity(0.9));
        if (ar.result != 0) {
          final ok = ar.result > 0;
          final cy = up ? y + s0 * 1.4 + 8 : y - s0 * 1.4 - 8;
          final pen = Paint()
            ..color = ok ? _up : _down
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke;
          canvas.drawCircle(Offset(x, cy), 6.5, Paint()..color = AppColors.bg.withOpacity(0.85));
          if (ok) {
            canvas.drawPath(Path()..moveTo(x - 3.5, cy)..lineTo(x - 1, cy + 3)..lineTo(x + 4, cy - 3), pen);
          } else {
            canvas.drawLine(Offset(x - 3, cy - 3), Offset(x + 3, cy + 3), pen);
            canvas.drawLine(Offset(x + 3, cy - 3), Offset(x - 3, cy + 3), pen);
          }
        }
      }
      if (inY(top)) _txt(canvas, 'أعلى متوقع ${sym.fmt(top)}', Offset(math.max(4, xe - 118), yT - 15), color: gold, size: 9, bold: true);
      if (inY(bot)) _txt(canvas, 'أدنى متوقع ${sym.fmt(bot)}', Offset(math.max(4, xe - 118), yB + 3), color: gold, size: 9, bold: true);
    }
    // ── LT بعيد المدى: يُرسم على الفريم اليومي فقط
    if (L.lt && ltr != null && tf == '1d') {
      final r = ltr!;
      _paintTagged(canvas, w, barW, xOf, yOf, inY, i0, i1, r.signals, r.pending, 'LT', const Color(0xFF4FC3F7),
          sources: r.sources, tagPer: [for (final x in r.sources) 'LT $x']);
    }
    if (L.zero && zr != null) {
      _paintTagged(canvas, w, barW, xOf, yOf, inY, i0, i1, zr!.signals, zr!.pending, '0.1', null,
          upCol: zeroUp, downCol: zeroDown, darkText: true);
    }

    // ── trade box (Entry / SL / TP1-3) like the QNA style
    if (f == null && s != null && s!.direction != Direction.neutral) {
      final x0 = math.max(0.0, xOf((n - 1).toDouble()) - barW / 2);
      if (x0 < w) {
        final yE = yOf(s!.entry), yS = yOf(s!.stopLoss), yT = yOf(s!.tp3);
        canvas.drawRect(Rect.fromLTRB(x0, math.min(yE, yT), w, math.max(yE, yT)),
            Paint()..color = _up.withOpacity(0.14));
        canvas.drawRect(Rect.fromLTRB(x0, math.min(yE, yS), w, math.max(yE, yS)),
            Paint()..color = _down.withOpacity(0.16));
        void tag(String name, double p, Color col) {
          if (!inY(p)) return;
          final y = yOf(p);
          canvas.drawLine(Offset(x0, y), Offset(w, y),
              Paint()
                ..color = col
                ..strokeWidth = 1.3);
          _txt(canvas, '$name ${sym.fmt(p)}', Offset(w - 92, y - 12),
              color: Colors.white, size: 9, bg: col.withOpacity(0.85));
        }

        tag('ENTRY', s!.entry, const Color(0xFF9AA5B8));
        tag('SL', s!.stopLoss, _down);
        tag('TP1', s!.tp1, _up);
        tag('TP2', s!.tp2, _up);
        tag('TP3', s!.tp3, _up);
      }
    }

    // ── خط آخر سعر
    final last = c.last.close;
    final lastCol = c.last.close >= c.last.open ? _up : _down;
    if (inY(last)) {
      _dashed(canvas, 0, w, yOf(last), Paint()
        ..color = lastCol.withOpacity(0.75)
        ..strokeWidth = 1, dash: 3, gap: 3);
    }
    canvas.restore();

    // ── اللوحة السفلية (RSI / MACD)
    if (subH > 0) _paintSub(canvas, Rect.fromLTWH(0, h, w, subH), xOf, barW, i0, i1);

    // ── سعر آخر شمعة + العد التنازلي لإغلاقها
    final ly = yOf(last).clamp(0.0, h - 26).toDouble();
    _pill(canvas, sym.fmt(last), Offset(w + 1, ly - 7), lastCol, bold: true);
    final mins = _tfMin[tf];
    if (mins != null) {
      final secs = mins * 60;
      final nowS = now.millisecondsSinceEpoch ~/ 1000;
      var left = (c.last.ts + secs) - nowS;
      if (left < 0 || left > secs) left = secs - (nowS % secs);
      final hh = left ~/ 3600, mm = (left % 3600) ~/ 60, ss = left % 60;
      final t = hh > 0
          ? '$hh:${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}'
          : '${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}';
      _pill(canvas, t, Offset(w + 1, ly + 8), lastCol.withOpacity(0.55));
    }

    _paintAxisTags(canvas, w, h, ly);

    // ── رأس الشارت: OHLC للشمعة الحالية أو التي تحت المؤشر
    int? cIdx;
    double? cx, cy;
    if (cross != null) {
      cIdx = ((cross!.dx.clamp(0.0, w)) / barW + leftIdx - 0.5).round().clamp(i0, i1).toInt();
      cx = xOf(cIdx.toDouble()); // التصاق بمنتصف الشمعة
      cy = cross!.dy.clamp(0.0, fullH).toDouble();
    }
    _header(canvas, cIdx ?? n - 1, w);
    if (f != null) _legend(canvas, w);

    // ── المؤشر المتقاطع
    if (cIdx != null) {
      final cp = Paint()
        ..color = Colors.white54
        ..strokeWidth = 0.8;
      _dashed(canvas, 0, w, cy!, cp, dash: 3, gap: 3);
      var y = 0.0;
      while (y < fullH) {
        canvas.drawLine(Offset(cx!, y), Offset(cx, math.min(y + 3, fullH)), cp);
        y += 6;
      }
      if (cy <= h) {
        final price = hi - cy / h * (hi - lo);
        _pill(canvas, sym.fmt(price), Offset(w + 1, cy - 7), AppColors.accent);
        // نقطة التقاطع + بطاقة صغيرة: البعد عن السعر الحالي (%) وعدد الشموع من الآن
        canvas.drawCircle(Offset(cx!, cy), 6, Paint()..color = AppColors.accent.withOpacity(0.22));
        canvas.drawCircle(Offset(cx, cy), 2.6, Paint()..color = AppColors.accent);
        final last = c[n - 1].close;
        final pct = (price - last) / last * 100;
        final bars = n - 1 - cIdx;
        final txt = '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%${bars > 0 ? '  ·  $bars شمعة' : ''}';
        final tp = TextPainter(
          text: TextSpan(
              text: txt,
              style: TextStyle(
                  fontFamily: chartFont, color: pct >= 0 ? AppColors.up : AppColors.down, fontSize: 10, fontWeight: FontWeight.w700)),
          textDirection: TextDirection.ltr,
        )..layout();
        final bw = tp.width + 12, bh = tp.height + 6;
        var bx = cx + 10;
        if (bx + bw > w - 4) bx = cx - 10 - bw;
        var by = cy - bh - 10;
        if (by < 4) by = cy + 10;
        final r = RRect.fromRectAndRadius(Rect.fromLTWH(bx, by, bw, bh), const Radius.circular(6));
        canvas.drawRRect(r, Paint()..color = AppColors.card.withOpacity(0.94));
        canvas.drawRRect(
            r,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.8
              ..color = AppColors.border);
        tp.paint(canvas, Offset(bx + 6, by + 3));
      }
      final t = c[cIdx].time;
      _pill(canvas, '${_date(t)} ${_time(t)}', Offset(cx! - 34, fullH + 2), AppColors.accent);
    }
  }

  void _pill(Canvas cv, String t, Offset o, Color bg, {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: t,
          style: TextStyle(
              fontFamily: chartFont,
              color: bg.computeLuminance() > 0.35 ? AppColors.onAccent : Colors.white,
              fontSize: 10,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
      textDirection: TextDirection.ltr,
    )..layout();
    cv.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(o.dx, o.dy - 1, tp.width + 8, tp.height + 2), const Radius.circular(3)),
        Paint()..color = bg);
    tp.paint(cv, Offset(o.dx + 4, o.dy));
  }

  String _date(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';

  String _vol(double v) {
    if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(2)}B';
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(2)}M';
    if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  void _header(Canvas cv, int i, double w) {
    final q = c[i];
    final prev = i > 0 ? c[i - 1].close : q.open;
    final ch = prev == 0 ? 0.0 : (q.close - prev) / prev * 100;
    final col = q.close >= q.open ? _up : _down;
    final spans = <TextSpan>[
      const TextSpan(text: 'O ', style: TextStyle(color: AppColors.muted)),
      TextSpan(text: '${sym.fmt(q.open)}  ', style: TextStyle(color: col)),
      const TextSpan(text: 'H ', style: TextStyle(color: AppColors.muted)),
      TextSpan(text: '${sym.fmt(q.high)}  ', style: TextStyle(color: col)),
      const TextSpan(text: 'L ', style: TextStyle(color: AppColors.muted)),
      TextSpan(text: '${sym.fmt(q.low)}  ', style: TextStyle(color: col)),
      const TextSpan(text: 'C ', style: TextStyle(color: AppColors.muted)),
      TextSpan(text: '${sym.fmt(q.close)}  ', style: TextStyle(color: col)),
      TextSpan(
          text: '${ch >= 0 ? '+' : ''}${ch.toStringAsFixed(2)}%',
          style: TextStyle(color: col, fontWeight: FontWeight.w700)),
      if (q.volume > 0)
        TextSpan(text: '   Vol ${_vol(q.volume)}', style: const TextStyle(color: AppColors.muted)),
    ];
    final tp = TextPainter(
      text: TextSpan(style: TextStyle(fontFamily: chartFont, fontSize: 10), children: spans),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: w - 8);
    // شريط كامل بخلفية شبه معتمة حتى لا تغطيه العلامات
    cv.drawRect(Rect.fromLTWH(0, 0, w, tp.height + 7), Paint()..color = AppColors.bg.withOpacity(0.92));
    tp.paint(cv, const Offset(6, 4));
  }

  List<Candle> _heikin() {
    final out = <Candle>[];
    var o = (c[0].open + c[0].close) / 2;
    var cl = (c[0].open + c[0].high + c[0].low + c[0].close) / 4;
    for (var i = 0; i < c.length; i++) {
      final q = c[i];
      if (i > 0) {
        o = (o + cl) / 2;
        cl = (q.open + q.high + q.low + q.close) / 4;
      }
      out.add(Candle(q.time, o, math.max(q.high, math.max(o, cl)),
          math.min(q.low, math.min(o, cl)), cl, q.volume));
    }
    return out;
  }

  void _paintSub(Canvas cv, Rect r, double Function(double) xOf, double barW, int i0, int i1) {
    final cl = c.map((e) => e.close).toList();
    cv.save();
    cv.clipRect(r);
    final gp = Paint()
      ..color = AppColors.muted.withOpacity(0.35)
      ..strokeWidth = 1;
    Path line(List<double> v, double Function(double) y) {
      final p = Path();
      var open = false;
      for (var i = i0; i <= i1; i++) {
        if (v[i].isNaN) {
          open = false;
          continue;
        }
        final o = Offset(xOf(i.toDouble()), y(v[i]));
        if (open) {
          p.lineTo(o.dx, o.dy);
        } else {
          p.moveTo(o.dx, o.dy);
          open = true;
        }
      }
      return p;
    }

    Paint stroke(Color c, [double w = 1.4]) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;
    String label;
    if (L.sub == 'rsi') {
      final v = rsi(cl, 14);
      double y(double x) => r.top + 4 + (r.height - 8) * (100 - x) / 100;
      cv.drawRect(Rect.fromLTRB(r.left, y(70), r.right, y(30)),
          Paint()..color = const Color(0xFF7E57C2).withOpacity(0.10));
      for (final lv in [70.0, 50.0, 30.0]) {
        _dashed(cv, r.left, r.right, y(lv), gp, dash: 3, gap: 4);
      }
      cv.drawPath(line(v, y), stroke(const Color(0xFFB39DDB)));
      final last = v[i1];
      label = 'RSI 14  ${last.isNaN ? '-' : last.toStringAsFixed(1)}';
      cv.restore();
      for (final lv in [70.0, 30.0]) {
        _txt(cv, lv.toStringAsFixed(0), Offset(r.right + 4, y(lv) - 6));
      }
    } else {
      final m = macd(cl);
      var mx = 0.0;
      for (var i = i0; i <= i1; i++) {
        for (final x in [m.line[i], m.signal[i], m.hist[i]]) {
          if (!x.isNaN) mx = math.max(mx, x.abs());
        }
      }
      if (mx == 0) mx = 1;
      double y(double x) => r.center.dy - (r.height / 2 - 6) * x / mx;
      cv.drawLine(Offset(r.left, y(0)), Offset(r.right, y(0)), gp);
      final bw = math.max(1.0, barW * 0.6);
      for (var i = i0; i <= i1; i++) {
        final hv = m.hist[i];
        if (hv.isNaN) continue;
        final grow = i > 0 && !m.hist[i - 1].isNaN && hv.abs() >= m.hist[i - 1].abs();
        final col = hv >= 0 ? _up : _down;
        final x = xOf(i.toDouble());
        cv.drawRect(Rect.fromLTRB(x - bw / 2, math.min(y(0), y(hv)), x + bw / 2, math.max(y(0), y(hv))),
            Paint()..color = col.withOpacity(grow ? 0.75 : 0.35));
      }
      cv.drawPath(line(m.line, y), stroke(const Color(0xFF4FC3F7), 1.3));
      cv.drawPath(line(m.signal, y), stroke(const Color(0xFFFFB74D), 1.3));
      final h = m.hist[i1];
      label = 'MACD 12 26 9  ${h.isNaN ? '-' : h.toStringAsPrecision(3)}';
      cv.restore();
    }
    _txt(cv, label, Offset(r.left + 6, r.top + 3), color: AppColors.text, size: 10);
  }

  void _paintForecast(Canvas cv, double w, double h, double barW,
      double Function(double) xOf, double Function(double) yOf,
      bool Function(double) inY, int i0, int i1) {
    final fc = f!;
    final n = c.length;

    // أنماط الشموع اليابانية على كل شمعة
    if (L.pats && barW >= 3) {
      var lastUp = -1e9, lastDn = -1e9; // منع تداخل الأسماء
      for (final p in fc.patterns) {
        if (p.i < i0 || p.i > i1) continue;
        final x = xOf(p.i.toDouble());
        if (p.bias > 0) {
          if (x - lastUp < 42) continue;
          lastUp = x;
        } else {
          if (x - lastDn < 42) continue;
          lastDn = x;
        }
        final col = (p.bias > 0 ? _up : _down).withOpacity(0.85);
        if (p.bias > 0) {
          _txt(cv, p.label, Offset(x - 12, yOf(c[p.i].low) + 24),
              color: col, size: 8, rtl: true);
        } else {
          _txt(cv, p.label, Offset(x - 12, yOf(c[p.i].high) - 34),
              color: col, size: 8, rtl: true);
        }
      }
    }

    // التوصيات على الشارت ونتيجتها الحقيقية
    if (L.sigs) {
      for (final sg in fc.signals) {
        final exitI = sg.exitI < 0 ? n - 1 : sg.exitI;
        if (exitI < i0 || sg.i > i1) continue;
        final buy = sg.dir > 0;
        final col = buy ? _up : _down;
        final xs = xOf(sg.i.toDouble()), xe = xOf(exitI.toDouble()) + barW / 2;
        // صندوق الصفقة: أخضر للهدف ، أحمر للوقف
        final yE = yOf(sg.entry), yS = yOf(sg.sl), yT = yOf(sg.tp2);
        cv.drawRect(Rect.fromLTRB(xs, math.min(yE, yT), xe, math.max(yE, yT)),
            Paint()..color = _up.withOpacity(0.08));
        cv.drawRect(Rect.fromLTRB(xs, math.min(yE, yS), xe, math.max(yE, yS)),
            Paint()..color = _down.withOpacity(0.08));
        cv.drawLine(Offset(xs, yE), Offset(xe, yE),
            Paint()
              ..color = Colors.white54
              ..strokeWidth = 1);
        _dashed(cv, xs, xe, yOf(sg.tp1), Paint()
          ..color = _up.withOpacity(0.6)
          ..strokeWidth = 1, dash: 3, gap: 3);
        // سهم كبير عند شمعة الإشارة
        final k = c[sg.i];
        final path = Path();
        if (buy) {
          final y = yOf(k.low) + 4;
          path
            ..moveTo(xs, y)
            ..lineTo(xs - 7, y + 12)
            ..lineTo(xs + 7, y + 12)
            ..close();
        } else {
          final y = yOf(k.high) - 4;
          path
            ..moveTo(xs, y)
            ..lineTo(xs - 7, y - 12)
            ..lineTo(xs + 7, y - 12)
            ..close();
        }
        cv.drawPath(path, Paint()..color = sg.strong ? col : col.withOpacity(0.6));
        _txt(cv, buy ? 'شراء' : 'بيع',
            Offset(xs - 10, buy ? yOf(k.low) + 14 : math.max(40.0, yOf(k.high) - 28)),
            color: Colors.white, size: 8, bold: true, bg: col, rtl: true);
        if (sg.total > 0) {
          _txt(cv, '${sg.agree}/${sg.total}',
              Offset(xs - 8, buy ? yOf(k.low) + 28 : yOf(k.high) - 40),
              color: col, size: 8);
        }
        // النتيجة
        if (sg.exitI >= 0 || sg.result != 0) {
          final rm = sg.rMultiple;
          final res = sg.result >= 1
              ? '${rm >= 0 ? '+' : ''}${rm.toStringAsFixed(1)}R'
                  : sg.result == -2
                      ? '⌛ انتهت المهلة'
                      : 'SL';
          final rc = sg.result > 0
              ? _up
              : sg.result == -2
                  ? AppColors.muted
                  : _down;
          final ry = sg.result > 0 ? yOf(sg.result == 2 ? sg.tp2 : sg.tp1) : yS;
          _txt(cv, res, Offset(xe - 28, ry - 14),
              color: Colors.white, size: 9, bold: true, bg: rc, rtl: sg.result == -2);
        } else {
          _txt(cv, 'مفتوحة', Offset(xe - 34, yE - 14),
              color: AppColors.onAccent, size: 9, bg: AppColors.accent, rtl: true);
        }
      }
    }

    if (!L.fc) return;

    // شريط دقة توقع الشموع (أسفل الشارت): أخضر صح ، أحمر خطأ
    for (var i = i0; i <= i1 && i < fc.predHits.length; i++) {
      final v = fc.predHits[i];
      if (v == 0) continue;
      final x = xOf(i.toDouble());
      cv.drawRect(Rect.fromLTWH(x - barW * 0.35, h - 4, barW * 0.7, 3),
          Paint()..color = (v > 0 ? _up : _down).withOpacity(0.8));
    }

    // الإشارات المرتقبة قبل حدوثها
    final xLast = xOf((n - 1).toDouble());
    for (final p in fc.pending) {
      final col = p.dir > 0 ? _up : _down;
      if (inY(p.trigger)) {
        final y = yOf(p.trigger);
        _dashed(cv, xLast - barW * 6, w, y, Paint()
          ..color = col
          ..strokeWidth = 1.4, dash: 6, gap: 3);
        _txt(cv,
            '${p.dir > 0 ? 'شراء فوق' : 'بيع تحت'} ${sym.fmt(p.trigger)}',
            Offset(xLast - barW * 6, y - 13),
            color: Colors.white, size: 9, bold: true, bg: col.withOpacity(0.85), rtl: true);
      }
      if (inY(p.sl)) {
        _dashed(cv, xLast + barW, w, yOf(p.sl), Paint()
          ..color = _down.withOpacity(0.6)
          ..strokeWidth = 1, dash: 2, gap: 3);
      }
      if (inY(p.tp1)) {
        _dashed(cv, xLast + barW, w, yOf(p.tp1), Paint()
          ..color = _up.withOpacity(0.6)
          ..strokeWidth = 1, dash: 2, gap: 3);
      }
    }

    // الشمعة القادمة المتوقعة (شبحية)
    final nb = fc.next;
    if (nb != null && fc.showNext) {
      final x = xOf(n.toDouble());
      if (x < w) {
        final up = nb.pUp >= 0.5;
        final col = !nb.clear ? AppColors.muted : (up ? _up : _down);
        final bw = math.max(2.0, barW * 0.7);
        cv.drawLine(Offset(x, yOf(nb.high)), Offset(x, yOf(nb.low)),
            Paint()
              ..color = col.withOpacity(0.5)
              ..strokeWidth = 1);
        final yo = yOf(nb.open), yc = yOf(nb.close);
        final r = Rect.fromLTRB(x - bw / 2, math.min(yo, yc), x + bw / 2,
            math.max(math.max(yo, yc), math.min(yo, yc) + 2));
        cv.drawRect(r, Paint()..color = col.withOpacity(0.3));
        cv.drawRect(
            r,
            Paint()
              ..color = col
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1);
        final pct = ((up ? nb.pUp : 1 - nb.pUp) * 100).toStringAsFixed(0);
        _txt(cv, nb.clear ? '${up ? '+' : '-'} $pct%' : '؟',
            Offset(x - 12, up ? yOf(nb.high) - 14 : yOf(nb.low) + 3),
            color: col, size: 10, bold: true);
      }
    }
  }

  /// علامات Alka: "Alka شراء ▲" تحت الشمعة و "Alka بيع ▼" فوقها، مع نتيجة الصفقة.
  /// علامات شراء/بيع بأسلوب Alka لأي مؤشر: "TAG شراء ▲" تحت الشمعة و "TAG بيع ▼" فوقها،
  /// مع نتيجة الصفقة، وخطوط الصفقة المفتوحة، والإشارة المنتظرة. [border] لون إطار مميز (ALL ذهبي).
  void _paintTagged(Canvas cv, double w, double barW, double Function(double) xOf,
      double Function(double) yOf, bool Function(double) inY, int i0, int i1,
      List<PastSignal> signals, List<PendingSetup> pending, String tag, Color? border,
      {Color upCol = const Color(0xFF00C853),
      Color downCol = const Color(0xFFFF1744),
      bool darkText = false,
      List<String>? sources,
      List<String>? pendingSrc,
      List<String>? tagPer,
      List<String>? pendTagPer,
      List<int>? starsPer,
      List<bool>? weakPer}) {
    final n = c.length;
    final placed = <Rect>[]; // لافتات مرسومة: نزيح الجديدة حتى لا تتراكب
    for (final (si, sg) in signals.indexed) {
      if (sg.i < i0 || sg.i > i1 || sg.i >= n) continue;
      final buy = sg.dir > 0;
      // إشارات 0.1 داخل Mp تحتفظ بلونها (أزرق/أصفر)
      final z = sources != null && si < sources.length && sources[si] == '0.1';
      final weak = weakPer != null && si < weakPer.length && weakPer[si];
      final col0 = z ? (buy ? zeroUp : zeroDown) : (buy ? upCol : downCol);
      // الإشارة الضعيفة: باهتة
      final col = weak ? Color.alphaBlend(col0.withOpacity(0.38), AppColors.bg) : col0;
      final txtCol = weak ? Colors.white70 : ((darkText || z) && !buy ? AppColors.onAccent : Colors.white);
      final x = xOf(sg.i.toDouble());
      final k = c[sg.i];
      final tp = TextPainter(
        text: TextSpan(
            text: '${tagPer != null && si < tagPer.length ? tagPer[si] : tag} ${buy ? 'شراء' : 'بيع'}'.trim(),
            style: TextStyle(
                fontFamily: chartFont, color: txtCol, fontSize: 10, fontWeight: FontWeight.w800)),
        textDirection: TextDirection.rtl,
      )..layout();
      // نجوم الثقة (مرسومة كأشكال حتى لا تعتمد على خط الإيموجي)
      final ns = starsPer != null && si < starsPer.length ? starsPer[si] : -1;
      const starW = 10.0;
      final starsW = ns < 0 ? 0.0 : (ns == 0 ? starW : ns * starW) + 3;
      final bw = tp.width + 10 + starsW, bh = tp.height + 4;
      // سهم صغير يشير للشمعة + لافتة ملونة
      final tipY = buy ? yOf(k.low) + 3 : yOf(k.high) - 3;
      // لا ترتفع اللافتة فوق شريط الأسعار العلوي، ونزيحها إذا تراكبت مع لافتة سابقة
      var boxY = buy ? tipY + 7 : math.max(40.0, tipY - 7 - bh);
      for (var guard = 0; guard < 6; guard++) {
        final rr = Rect.fromLTWH(x - bw / 2, boxY, bw, bh + 13);
        final hit = placed.where((p) => p.overlaps(rr)).toList();
        if (hit.isEmpty) break;
        boxY = buy ? hit.map((p) => p.bottom).reduce(math.max) + 2 : hit.map((p) => p.top).reduce(math.min) - bh - 15;
      }
      placed.add(Rect.fromLTWH(x - bw / 2, buy ? boxY : boxY - 13, bw, bh + 13));
      final arrow = Path()
        ..moveTo(x, tipY)
        ..lineTo(x - 5, buy ? tipY + 7 : tipY - 7)
        ..lineTo(x + 5, buy ? tipY + 7 : tipY - 7)
        ..close();
      cv.drawPath(arrow, Paint()..color = col);
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(x - bw / 2, boxY, bw, bh), const Radius.circular(5));
      cv.drawRRect(r, Paint()..color = col);
      cv.drawRRect(
          r,
          Paint()
            ..color = weak ? col0.withOpacity(0.7) : (border ?? Colors.white.withOpacity(0.85))
            ..style = PaintingStyle.stroke
            ..strokeWidth = border == null || weak ? 1 : 2);
      tp.paint(cv, Offset(x + bw / 2 - 5 - tp.width, boxY + 2));
      if (ns >= 0) {
        // النجوم يسار النص: ذهبية ممتلئة، أو نجمة فارغة واحدة لإشارة بلا موافقة
        for (var q = 0; q < (ns == 0 ? 1 : ns); q++) {
          final cx = x - bw / 2 + 5 + starW / 2 + q * starW, cy = boxY + bh / 2;
          final path = _starPath(cx, cy, 4.6);
          if (ns == 0) {
            cv.drawPath(path, Paint()
              ..color = Colors.white.withOpacity(0.8)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1);
          } else {
            cv.drawPath(path, Paint()..color = const Color(0xFFFFD54F));
            cv.drawPath(path, Paint()
              ..color = Colors.black.withOpacity(0.35)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.6);
          }
        }
      }
      // النتيجة تحت/فوق اللافتة
      if (sg.result != 0 || sg.exitI >= 0) {
        final rm = sg.rMultiple;
        final txt = '${rm >= 0 ? '+' : ''}${rm.toStringAsFixed(1)}R';
        _txt(cv, txt, Offset(x - 18, buy ? boxY + bh + 2 : boxY - 13),
            color: sg.result > 0 ? const Color(0xFF00E676) : const Color(0xFFFF8A80), size: 9, bold: true);
      } else {
        _txt(cv, 'مفتوحة', Offset(x - 16, buy ? boxY + bh + 2 : boxY - 13),
            color: AppColors.gold, size: 9, bold: true, rtl: true);
      }
    }
    // صفقات مفتوحة (قد تكون صفقتان: شراء + بيع): خطوط الدخول والوقف والهدف
    for (final sg in signals.where((x) => x.exitI < 0)) {
      final x0 = math.max(0.0, xOf(sg.i.toDouble()));
      void ln(double p, Color col, String t) {
        if (!inY(p)) return;
        _dashed(cv, x0, w, yOf(p), Paint()
          ..color = col
          ..strokeWidth = 1.2, dash: 5, gap: 3);
        _axis.add((yOf(p), sym.fmt(p), t, col));
      }

      ln(sg.entry, const Color(0xFF9AA5B8), 'دخول');
      ln(sg.curStop.isNaN ? sg.sl : sg.curStop, _down, 'وقف');
      ln(sg.tp1, _up, 'TP1');
      ln(sg.tp2, _up.withOpacity(0.8), 'TP2');
    }
    for (final (pi, p) in pending.indexed) {
      if (!inY(p.trigger)) continue;
      final pz = pendingSrc != null && pi < pendingSrc.length && pendingSrc[pi] == '0.1';
      final col = pz ? (p.dir > 0 ? zeroUp : zeroDown) : (p.dir > 0 ? upCol : downCol);
      final xl = xOf((n - 1).toDouble()) - barW * 6;
      _dashed(cv, xl, w, yOf(p.trigger), Paint()
        ..color = col
        ..strokeWidth = 1.4, dash: 6, gap: 3);
      _txt(cv, '${pendTagPer != null && pi < pendTagPer.length ? pendTagPer[pi] : tag} ${p.dir > 0 ? 'شراء فوق' : 'بيع تحت'}',
          Offset(xl, yOf(p.trigger) - 13),
          color: (darkText || pz) && p.dir < 0 ? AppColors.onAccent : Colors.white, size: 9, bold: true, bg: col.withOpacity(0.85), rtl: true);
      _axis.add((yOf(p.trigger), sym.fmt(p.trigger), 'دخول', col));
      if (inY(p.sl)) {
        _dashed(cv, xl, w, yOf(p.sl), Paint()
          ..color = _down.withOpacity(0.6)
          ..strokeWidth = 1, dash: 3, gap: 3);
        _axis.add((yOf(p.sl), sym.fmt(p.sl), 'وقف', _down));
      }
      if (inY(p.tp1)) {
        _dashed(cv, xl, w, yOf(p.tp1), Paint()
          ..color = _up.withOpacity(0.6)
          ..strokeWidth = 1, dash: 3, gap: 3);
        _axis.add((yOf(p.tp1), sym.fmt(p.tp1), 'TP1', _up));
      }
    }
  }

  Path _starPath(double cx, double cy, double r) {
    final p = Path();
    for (var k = 0; k < 10; k++) {
      final rr = k.isEven ? r : r * 0.45;
      final a = -math.pi / 2 + k * math.pi / 5;
      final pt = Offset(cx + rr * math.cos(a), cy + rr * math.sin(a));
      if (k == 0) {
        p.moveTo(pt.dx, pt.dy);
      } else {
        p.lineTo(pt.dx, pt.dy);
      }
    }
    return p..close();
  }

  /// لافتات المحور: السعر على المحور واسم المستوى بجانبه، مع إزاحة رأسية تمنع التداخل
  /// (وتتجنب لافتة السعر الحالي).
  void _paintAxisTags(Canvas cv, double w, double h, double lastY) {
    if (_axis.isEmpty) return;
    // نفس المستوى من أكثر من مؤشر (مثل النجوم و SM لنفس الصفقة) يُرسم مرة واحدة
    final seen = <String>{};
    final tags = [for (final t in _axis) if (seen.add('${t.$3}|${t.$2}')) t]..sort((a, b) => a.$1.compareTo(b.$1));
    const gap = 16.0;
    final ys = <double>[];
    for (final t in tags) {
      var y = t.$1.clamp(30.0, h - 10).toDouble();
      if (ys.isNotEmpty && y < ys.last + gap) y = ys.last + gap;
      // تجنب لافتة السعر الحالي والعداد
      if (y > lastY - 15 && y < lastY + 31) y = t.$1 < lastY + 6 ? lastY - 15 : lastY + 31;
      if (ys.isNotEmpty && y < ys.last + gap) y = ys.last + gap;
      ys.add(y);
    }
    for (var i = 0; i < tags.length; i++) {
      final (py, price, name, col) = tags[i];
      final y = ys[i];
      // وصلة صغيرة لو أُزيحت اللافتة عن مستواها
      if ((y - py).abs() > 2) {
        cv.drawLine(Offset(w - 2, py), Offset(w + 2, y),
            Paint()
              ..color = col.withOpacity(0.7)
              ..strokeWidth = 1);
      }
      _pill(cv, price, Offset(w + 1, y - 7), col, bold: true);
      final tp = TextPainter(
        text: TextSpan(
            text: name,
            style: TextStyle(fontFamily: chartFont, color: col, fontSize: 9, fontWeight: FontWeight.w800)),
        textDirection: TextDirection.rtl,
      )..layout();
      final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(w - tp.width - 10, y - 7, tp.width + 8, tp.height + 1), const Radius.circular(3));
      cv.drawRRect(r, Paint()..color = AppColors.bg.withOpacity(0.9));
      cv.drawRRect(
          r,
          Paint()
            ..color = col.withOpacity(0.8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8);
      tp.paint(cv, Offset(w - tp.width - 6, y - 7));
    }
  }

  /// سطر واحد مختصر تحت شريط الأسعار: دقة المؤشرين + اتجاه AAB Algo.
  void _legend(Canvas cv, double w) {
    final fc = f!;
    final spans = <TextSpan>[];
    void part(String t, Color col) {
      if (spans.isNotEmpty) {
        spans.add(const TextSpan(text: '  •  ', style: TextStyle(color: AppColors.muted)));
      }
      spans.add(TextSpan(text: t, style: TextStyle(color: col, fontWeight: FontWeight.w700)));
    }

    if (L.dm && dmr != null && dmr!.closed > 0) {
      final a = dmr!;
      part('DM ${(a.winRate * 100).toStringAsFixed(0)}% (${a.wins}/${a.closed})',
          a.winRate >= 0.5 ? AppColors.gold : _down);
    }
    if (L.king && kingr != null && kingr!.res.closed > 0) {
      final a = kingr!.res;
      part('King ${(a.winRate * 100).toStringAsFixed(0)}% (${a.wins}/${a.closed})', a.winRate >= 0.5 ? AppColors.gold : _down);
    }
    if (L.aiak && akr != null && akr!.closed > 0) {
      final a = akr!;
      part('AK ${(a.winRate * 100).toStringAsFixed(0)}% (${a.wins}/${a.closed})', a.winRate >= 0.5 ? _up : _down);
    }
    if (L.pq && pqr != null && pqr!.closed > 0) {
      final a = pqr!;
      part('PQ ${(a.winRate * 100).toStringAsFixed(0)}% (${a.wins}/${a.closed})', a.winRate >= 0.5 ? _up : _down);
    }
    if (L.lt && ltr != null && tf == '1d' && ltr!.closed > 0) {
      final a = ltr!;
      part('LT ${(a.winRate * 100).toStringAsFixed(0)}% (${a.wins}/${a.closed})',
          a.winRate >= 0.5 ? const Color(0xFF4FC3F7) : _down);
    }
    if (L.star && starr != null && starr!.res.closed > 0) {
      final a = starr!.res;
      part('نجوم ${(a.winRate * 100).toStringAsFixed(0)}% (${a.wins}/${a.closed})',
          a.winRate >= 0.5 ? AppColors.gold : _down);
    }
    if (L.st && str != null && str!.res.closed > 0) {
      final a = str!.res;
      part('ST ${(a.winRate * 100).toStringAsFixed(0)}% (${a.wins}/${a.closed})',
          a.winRate >= 0.5 ? AppColors.gold : _down);
    }
    if (L.km && kmr != null && kmr!.closed > 0) {
      final a = kmr!;
      part('KM ${(a.winRate * 100).toStringAsFixed(0)}% (${a.wins}/${a.closed})',
          a.winRate >= 0.5 ? AppColors.gold : _down);
    }
    if (L.sm && smr != null && smr!.closed > 0) {
      final a = smr!;
      part('SM ${(a.winRate * 100).toStringAsFixed(0)}% (${a.wins}/${a.closed})',
          a.winRate >= 0.5 ? const Color(0xFF00E676) : _down);
    }
    if (L.mp && mr != null && mr!.closed > 0) {
      final a = mr!;
      part('Mp ${(a.winRate * 100).toStringAsFixed(0)}% (${a.wins}/${a.closed})',
          a.winRate >= 0.5 ? AppColors.gold : _down);
    }
    if (L.all && ar != null && ar!.closed > 0) {
      final a = ar!;
      part('ALL ${(a.winRate * 100).toStringAsFixed(0)}% (${a.wins}/${a.closed})',
          a.winRate >= 0.5 ? AppColors.gold : _down);
    }
    if (L.zero && zr != null && zr!.closed > 0) {
      final a = zr!;
      part('0.1 ${(a.winRate * 100).toStringAsFixed(0)}% (${a.wins}/${a.closed})',
          a.winRate >= 0.5 ? zeroUp : _down);
    }
    if (L.alka && ak != null && ak!.closed > 0) {
      final a = ak!;
      part('Alka ${(a.winRate * 100).toStringAsFixed(0)}% (${a.wins}/${a.closed})',
          a.winRate >= 0.5 ? const Color(0xFF00E676) : _down);
    }
    if (L.sigs && fc.closed > 0) {
      part('AAB ${(fc.winRate * 100).toStringAsFixed(0)}% (${fc.wins}/${fc.closed})',
          fc.winRate >= 0.5 ? _up : _down);
    }
    if (_algoOn) {
      final t = al!.trend.last, p = al!.power.last;
      part('Algo ${t > 0 ? 'صاعد' : t < 0 ? 'هابط' : '-'} ${p == 2 ? 'قوي' : p == 1 ? 'متوسط' : 'ضعيف'}',
          t > 0 ? _up : (t < 0 ? _down : AppColors.muted));
    }
    if (spans.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(
          style: TextStyle(fontFamily: chartFont, fontSize: 10),
          children: spans),
      textDirection: TextDirection.rtl,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: math.max(120.0, w - 16));
    cv.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(4, 21, tp.width + 8, tp.height + 4), const Radius.circular(6)),
        Paint()..color = AppColors.surface.withOpacity(0.92));
    tp.paint(cv, const Offset(8, 23));
  }

  @override
  bool shouldRepaint(covariant _Painter old) => true;
}
