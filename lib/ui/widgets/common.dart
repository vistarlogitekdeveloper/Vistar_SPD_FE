import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/theme.dart';

/* ============================================================================
   The prototype's component set, one widget per CSS class. Names are kept close
   to the class they came from so the HTML and this file can be read side by
   side: `.sect-ttl` is [SectionTitle], `.pill` is [Pill], `.kpi` is [KpiCard].
   ========================================================================== */

/// `.wordmark` — the Vi·S·tar lockup, with the brand mark standing in for the
/// "s". Used on the splash, the login art and the login form.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    final markW = size * 1.28;
    final markH = size * 1.39;

    // The prototype tucks the mark into the letters either side of it with
    // negative margins (`.wordmark.md i{margin:0 -3px 0 -4px}`). CSS allows
    // that; Flutter's Padding asserts `padding.isNonNegative` and throws.
    //
    // The equivalent is to give the mark a slot narrower than the mark itself
    // and let it draw past the edges: the layout advances by the reduced width
    // while the glyph still paints at full size, which is exactly what a
    // negative margin does.
    final pullLeft = size * 0.11;
    final pullRight = size * 0.08;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('Vi', style: wordmark(size: size)),
        SizedBox(
          width: markW - pullLeft - pullRight,
          height: markH,
          child: OverflowBox(
            maxWidth: markW,
            maxHeight: markH,
            child: Image.asset(
              'assets/brand/vistar_s.png',
              width: markW,
              height: markH,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
        Text('tar', style: wordmark(size: size)),
      ],
    );
  }
}

/// `.smark` — the standalone brand mark, with the prototype's
/// `filter: drop-shadow(0 0 Npx rgba(224,33,138,.5))` glow.
class SMark extends StatelessWidget {
  const SMark({
    super.key,
    this.width = 34,
    this.height,
    this.opacity = 1,
    this.glow = true,
    this.glowRadius = 18,
  });

  final double width;
  final double? height;
  final double opacity;
  final bool glow;

  /// Matches the CSS blur radius; the glow is scaled from it.
  final double glowRadius;

  @override
  Widget build(BuildContext context) {
    final h = height ?? width * 1.06;
    final img = Image.asset(
      'assets/brand/vistar_s.png',
      width: width,
      height: h,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
    if (!glow) return Opacity(opacity: opacity, child: img);

    // A `BoxShadow` on a `DecoratedBox` draws a rectangle the size of the
    // child, which around a transparent PNG reads as a glowing box rather than
    // a glowing mark — which is exactly what it looked like. CSS
    // `drop-shadow()` follows the image's alpha, so the equivalent here is a
    // blurred, tinted copy of the mark painted behind the crisp one.
    //
    // The glow layer is given room to bleed with an `OverflowBox`, so it is not
    // clipped at the mark's own bounds while the widget still measures exactly
    // `width` × `h` — every call site sizes this thing precisely.
    final bleed = glowRadius;
    return Opacity(
      opacity: opacity,
      child: SizedBox(
        width: width,
        height: h,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            OverflowBox(
              maxWidth: width + bleed * 2,
              maxHeight: h + bleed * 2,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: glowRadius / 3, sigmaY: glowRadius / 3),
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Brand.pink.withValues(alpha: Brand.isLight ? 0.35 : 0.5),
                    BlendMode.srcATop,
                  ),
                  child: img,
                ),
              ),
            ),
            img,
          ],
        ),
      ),
    );
  }
}

/// Text painted with the brand ribbon — `.val.grad`, `.crumb em`, `.elapsed`.
class GradientText extends StatelessWidget {
  const GradientText(this.text, {super.key, required this.style, this.textAlign});

  final String text;
  final TextStyle style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => ShaderMask(
        shaderCallback: (b) => Brand.ribbon.createShader(b),
        blendMode: BlendMode.srcIn,
        child: Text(text, style: style.copyWith(color: Colors.white), textAlign: textAlign),
      );
}

/// `.sect-ttl .acc` — the little ribbon bar before a section title.
class RibbonAccent extends StatelessWidget {
  const RibbonAccent({super.key, this.width = 5, this.height = 16});

  final double width, height;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(gradient: Brand.ribbon, borderRadius: BorderRadius.circular(6)),
      );
}

/// `.sect-ttl` — accent, title, optional right-hand caption.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing, this.trailingWidget});

  final String title;
  final String? trailing;
  final Widget? trailingWidget;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 13),
        child: Row(children: [
          const RibbonAccent(),
          const SizedBox(width: 9),
          Flexible(child: Text(title, style: body(size: 15, weight: FontWeight.w800))),
          const Spacer(),
          ?trailingWidget,
          if (trailingWidget == null && trailing != null)
            Text(trailing!, style: body(size: 12.5, weight: FontWeight.w600, color: Brand.txt3)),
        ]),
      );
}

