import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../analysis/forecast.dart';
import '../analysis/indicators.dart';
import '../models.dart';
import '../theme.dart';

class ChartLayers {
  bool fib = false, vp = false, zones = true, vwap = false, levels = false, ce = false;
  bool sigs = true, fc = true, pats = true, ema = true;
  bool vol = true; // أعمدة الحجم أسفل الشارت
  String type = 'candle'; // candle | ha (Heikin Ashi) | line
  String sub = 'rsi'; // none | rsi | macd — اللوحة السفلية
}

/// خط الكتابة في الشارت (null = خط النظام). يُغيَّر في اختبارات لقطات الشاشة فقط.
String? chartFont;

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
  final MarketSymbol sym;
  final String tf;
  final ChartLayers layers;
  const NativeChart({
    super.key,
    required this.candles,
    required this.signal,
    this.forecast,
    required this.sym,
    required this.tf,
    required this.layers,
  });

  @override
  State<NativeChart> createState() => _NativeChartState();
}

class _NativeChartState extends State<NativeChart> with SingleTickerProviderStateMixin {
  static const _homeShift = -6.0;
  double visible = 90, shift = _homeShift, _baseVisible = 90;
  double yZoom = 1, _baseYZoom = 1; // تكبير عمودي يدوي (اسحب على محور السعر)
  bool _axisDrag = false;
  double _chartW = 1;
  Offset? cross;
  late final Ticker _ticker;
  double _vel = 0; // سرعة التمرير بعد رفع الإصبع (شموع/ثانية)
  Duration _lastTick = Duration.zero;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    // تحديث العدّاد التنازلي لإغلاق الشمعة كل ثانية
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && cross == null) setState(() {});
    });
  }

  @override
  void dispose() {
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
              if (cross != null) setState(() => cross = null);
            },
            onLongPressStart: (d) => setState(() => cross = d.localPosition),
            onLongPressMoveUpdate: (d) => setState(() => cross = d.localPosition),
            onDoubleTap: () => setState(() {
              _stopFling();
              visible = 90;
              shift = _homeShift;
              yZoom = 1;
              cross = null;
            }),
            child: CustomPaint(
              size: Size.infinite,
              painter: _Painter(widget.candles, widget.signal, widget.forecast,
                  widget.sym, widget.tf, visible, shift, cross, widget.layers, yZoom,
                  DateTime.now().toUtc()),
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
                onTap: () => setState(() {
                  _stopFling();
                  shift = _homeShift;
                }),
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
                onTap: () => setState(() => cross = null),
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
  _Painter(this.c, this.s, this.f, this.sym, this.tf, this.visible, this.shift,
      this.cross, this.L, this.yZoom, this.now);

  static const _up = AppColors.up, _down = AppColors.down;

  void _txt(Canvas cv, String t, Offset o,
      {Color color = AppColors.muted, double size = 10, Color? bg, bool bold = false,
      bool rtl = false}) {
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

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.bg);
    final n = c.length;
    if (n < 2) {
      _txt(canvas, 'جاري تحميل البيانات…', Offset(size.width / 2 - 55, size.height / 2),
          size: 12);
      return;
    }
    final fullH = size.height - timeH;
    final subH = L.sub == 'none' ? 0.0 : math.max(60.0, fullH * 0.22);
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
    double yOf(double p) => h * (hi - p) / (hi - lo);
    bool inY(double p) => p <= hi && p >= lo;

    // ── علامة مائية
    _txt(canvas, '${sym.code}  ${tf.toUpperCase()}', Offset(w / 2 - 70, h / 2 - 16),
        color: AppColors.muted.withOpacity(0.07), size: 28, bold: true);

    // ── شبكة + محور السعر بخطوات منتظمة
    final gridP = Paint()
      ..color = AppColors.border.withOpacity(0.45)
      ..strokeWidth = 1;
    final step = _niceStep((hi - lo) / 7);
    for (var p = (lo / step).ceil() * step; p <= hi; p += step) {
      final y = yOf(p);
      canvas.drawLine(Offset(0, y), Offset(w, y), gridP);
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
        canvas.drawRect(Rect.fromLTRB(x - vw / 2, h - vh, x + vw / 2, h),
            Paint()..color = (c[i].close >= c[i].open ? _up : _down).withOpacity(0.28));
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
      for (var i = i0; i <= i1; i++) {
        final q = k[i];
        final x = xOf(i.toDouble());
        final bull = q.close >= q.open;
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

    // ── رأس الشارت: OHLC للشمعة الحالية أو التي تحت المؤشر
    int? cIdx;
    double? cx, cy;
    if (cross != null) {
      cIdx = ((cross!.dx.clamp(0.0, w)) / barW + leftIdx - 0.5).round().clamp(i0, i1).toInt();
      cx = xOf(cIdx.toDouble()); // التصاق بمنتصف الشمعة
      cy = cross!.dy.clamp(0.0, fullH).toDouble();
    }
    _header(canvas, cIdx ?? n - 1, w);
    if (f != null) _legend(canvas);

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
        _pill(canvas, sym.fmt(hi - cy / h * (hi - lo)), Offset(w + 1, cy - 7), AppColors.accent);
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
              color: Colors.white,
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
    cv.drawRect(Rect.fromLTWH(4, 3, tp.width + 4, tp.height + 2),
        Paint()..color = AppColors.bg.withOpacity(0.75));
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
            Offset(xs - 10, buy ? yOf(k.low) + 14 : yOf(k.high) - 28),
            color: Colors.white, size: 8, bold: true, bg: col, rtl: true);
        if (sg.total > 0) {
          _txt(cv, '${sg.agree}/${sg.total}',
              Offset(xs - 8, buy ? yOf(k.low) + 28 : yOf(k.high) - 40),
              color: col, size: 8);
        }
        // النتيجة
        if (sg.exitI >= 0 || sg.result != 0) {
          final res = sg.result == 2
              ? '✓ TP2'
              : sg.result == 1
                  ? '✓ TP1'
                  : sg.result == -2
                      ? '⌛ انتهت المهلة'
                      : '✗ SL';
          final rc = sg.result > 0
              ? _up
              : sg.result == -2
                  ? AppColors.muted
                  : _down;
          final ry = sg.result > 0 ? yOf(sg.result == 2 ? sg.tp2 : sg.tp1) : yS;
          _txt(cv, res, Offset(xe - 28, ry - 14),
              color: Colors.white, size: 9, bold: true, bg: rc, rtl: sg.result == -2);
        } else {
          _txt(cv, '⏳ مفتوحة', Offset(xe - 40, yE - 14),
              color: Colors.white, size: 9, bg: AppColors.accent, rtl: true);
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
            '⏳ ${p.dir > 0 ? 'شراء فوق' : 'بيع تحت'} ${sym.fmt(p.trigger)}',
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
        _txt(cv, nb.clear ? '${up ? '▲' : '▼'} $pct%' : '؟',
            Offset(x - 12, up ? yOf(nb.high) - 14 : yOf(nb.low) + 3),
            color: col, size: 10, bold: true);
      }
    }
  }

  void _legend(Canvas cv) {
    final fc = f!;
    final lines = <(String, Color)>[];
    if (L.sigs && fc.closed > 0) {
      lines.add((
        'دقة التوصيات على الشارت: ${(fc.winRate * 100).toStringAsFixed(0)}% '
            '(${fc.wins} ربح / ${fc.losses} خسارة)',
        fc.winRate >= 0.5 ? _up : _down
      ));
    }
    if (L.fc && fc.predN > 0) {
      lines.add((
        'دقة توقع اتجاه الشمعة: ${(fc.predAcc * 100).toStringAsFixed(0)}% (${fc.predN} توقع)',
        fc.predAcc >= 0.5 ? _up : _down
      ));
    }
    if (L.ema) {
      lines.add(('EMA20 سماوي • EMA50 برتقالي • EMA200 بنفسجي', AppColors.muted));
    }
    var y = 22.0;
    for (final (t, col) in lines) {
      _txt(cv, t, Offset(6, y), color: col, size: 10, bg: AppColors.surface.withOpacity(0.85),
          rtl: true);
      y += 15;
    }
  }

  @override
  bool shouldRepaint(covariant _Painter old) => true;
}
