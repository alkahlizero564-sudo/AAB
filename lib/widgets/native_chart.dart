import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';

class ChartLayers {
  bool fib = true, vp = true, zones = true, vwap = true, levels = true, ce = true;
}

/// Our own candlestick chart (no TradingView, no WebView).
/// Pinch = zoom, drag = scroll, long-press = crosshair, double-tap = reset.
class NativeChart extends StatefulWidget {
  final List<Candle> candles;
  final TradeSignal? signal;
  final MarketSymbol sym;
  final String tf;
  final ChartLayers layers;
  const NativeChart({
    super.key,
    required this.candles,
    required this.signal,
    required this.sym,
    required this.tf,
    required this.layers,
  });

  @override
  State<NativeChart> createState() => _NativeChartState();
}

class _NativeChartState extends State<NativeChart> {
  double visible = 90, shift = 0, _baseVisible = 90;
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
                .clamp(-8.0, math.max(0, n - 20).toDouble())
                .toDouble();
          });
        },
        onLongPressStart: (d) => setState(() => cross = d.localPosition),
        onLongPressMoveUpdate: (d) => setState(() => cross = d.localPosition),
        onLongPressEnd: (_) => setState(() => cross = null),
        onDoubleTap: () => setState(() {
          visible = 90;
          shift = 0;
        }),
        child: CustomPaint(
          size: Size.infinite,
          painter: _Painter(widget.candles, widget.signal, widget.sym,
              widget.tf, visible, shift, cross, widget.layers),
        ),
      );
    });
  }
}

class _Painter extends CustomPainter {
  static const axisW = 58.0, timeH = 20.0;
  final List<Candle> c;
  final TradeSignal? s;
  final MarketSymbol sym;
  final String tf;
  final double visible, shift;
  final Offset? cross;
  final ChartLayers L;
  _Painter(this.c, this.s, this.sym, this.tf, this.visible, this.shift,
      this.cross, this.L);

  static const _up = AppColors.up, _down = AppColors.down;

  void _txt(Canvas cv, String t, Offset o,
      {Color color = AppColors.muted, double size = 10, Color? bg, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: t,
          style: TextStyle(
              color: color,
              fontSize: size,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
      textDirection: TextDirection.ltr,
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

  @override
  bool shouldRepaint(covariant _Painter old) => true;
}