/// `.card` — gradient fill, hairline border, and the faint corner brand mark.
class SpdCard extends StatelessWidget {
  const SpdCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.cornerMark = true,
    this.onTap,
    this.borderColor,
    this.fill,
  });

  final Widget child;
  final EdgeInsets padding;
  final bool cornerMark;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Gradient? fill;

  @override
  Widget build(BuildContext context) {
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(Brand.r),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: fill ?? Brand.cardFill,
          borderRadius: BorderRadius.circular(Brand.r),
          border: Border.all(color: borderColor ?? Brand.line),
        ),
        child: Stack(children: [
          // .card .corner-s { right:-26px; bottom:-30px; width:120px }
          if (cornerMark)
            Positioned(
              right: -26,
              bottom: -30,
              width: 120,
              height: 120,
              child: IgnorePointer(
                child: Opacity(
                  opacity: Brand.cornerMarkOpacity,
                  child: Image.asset(
                    'assets/brand/vistar_s.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          Padding(padding: padding, child: child),
        ]),
      ),
    );
    if (onTap == null) return card;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(Brand.r), child: card);
  }
}

/// A card with a [SectionTitle] already in place.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    this.title,
    this.trailingText,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.cornerMark = true,
  });

  final String? title;
  final String? trailingText;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;
  final bool cornerMark;

  @override
  Widget build(BuildContext context) => SpdCard(
        padding: padding,
        cornerMark: cornerMark,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title != null) SectionTitle(title!, trailing: trailingText, trailingWidget: trailing),
          child,
        ]),
      );
}

/// `.kpi` — icon tile, big value, caption, optional delta chip.
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.icon,
    required this.value,
    required this.caption,
    this.extra,
    this.gradient = false,
  });

  final IconData icon;
  final String value;
  final String caption;
  final Widget? extra;
  final bool gradient;

  @override
  Widget build(BuildContext context) {
    final valStyle = display(size: 30, height: 1);
    return SpdCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Brand.pink.withValues(alpha: Brand.isLight ? 0.10 : 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 18, color: Brand.isLight ? const Color(0xFFC2186F) : Brand.pink),
          ),
          const Spacer(),
          if (extra != null) Flexible(child: extra!),
        ]),
        const SizedBox(height: 14),
        gradient
            ? GradientText(value, style: valStyle)
            : Text(value, style: valStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 6),
        Text(caption, style: body(size: 12, weight: FontWeight.w600, color: Brand.txt3)),
      ]),
    );
  }
}

/// `.kpi .delta` — the small chip beside a KPI icon.
class DeltaChip extends StatelessWidget {
  const DeltaChip(this.text, {super.key, this.tone = PillTone.ok});

  final String text;
  final PillTone tone;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: tone.fill, borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: body(size: 11.5, weight: FontWeight.w700, color: tone.ink)),
      );
}

/// `.pill` — dot plus label in a tinted capsule.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.tone = PillTone.neutral, this.dot = true, this.size = 11.5, this.icon});

  final String text;
  final PillTone tone;
  final bool dot;
  final double size;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: tone.fill, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: size + 1, color: tone.ink), const SizedBox(width: 6)]
          else if (dot) ...[
            Container(width: 6, height: 6, decoration: BoxDecoration(color: tone.dot, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          Text(text, style: body(size: size, weight: FontWeight.w700, color: tone.ink)),
        ]),
      );
}

/// A [Pill] coloured by the prototype's status map.
class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key, this.size = 11.5});

  final String status;
  final double size;

  @override
  Widget build(BuildContext context) => Pill(status, tone: Brand.statusTone(status), size: size);
}

/// `.avatar` — ribbon-filled initials tile.
class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key, this.size = 34});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: Brand.ribbon,
          borderRadius: BorderRadius.circular(size * 0.32),
        ),
        child: Text(
          initials(name),
          style: body(size: size * 0.37, weight: FontWeight.w800, color: Colors.white, letterSpacing: 0.3),
        ),
      );
}

/// `.phead` — crumb with a gradient accent word, title, blurb and action row.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.crumb,
    required this.accent,
    required this.title,
    this.blurb,
    this.blurbWidget,
    this.actions = const [],
  });

  final String crumb;
  final String accent;
  final String title;
  final String? blurb;
  final Widget? blurbWidget;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 980;
    final head = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Flexible(child: Text(crumb.toUpperCase(), style: eyebrow(size: 11.5, tracking: 0.7))),
        const SizedBox(width: 5),
        Flexible(
          child: GradientText(accent.toUpperCase(), style: eyebrow(size: 11.5, tracking: 0.7)),
        ),
      ]),
      const SizedBox(height: 9),
      Text(title, style: display(size: narrow ? 23 : 29)),
      if (blurbWidget != null) ...[
        const SizedBox(height: 7),
        ConstrainedBox(constraints: const BoxConstraints(maxWidth: 660), child: blurbWidget!),
      ] else if (blurb != null) ...[
        const SizedBox(height: 7),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 660),
          child: Text(blurb!, style: body(size: 13.5, color: Brand.txt3, height: 1.55)),
        ),
      ],
    ]);

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: narrow
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              head,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(spacing: 9, runSpacing: 9, children: actions),
              ],
            ])
          : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: head),
              if (actions.isNotEmpty) ...[
                const SizedBox(width: 18),
                Wrap(spacing: 9, runSpacing: 9, alignment: WrapAlignment.end, children: actions),
              ],
            ]),
    );
  }
}

