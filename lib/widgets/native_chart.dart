import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../analysis/forecast.dart';
import '../models.dart';
import '../theme.dart';

class ChartLayers {
  bool fib = false, vp = false, zones = true, vwap = false, levels = false, ce = false;
  bool sigs = true, fc = true, pats = true, ema = true;
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

class _NativeChartState extends State<NativeChart> {
  double visible = 90, shift = -6, _baseVisible = 90;
  Offset? cross;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final chartW = math.max(1.0, box.maxWidth - _Painter.axisW);
      return GestureDetector(
        onScaleStart: (_) => _baseVisible = visible,
        onScaleUpdate: (d) {
          final n = widget.candles.length;
          setState(() {
            if (d.pointerCount >= 2) {
              visible = (_baseVisible / d.scale).clamp(25.0, 300.0).toDouble();
            }
            final barW = chartW / visible;
            shift = (shift + d.focalPointDelta.dx / barW)
                .clamp(-12.0, math.max(0, n - 20).toDouble())
                .toDouble();
          });
        },
        onLongPressStart: (d) => setState(() => cross = d.localPosition),
        onLongPressMoveUpdate: (d) => setState(() => cross = d.localPosition),
        onLongPressEnd: (_) => setState(() => cross = null),
        onDoubleTap: () => setState(() {
          visible = 90;
          shift = -6;
        }),
        child: CustomPaint(
          size: Size.infinite,
          painter: _Painter(widget.candles, widget.signal, widget.forecast,
              widget.sym, widget.tf, visible, shift, cross, widget.layers),
        ),
      );
    });
  }
}

class _Painter extends CustomPainter {
  static const axisW = 58.0, timeH = 20.0;
  final List<Candle> c;
  final TradeSignal? s;
  final Forecast? f;
  final MarketSymbol sym;
  final String tf;
  final double visible, shift;
  final Offset? cross;
  final ChartLayers L;
  _Painter(this.c, this.s, this.f, this.sym, this.tf, this.visible, this.shift,
      this.cross, this.L);

  static const _up = AppColors.up, _down = AppColors.down;

  void _txt(Canvas cv, String t, Offset o,
      {Color color = AppColors.muted, double size = 10, Color? bg, bool bold = false,
      bool rtl = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: t,
          style: TextStyle(
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
    final w = size.width - axisW, h = size.height - timeH;
    final rightIdx = n - 1 - shift;
    final leftIdx = rightIdx - visible + 1;
    final barW = w / visible;
    double xOf(double i) => (i - leftIdx + 0.5) * barW;
    final i0 = math.max(0, leftIdx.floor()), i1 = math.min(n - 1, rightIdx.ceil());
    if (i0 > i1) return;

    double hi = -double.infinity, lo = double.infinity;
    for (var i = i0; i <= i1; i++) {
      hi = math.max(hi, c[i].high);
      lo = math.min(lo, c[i].low);
    }
    if (!(hi > lo)) hi = lo + 1;
    final pad = (hi - lo) * 0.08;
    hi += pad;
    lo -= pad;
    double yOf(double p) => h * (hi - p) / (hi - lo);
    bool inY(double p) => p <= hi && p >= lo;

    // ── grid + price axis
    final gridP = Paint()
      ..color = AppColors.border.withOpacity(0.55)
      ..strokeWidth = 1;
    for (var k = 0; k <= 6; k++) {
      final p = hi - k * (hi - lo) / 6;
      final y = yOf(p);
      canvas.drawLine(Offset(0, y), Offset(w, y), gridP);
      _txt(canvas, sym.fmt(p), Offset(w + 4, y - 6));
    }
    canvas.drawLine(Offset(w, 0), Offset(w, h), Paint()..color = AppColors.border);

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w, h));

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

    // ── candles
    final bodyW = math.max(1.0, barW * 0.7);
    for (var i = i0; i <= i1; i++) {
      final k = c[i];
      final x = xOf(i.toDouble());
      final col = k.close >= k.open ? _up : _down;
      canvas.drawLine(Offset(x, yOf(k.high)), Offset(x, yOf(k.low)),
          Paint()
            ..color = col
            ..strokeWidth = 1);
      final yo = yOf(k.open), yc = yOf(k.close);
      final top = math.min(yo, yc), bot = math.max(yo, yc);
      canvas.drawRect(
          Rect.fromLTRB(x - bodyW / 2, top, x + bodyW / 2, math.max(bot, top + 1)),
          Paint()..color = col);
    }

    // ── markers (CE flips, sweeps, S/R breaks)
    if (s != null) {
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
    if (s != null && s!.direction != Direction.neutral) {
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

    // ── last price line
    final last = c.last.close;
    if (inY(last)) {
      final y = yOf(last);
      _dashed(canvas, 0, w, y, Paint()
        ..color = (c.last.close >= c.last.open ? _up : _down).withOpacity(0.7)
        ..strokeWidth = 1);
    }
    canvas.restore();

    if (inY(last)) {
      final y = yOf(last);
      _txt(canvas, sym.fmt(last), Offset(w + 3, y - 7),
          color: Colors.white,
          size: 10,
          bold: true,
          bg: c.last.close >= c.last.open ? _up : _down);
    }

    // ── time axis
    final step = math.max(1, (visible / 5).round());
    for (var i = i0; i <= i1; i++) {
      if ((i - i0) % step != 0) continue;
      _txt(canvas, _time(c[i].time), Offset(xOf(i.toDouble()) - 14, h + 4));
    }

    if (f != null && cross == null) _legend(canvas);

    // ── crosshair
    if (cross != null) {
      final cx = cross!.dx.clamp(0.0, w).toDouble();
      final cy = cross!.dy.clamp(0.0, h).toDouble();
      final idx = (cx / barW + leftIdx - 0.5).round().clamp(0, n - 1).toInt();
      final p = hi - cy / h * (hi - lo);
      final cp = Paint()
        ..color = Colors.white54
        ..strokeWidth = 0.8;
      _dashed(canvas, 0, w, cy, cp, dash: 3, gap: 3);
      canvas.drawLine(Offset(cx, 0), Offset(cx, h), cp);
      _txt(canvas, sym.fmt(p), Offset(w + 3, cy - 7),
          color: Colors.white, size: 10, bg: AppColors.accent);
      final k = c[idx];
      _txt(
          canvas,
          '${_time(k.time)}  O ${sym.fmt(k.open)}  H ${sym.fmt(k.high)}  L ${sym.fmt(k.low)}  C ${sym.fmt(k.close)}',
          const Offset(6, 4),
          color: AppColors.text,
          size: 10,
          bg: AppColors.surface);
    }
  }

  void _paintForecast(Canvas cv, double w, double h, double barW,
      double Function(double) xOf, double Function(double) yOf,
      bool Function(double) inY, int i0, int i1) {
    final fc = f!;
    final n = c.length;

    // أنماط الشموع اليابانية على كل شمعة
    if (L.pats) {
      for (final p in fc.patterns) {
        if (p.i < i0 || p.i > i1) continue;
        final x = xOf(p.i.toDouble());
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
    if (nb != null) {
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
    var y = 4.0;
    for (final (t, col) in lines) {
      _txt(cv, t, Offset(6, y), color: col, size: 10, bg: AppColors.surface.withOpacity(0.85),
          rtl: true);
      y += 15;
    }
  }

  @override
  bool shouldRepaint(covariant _Painter old) => true;
}