/// Rich blurb text that mixes plain and bold runs, as several page headers do.
class BlurbText extends StatelessWidget {
  const BlurbText(this.spans, {super.key});

  /// Each entry is (text, bold).
  final List<(String, bool)> spans;

  @override
  Widget build(BuildContext context) => Text.rich(
        TextSpan(children: [
          for (final (t, bold) in spans)
            TextSpan(
              text: t,
              style: body(
                size: 13.5,
                color: bold ? Brand.txt2 : Brand.txt3,
                weight: bold ? FontWeight.w700 : FontWeight.w500,
                height: 1.55,
              ),
            ),
        ]),
      );
}

/// `.btn-grad` — the primary ribbon button.
class GradButton extends StatelessWidget {
  const GradButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.small = false,
    this.big = false,
    this.expand = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool small, big, expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final pad = big
        ? const EdgeInsets.symmetric(horizontal: 20, vertical: 20)
        : small
            ? const EdgeInsets.symmetric(horizontal: 14, vertical: 9)
            : const EdgeInsets.symmetric(horizontal: 18, vertical: 13);
    final radius = big ? 16.0 : small ? 10.0 : Brand.rSm;
    final fs = big ? 17.0 : small ? 13.0 : 14.0;

    final btn = Opacity(
      opacity: enabled ? 1 : 0.45,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: Brand.ribbon,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: enabled
              ? [BoxShadow(color: Brand.pink.withValues(alpha: 0.55), blurRadius: 34, spreadRadius: -14, offset: const Offset(0, 14))]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(radius),
            child: Padding(
              padding: pad,
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: big ? 20 : 16, color: Colors.white),
                    const SizedBox(width: 9),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      style: body(size: fs, weight: FontWeight.w700, color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

/// `.btn-ghost` — the secondary button.
class GhostButton extends StatelessWidget {
  const GhostButton({super.key, required this.label, this.icon, this.onPressed, this.small = true, this.danger = false});

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool small, danger;

  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: danger ? Brand.bad : Brand.txt,
          backgroundColor: danger ? Brand.bad.withValues(alpha: 0.13) : Brand.surface2,
          side: BorderSide(color: danger ? Brand.bad.withValues(alpha: 0.28) : Brand.line),
          padding: small
              ? const EdgeInsets.symmetric(horizontal: 14, vertical: 9)
              : const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(small ? 10 : Brand.rSm)),
          textStyle: body(size: small ? 13 : 14, weight: FontWeight.w700),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 15), const SizedBox(width: 8)],
          Text(label),
        ]),
      );
}

/// `.iconbtn` — the square icon button used in the top bar.
class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, this.onTap, this.tooltip, this.dot = false, this.size = 36});

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool dot;
  final double size;

  @override
  Widget build(BuildContext context) {
    final btn = SizedBox(
      width: size,
      height: size,
      child: Material(
        color: Brand.field,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: Stack(children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Brand.fieldLine),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 17, color: Brand.txt2),
              ),
            ),
            if (dot)
              Positioned(
                top: 7,
                right: 8,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: Brand.pink,
                    shape: BoxShape.circle,
                    border: Border.all(color: Brand.bg2, width: 2),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// `.lbl` + field, the standard vertical form field.
class Field extends StatelessWidget {
  const Field({super.key, required this.label, required this.child, this.required = false, this.hint, this.bottom = 15});

  final String label;
  final Widget child;
  final bool required;
  final String? hint;
  final double bottom;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text.rich(TextSpan(children: [
            TextSpan(text: label.toUpperCase(), style: fieldLabel()),
            if (required) TextSpan(text: ' *', style: fieldLabel(color: Brand.bad)),
          ])),
          const SizedBox(height: 7),
          child,
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(hint!, style: body(size: 12, color: Brand.txt3)),
          ],
        ]),
      );
}

/// `select.inp` — a dropdown styled like the prototype's inputs.
class SpdDropdown<T> extends StatelessWidget {
  const SpdDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.dense = false,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
        initialValue: value,
        items: items,
        onChanged: onChanged,
        isExpanded: true,
        dropdownColor: Brand.surface2,
        borderRadius: BorderRadius.circular(13),
        icon: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Brand.txt3),
        style: body(size: dense ? 13 : 14, color: Brand.txt),
        decoration: InputDecoration(
          filled: true,
          fillColor: Brand.field,
          isDense: true,
          contentPadding: dense
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
              : const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Brand.rSm),
            borderSide: BorderSide(color: Brand.fieldLine),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Brand.rSm),
            borderSide: BorderSide(color: Brand.pink.withValues(alpha: 0.6), width: 1.4),
          ),
        ),
      );
}

/// `.filterbar` — a bordered row of filter fields with a reset button.
class FilterBar extends StatelessWidget {
  const FilterBar({super.key, required this.children, this.onReset});

  final List<Widget> children;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
        decoration: BoxDecoration(
          gradient: Brand.cardFill,
          border: Border.all(color: Brand.line),
          borderRadius: BorderRadius.circular(Brand.r),
        ),
        child: LayoutBuilder(builder: (context, c) {
          final perRow = c.maxWidth < 620 ? 1 : c.maxWidth < 980 ? 2 : children.length;
          final w = perRow == 1
              ? c.maxWidth
              : (c.maxWidth - 10 * (perRow - 1) - (onReset != null ? 96 : 0)) / perRow;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              for (final f in children) SizedBox(width: math.max(150, w), child: f),
              if (onReset != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: GhostButton(label: 'Reset', onPressed: onReset),
                ),
            ],
          );
        }),
      );
}

/// `.alertbox` — the tinted advisory block with an icon and a bold lead line.
class AlertBox extends StatelessWidget {
  const AlertBox({super.key, required this.tone, required this.title, required this.message, this.icon});

  final AlertTone tone;
  final String title;
  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: BoxDecoration(
          color: tone.fill,
          border: Border.all(color: tone.border),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon ?? _defaultIcon, size: 16, color: tone.icon),
          const SizedBox(width: 11),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: body(size: 13, weight: FontWeight.w700, color: tone.ink)),
              const SizedBox(height: 3),
              Text(message, style: body(size: 13, color: tone.ink, height: 1.55)),
            ]),
          ),
        ]),
      );

  IconData get _defaultIcon => switch (tone) {
        AlertTone.ok => Icons.check_rounded,
        AlertTone.bad || AlertTone.warn => Icons.warning_amber_rounded,
        AlertTone.info => Icons.shield_outlined,
      };
}

/// `.bar` — the thin ribbon progress bar.
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.percent, this.thin = false});

  final int percent;
  final bool thin;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: thin ? 5 : 7,
          child: Stack(children: [
            Positioned.fill(child: ColoredBox(color: Brand.track)),
            FractionallySizedBox(
              widthFactor: (percent.clamp(0, 100)) / 100,
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: Brand.ribbon, borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ]),
        ),
      );
}

/// `.barrow` — label row above a thin bar, used by the productivity panels.
class BarRow extends StatelessWidget {
  const BarRow({super.key, required this.label, required this.value, required this.percent, this.leading});

  final Widget label;
  final String value;
  final int percent;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 13),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (leading != null) ...[leading!, const SizedBox(width: 7)],
            Flexible(child: label),
            const SizedBox(width: 12),
            // Flexible, not a trailing Text after a Spacer: on a tablet-width
            // column the figures are the longer half of the row, and an
            // unconstrained Text there loses the box count off the right edge.
            Flexible(
              child: Text(
                value,
                style: body(size: 12.5, weight: FontWeight.w600, color: Brand.txt3),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
          const SizedBox(height: 6),
          ProgressBar(percent: percent, thin: true),
        ]),
      );
}

/// `.ring-prog` — the conic-gradient completion ring.
class RingProgress extends StatelessWidget {
  const RingProgress({super.key, required this.percent, required this.label, this.size = 132});

  final int percent;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(percent: percent.clamp(0, 100), track: Brand.track, hole: Brand.isLight ? const Color(0xFFFDFCFF) : const Color(0xFF0E0C1B)),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$percent%', style: display(size: 27, height: 1)),
              const SizedBox(height: 3),
              Text(label.toUpperCase(), style: eyebrow(size: 10.5, tracking: 0.6)),
            ]),
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.percent, required this.track, required this.hole});

  final int percent;
  final Color track, hole;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final centre = rect.center;
    final radius = size.width / 2;

    // conic-gradient(from -90deg, #7A1FB0 0%, #E0218A 45%, #F0480C 75%, #F0C000 100%)
    // The sweep covers only the completed share; the rest is the track colour.
    canvas.drawCircle(centre, radius, Paint()..color = track);
    if (percent > 0) {
      final sweep = 2 * math.pi * percent / 100;
      final shader = SweepGradient(
        startAngle: 0,
        endAngle: sweep,
        colors: const [Color(0xFF7A1FB0), Color(0xFFE0218A), Color(0xFFF0480C), Color(0xFFF0C000)],
        stops: const [0.0, 0.45, 0.75, 1.0],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);
      canvas.drawArc(rect, -math.pi / 2, sweep, true, Paint()..shader = shader);
    }
    // .ring-prog::after { inset: 11px; background: #0E0C1B }
    canvas.drawCircle(centre, radius - 11, Paint()..color = hole);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.percent != percent || old.track != track || old.hole != hole;
}

/* -------------------------------------------------------------- tables --- */

/// Wraps [child] in a [Flexible] only when the surrounding column has a bounded
/// height to divide. Handing a flex to a shrink-wrapping column is the
/// contradiction `RenderFlex` asserts on, and asserts are stripped from release
/// builds — so without this the fault is invisible until someone runs the app.
Widget _maybeFlexible(bool bounded, Widget child) =>
    bounded ? Flexible(child: child) : child;

/// One column of a [SpdTable].
class SpdCol {
  const SpdCol(this.title, {this.right = false, this.width, this.wrap = false});

  final String title;

  /// `.tar` — right-aligned, for quantities.
  final bool right;

  /// Fixed width; otherwise the column is sized from its content.
  final double? width;

  /// `white-space:normal` — the column may wrap onto several lines.
  final bool wrap;
}

/// One row, optionally tappable for a drill-down.
class SpdRow {
  const SpdRow(this.cells, {this.onTap});

  final List<Widget> cells;
  final VoidCallback? onTap;
}

/// `.tbl-wrap` — a bordered, horizontally scrollable table with a sticky-looking
/// header, the hover tint on rows, and the prototype's empty state.
class SpdTable extends StatefulWidget {
  const SpdTable({
    super.key,
    required this.columns,
    required this.rows,
    this.emptyMessage = 'No records match the current filter.',
    this.maxHeight,
  });

  final List<SpdCol> columns;
  final List<SpdRow> rows;
  final String emptyMessage;
  final double? maxHeight;

  @override
  State<SpdTable> createState() => _SpdTableState();
}

class _SpdTableState extends State<SpdTable> {
  final _h = ScrollController();
  int? _hovered;

  @override
  void dispose() {
    _h.dispose();
    super.dispose();
  }

  double _widthOf(SpdCol c) => c.width ?? (c.wrap ? 280 : 132);

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Brand.surface,
          border: Border.all(color: Brand.line),
          borderRadius: BorderRadius.circular(Brand.r),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 44),
        child: Column(children: [
          Opacity(
            opacity: 0.28,
            child: Image.asset('assets/brand/vistar_s.png', width: 56, errorBuilder: (_, _, _) => const SizedBox.shrink()),
          ),
          const SizedBox(height: 14),
          Text(widget.emptyMessage, style: body(size: 13.5, color: Brand.txt3), textAlign: TextAlign.center),
        ]),
      );
    }

    final totalW = widget.columns.fold<double>(0, (s, c) => s + _widthOf(c));

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Brand.surface,
        border: Border.all(color: Brand.line),
        borderRadius: BorderRadius.circular(Brand.r),
      ),
      child: LayoutBuilder(builder: (context, c) {
        // The header and every row carry this much horizontal padding, so it is
        // not available to the columns. Sizing them against the full width
        // instead overflows each row by exactly this much — which release
        // builds clip in silence and only an assert ever reports.
        const rowPadding = 32.0; // EdgeInsets.symmetric(horizontal: 16)
        final content = (c.maxWidth - rowPadding).clamp(0.0, double.infinity);

        final fits = totalW <= content;
        final width = fits ? c.maxWidth : totalW + rowPadding;
        // When the columns fit, share the slack proportionally so the table
        // fills its card rather than leaving a gutter on the right.
        final scale = fits && totalW > 0 ? content / totalW : 1.0;

        // A table with no `maxHeight` shrink-wraps its rows and is almost always
        // inside a page-level scroll view, so it is laid out with an unbounded
        // height. A Column that both shrink-wraps and hands a child a flex is a
        // contradiction the framework asserts on, so the body only takes a flex
        // when there is a bounded height to divide.
        final bounded = widget.maxHeight != null;

        final table = SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            children: [
            // thead
            Container(
              decoration: BoxDecoration(
                color: Brand.surface2,
                border: Border(bottom: BorderSide(color: Brand.line)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(children: [
                for (final col in widget.columns)
                  SizedBox(
                    width: _widthOf(col) * scale - (col == widget.columns.last ? 0 : 0),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(
                        col.title.toUpperCase(),
                        style: eyebrow(size: 11, tracking: 0.6),
                        textAlign: col.right ? TextAlign.right : TextAlign.left,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ]),
            ),
            // tbody
            _maybeFlexible(
              bounded,
              ListView.builder(
                shrinkWrap: !bounded,
                physics: bounded ? null : const NeverScrollableScrollPhysics(),
                itemCount: widget.rows.length,
                itemBuilder: (context, i) {
                  final row = widget.rows[i];
                  return MouseRegion(
                    onEnter: (_) => setState(() => _hovered = i),
                    onExit: (_) => setState(() => _hovered = null),
                    cursor: row.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: row.onTap,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _hovered == i ? Brand.surface2 : Colors.transparent,
                          border: i == widget.rows.length - 1
                              ? null
                              : Border(bottom: BorderSide(color: Brand.line)),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            for (var ci = 0; ci < widget.columns.length; ci++)
                              SizedBox(
                                width: _widthOf(widget.columns[ci]) * scale,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: Align(
                                    alignment: widget.columns[ci].right
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: ci < row.cells.length ? row.cells[ci] : const SizedBox.shrink(),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            ],
          ),
        );

        final constrained = widget.maxHeight == null
            ? table
            : ConstrainedBox(constraints: BoxConstraints(maxHeight: widget.maxHeight!), child: table);

        return fits
            ? constrained
            : Scrollbar(
                controller: _h,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _h,
                  scrollDirection: Axis.horizontal,
                  child: constrained,
                ),
              );
      }),
    );
  }
}

/* ---- cell helpers, matching the prototype's td classes ------------------ */

/// `td` — the default muted cell.
Widget cell(String text, {int maxLines = 1}) =>
    Text(text, style: body(size: 13, color: Brand.txt2), maxLines: maxLines, overflow: TextOverflow.ellipsis);

/// `td.mono` — tabular figures.
Widget monoCell(String text, {Color? color, FontWeight weight = FontWeight.w600}) =>
    Text(text, style: mono(size: 13, weight: weight, color: color ?? Brand.txt2), maxLines: 1, overflow: TextOverflow.ellipsis);

/// `td.strong.mono` — the identifying column of a row.
Widget strongCell(String text) =>
    Text(text, style: mono(size: 13, weight: FontWeight.w700, color: Brand.txt), maxLines: 1, overflow: TextOverflow.ellipsis);

/// `td[style="white-space:normal"]` — a cell allowed to wrap.
Widget wrapCell(String text, {Color? color}) =>
    Text(text, style: body(size: 13, color: color ?? Brand.txt2, height: 1.45));

/// `.datacell` — avatar plus name.
Widget personCell(String name) => Row(mainAxisSize: MainAxisSize.min, children: [
      Avatar(name, size: 27),
      const SizedBox(width: 9),
      Flexible(child: Text(name, style: body(size: 13, color: Brand.txt), maxLines: 1, overflow: TextOverflow.ellipsis)),
    ]);

/* -------------------------------------------------------------- pieces --- */

/// `.kv` — a definition list with the value right-aligned.
class KeyValues extends StatelessWidget {
  const KeyValues(this.pairs, {super.key});

  final List<(String, String)> pairs;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final (k, v) in pairs)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(k, style: body(size: 13, weight: FontWeight.w600, color: Brand.txt3)),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(v,
                      style: body(size: 13, weight: FontWeight.w700),
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),
        ],
      );
}

/// `.listrow` — a bordered row inside a stack.
class ListRow extends StatelessWidget {
  const ListRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          // A list row sits inside a card, which in light mode is also white.
          color: Brand.field,
          border: Border.all(color: Brand.fieldLine),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(children: children),
      );
}

/// `.hairline`
class Hairline extends StatelessWidget {
  const Hairline({super.key, this.margin = 18});

  final double margin;

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: Brand.line, margin: EdgeInsets.symmetric(vertical: margin));
}

/// `.chip` — a filter chip.
class SpdChip extends StatelessWidget {
  const SpdChip(this.label, {super.key, this.selected = false, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? Brand.pink.withValues(alpha: 0.14) : Brand.surface2,
            border: Border.all(color: selected ? Brand.pink.withValues(alpha: 0.42) : Brand.line),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: body(
              size: 12.5,
              weight: FontWeight.w700,
              color: selected ? PillTone.pink.ink : Brand.txt2,
            ),
          ),
        ),
      );
}

/// `.dz` — the GRN drop zone.
class DropZone extends StatefulWidget {
  const DropZone({super.key, required this.title, required this.subtitle, this.onTap});

  final String title, subtitle;
  final VoidCallback? onTap;

  @override
  State<DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<DropZone> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
            decoration: BoxDecoration(
              color: _hover ? Brand.pink.withValues(alpha: 0.05) : Brand.surface2.withValues(alpha: 0.4),
              border: Border.all(
                color: _hover ? Brand.pink.withValues(alpha: 0.45) : Brand.line2,
                width: 1.5,
                style: BorderStyle.solid,
              ),
              borderRadius: BorderRadius.circular(Brand.r),
            ),
            child: Column(children: [
              Opacity(
                opacity: 0.5,
                child: Image.asset('assets/brand/vistar_s.png', width: 46, errorBuilder: (_, _, _) => const SizedBox.shrink()),
              ),
              const SizedBox(height: 12),
              Text(widget.title, style: body(size: 14, weight: FontWeight.w800), textAlign: TextAlign.center),
              const SizedBox(height: 5),
              Text(widget.subtitle,
                  style: body(size: 12.5, color: Brand.txt3), textAlign: TextAlign.center),
            ]),
          ),
        ),
      );
}

/// `.partcard` — the touch target on the member's screens.
class PartCard extends StatelessWidget {
  const PartCard({super.key, required this.child, this.selected = false, this.onTap});

  final Widget child;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? Brand.pink.withValues(alpha: 0.07) : Brand.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: selected ? Brand.pink.withValues(alpha: 0.6) : Brand.line),
              borderRadius: BorderRadius.circular(16),
            ),
            child: child,
          ),
        ),
      );
}

/// `.tablecard` — one packing table on the allocation board.
class TableCard extends StatelessWidget {
  const TableCard({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SpdCard(
        padding: const EdgeInsets.all(15),
        onTap: onTap,
        child: child,
      );
}

/// `.emailprev` — the hourly report as the Supervisor receives it.
class EmailPreview extends StatelessWidget {
  const EmailPreview({super.key, required this.subject, required this.meta, required this.content});

  final String subject, meta;
  final Widget content;

  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          border: Border.all(color: Brand.line2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.infinity,
            color: Brand.surface2,
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(subject, style: body(size: 13.5, weight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(meta, style: body(size: 12.5, color: Brand.txt3)),
            ]),
          ),
          Container(
            width: double.infinity,
            color: Brand.surface,
            padding: const EdgeInsets.all(15),
            child: content,
          ),
        ]),
      );
}

/// `.grid.gN` — responsive equal-width columns with the prototype's breakpoints.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({super.key, required this.children, this.columns = 3, this.spacing = 16, this.childAspect});

  final List<Widget> children;
  final int columns;
  final double spacing;
  final double? childAspect;

  @override
  Widget build(BuildContext context) {
    // The prototype's breakpoints are CSS media queries, so they read the
    // *viewport*, not the element. Deciding the column count from the local
    // constraint instead would drop the four KPI tiles to two on a 1440px
    // screen, purely because the sidebar takes 248 of them.
    //   @media (max-width:1180px){ .g4 → 2 }
    //   @media (max-width:980px) { .g2,.g3 → 1 }
    //   @media (max-width:640px) { .grid.g4 → 2 }
    final vw = MediaQuery.sizeOf(context).width;
    var n = columns;
    if (columns >= 4 && vw <= 1180) n = 2;
    if (columns <= 3 && vw <= 980) n = 1;
    if (vw <= 640) n = columns >= 4 ? 2 : 1;
    n = n.clamp(1, columns);

    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - spacing * (n - 1)) / n;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [for (final ch in children) SizedBox(width: w, child: ch)],
      );
    });
  }
}

/// `.split-l` / `.split-r` — a fixed side column that stacks below 1100px.
class SplitPane extends StatelessWidget {
  const SplitPane({
    super.key,
    required this.main,
    required this.side,
    this.sideWidth = 340,
    this.sideFirst = false,
    this.spacing = 16,
  });

  final Widget main, side;
  final double sideWidth, spacing;
  final bool sideFirst;

  @override
  Widget build(BuildContext context) {
    // @media (max-width:1100px){ .split-l,.split-r{grid-template-columns:1fr} }
    // Viewport-based, for the same reason as [ResponsiveGrid].
    if (MediaQuery.sizeOf(context).width <= 1100) {
      return Column(children: [
        if (sideFirst) ...[side, SizedBox(height: spacing), main]
        else ...[main, SizedBox(height: spacing), side],
      ]);
    }
    final fixed = SizedBox(width: sideWidth, child: side);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: sideFirst
        ? [fixed, SizedBox(width: spacing), Expanded(child: main)]
        : [Expanded(child: main), SizedBox(width: spacing), fixed]);
  }
}

/* ------------------------------------------------------- toast & modal --- */

/// `#toasts` — the bottom-right stack. Kept as an overlay entry so it survives
/// a screen rebuild, which is what the live dashboard does every refresh.
class Toast {
  static void show(BuildContext context, {required String title, required String message, AlertTone tone = AlertTone.ok}) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    late OverlayEntry entry;
    entry = OverlayEntry(builder: (context) => _ToastCard(title: title, message: message, tone: tone));
    overlay.insert(entry);
    Future.delayed(Duration(milliseconds: tone == AlertTone.bad ? 6200 : 4200), () {
      entry.remove();
    });
  }

  static void ok(BuildContext c, String title, String msg) => show(c, title: title, message: msg);
  static void bad(BuildContext c, String title, String msg) => show(c, title: title, message: msg, tone: AlertTone.bad);
  static void warn(BuildContext c, String title, String msg) => show(c, title: title, message: msg, tone: AlertTone.warn);
}

class _ToastCard extends StatefulWidget {
  const _ToastCard({required this.title, required this.message, required this.tone});

  final String title, message;
  final AlertTone tone;

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 280))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width <= 640;
    return Positioned(
      right: narrow ? 12 : 22,
      left: narrow ? 12 : null,
      bottom: narrow ? 12 : 22,
      child: SlideTransition(
        position: Tween(begin: const Offset(0.16, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutBack)),
        child: FadeTransition(
          opacity: _c,
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: BoxConstraints(minWidth: narrow ? 0 : 280, maxWidth: narrow ? double.infinity : 400),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: Brand.isLight
                      ? [const Color(0xFFFFFFFF), const Color(0xFFFAF7FF)]
                      : [Brand.surface3.withValues(alpha: 0.98), Brand.surface.withValues(alpha: 0.98)],
                ),
                border: Border.all(color: Brand.line2),
                borderRadius: BorderRadius.circular(14),
                boxShadow: Brand.shadow,
              ),
              child: IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  // .toast::before — the 3px accent stripe
                  Container(
                    width: 3,
                    decoration: BoxDecoration(
                      gradient: widget.tone == AlertTone.bad
                          ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFB6F84), Color(0xFFC8102E)])
                          : widget.tone == AlertTone.warn
                              ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF0C000), Color(0xFFF06000)])
                              : Brand.ribbon,
                    ),
                  ),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 13, 15, 13),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(color: widget.tone.fill, borderRadius: BorderRadius.circular(8)),
                          child: Icon(
                            widget.tone == AlertTone.ok ? Icons.check_rounded : Icons.warning_amber_rounded,
                            size: 14,
                            color: widget.tone.icon,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Flexible(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                            Text(widget.title, style: body(size: 13.5, weight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text(widget.message, style: body(size: 12.5, color: Brand.txt2, height: 1.45)),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.modal` — the centred dialog with the prototype's head/body/foot sections.
Future<T?> showSpdModal<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required Widget Function(BuildContext context, void Function(void Function()) setModalState) content,
  List<Widget> Function(BuildContext context, void Function(void Function()) setModalState)? actions,
  bool wide = false,
  bool dismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierColor: Brand.isLight ? const Color(0x4D28164E) : const Color(0xA804030A),
    builder: (context) => StatefulBuilder(
      builder: (context, setModalState) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: wide ? 880 : 620,
            maxHeight: MediaQuery.sizeOf(context).height * 0.88,
          ),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: Brand.isLight
                    ? [const Color(0xFFFFFFFF), const Color(0xFFF8F5FE)]
                    : [const Color(0xFF16142A), const Color(0xFF110F1E)],
              ),
              border: Border.all(color: Brand.line2),
              borderRadius: BorderRadius.circular(Brand.rLg),
              boxShadow: Brand.shadow,
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: display(size: 19)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(subtitle, style: body(size: 12.5, color: Brand.txt3)),
                      ],
                    ]),
                  ),
                  const SizedBox(width: 14),
                  _CloseButton(onTap: () => Navigator.of(context).pop()),
                ]),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                  child: content(context, setModalState),
                ),
              ),
              if (actions != null)
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: Brand.line))),
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 10,
                    runSpacing: 10,
                    children: actions(context, setModalState),
                  ),
                ),
            ]),
          ),
        ),
      ),
    ),
  );
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 32,
        height: 32,
        child: Material(
          color: Brand.surface2,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Brand.line),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.close_rounded, size: 16, color: Brand.txt3),
            ),
          ),
        ),
      );
}

/* --------------------------------------------------------------- misc ---- */

/// The route-change loader (`#routeload`) and any in-card wait.
class SpdLoader extends StatelessWidget {
  const SpdLoader({super.key, this.size = 64, this.label});

  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _Breathing(child: SMark(width: size)),
          if (label != null) ...[
            const SizedBox(height: 14),
            Text(label!, style: body(size: 12.5, color: Brand.txt3)),
          ],
        ]),
      );
}

/// `@keyframes breathe` — the gentle pulse on the brand mark.
class _Breathing extends StatefulWidget {
  const _Breathing({required this.child});

  final Widget child;

  @override
  State<_Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<_Breathing> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
        scale: Tween(begin: 0.92, end: 1.04).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
        child: widget.child,
      );
}

/// A failed fetch, shown in place of a screen's content with a retry.
class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => SpdCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AlertBox(tone: AlertTone.bad, title: 'Could not load this screen', message: message),
          if (onRetry != null) ...[
            const SizedBox(height: 14),
            GhostButton(label: 'Try again', icon: Icons.refresh_rounded, onPressed: onRetry),
          ],
        ]),
      );
}

/// Digits-only input formatter for the quantity pads (BR-02).
final digitsOnly = FilteringTextInputFormatter.digitsOnly;
