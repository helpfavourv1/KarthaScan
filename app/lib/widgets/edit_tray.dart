import 'package:flutter/material.dart';
import '../core/utils/constants.dart';
import 'ios_pressable.dart';

class EditTray extends StatefulWidget {
  const EditTray({
    super.key,
    required this.onMarkup,
    required this.onSign,
    required this.onWatermark,
    required this.onOcr,
    required this.onConvert,
    required this.onCompress,
    required this.onRotate,
    required this.onResize,
    required this.onPages,
    required this.onFilter,
    required this.onCrop,
    required this.onText,
    required this.onNote,
    required this.onDate,
    required this.onCheckbox,
    required this.onSeal,
    required this.onPrint,
    required this.onEmail,
    required this.onErase,
    this.onRevert,
    this.compact = false,
  });

  final VoidCallback onMarkup;
  final VoidCallback onSign;
  final VoidCallback onWatermark;
  final VoidCallback onOcr;
  final VoidCallback onConvert;
  final VoidCallback onCompress;
  final VoidCallback onRotate;
  final VoidCallback onResize;
  final VoidCallback onPages;
  final VoidCallback onFilter;
  final VoidCallback onCrop;
  final VoidCallback onText;
  final VoidCallback onNote;
  final VoidCallback onDate;
  final VoidCallback onCheckbox;
  final VoidCallback onSeal;
  final VoidCallback onPrint;
  final VoidCallback onEmail;
  final VoidCallback onErase;
  final VoidCallback? onRevert;
  final bool compact;

  @override
  State<EditTray> createState() => _EditTrayState();
}

class _EditTrayState extends State<EditTray> with SingleTickerProviderStateMixin {
  late final ScrollController _scrollController;
  late final ValueNotifier<double> _wheelAngle;
  late final AnimationController _entranceCtrl;
  late final Animation<double> _entranceAnim;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _wheelAngle = ValueNotifier<double>(0.0);
    _scrollController.addListener(() {
      _wheelAngle.value = -_scrollController.offset / 5.0;
    });
    
    _entranceCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _entranceAnim = Tween<double>(begin: 60.0, end: 0.0).animate(
      CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOutBack),
    );
    _entranceCtrl.forward();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _wheelAngle.dispose();
    _entranceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final topGrad = isDark ? const Color(0xFF2A2A2E) : const Color(0xFFFFFFFF);
    final botGrad = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFEDEDF2);
    
    final coachFill = isDark ? const Color(0xFF3A3A3E) : const Color(0xFFF8F8FA);
    final coachBorder = isDark ? const Color(0xFF4A4A4E) : const Color(0xFFD8D8DE);
    final railColor = isDark ? const Color(0xFF6E6E73) : const Color(0xFF8E8E93);
    final sleeperColor = isDark ? const Color(0xFF48484C) : const Color(0xFFC7C7CC);
    final hubColor = isDark ? const Color(0xFF111111) : const Color(0xFF3A3A3E);
    final spokeColor = isDark ? const Color(0xFF9A9AA0) : const Color(0xFFE5E5EA);
    final couplerColor = isDark ? const Color(0xFF4A4A4E) : const Color(0xFFD8D8DE);
    
    final iconColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return AnimatedBuilder(
      animation: _entranceCtrl,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_entranceAnim.value, 0),
          child: Opacity(
            opacity: _entranceCtrl.value.clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 10, vertical: widget.compact ? 3 : 6),
        height: widget.compact ? 58 : 84,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.compact ? 14 : 20),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [topGrad, botGrad],
          ),
          border: Border.all(color: isDark ? const Color(0xFF3A3A3E) : const Color(0xFFD8D8DE), width: 1),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.12), offset: const Offset(0, 1), blurRadius: 3),
            BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.10), offset: const Offset(0, 8), blurRadius: 20),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _TrackPainter(railColor, sleeperColor, widget.compact ? 48.0 : 71.0)),
              ),
            ),
            Positioned.fill(
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: widget.compact ? 8 : 12, vertical: widget.compact ? 4 : 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: _buildTrain(coachFill, coachBorder, iconColor, textColor, hubColor, spokeColor, couplerColor),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), bottomLeft: Radius.circular(20)),
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [botGrad.withValues(alpha: 1.0), botGrad.withValues(alpha: 0.0)],
                        ),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 20,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.only(topRight: Radius.circular(20), bottomRight: Radius.circular(20)),
                        gradient: LinearGradient(
                          begin: Alignment.centerRight,
                          end: Alignment.centerLeft,
                          colors: [botGrad.withValues(alpha: 1.0), botGrad.withValues(alpha: 0.0)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTrain(Color coachFill, Color coachBorder, Color iconColor, Color textColor, Color hubColor, Color spokeColor, Color couplerColor) {
    final items = <_TrayItem>[
      _TrayItem(Icons.mode_edit_outline, 'Annotate', widget.onMarkup),
      _TrayItem(Icons.draw_outlined, 'Sign', widget.onSign),
      _TrayItem(Icons.text_fields, 'Watermark', widget.onWatermark),
      _TrayItem(Icons.crop, 'OCR', widget.onOcr),
      _TrayItem(Icons.file_download_outlined, 'Convert', widget.onConvert),
      _TrayItem(Icons.compress, 'Compress', widget.onCompress),
      _TrayItem(Icons.rotate_90_degrees_ccw, 'Rotate', widget.onRotate),
      _TrayItem(Icons.aspect_ratio, 'Resize', widget.onResize),
      _TrayItem(Icons.reorder, 'Pages', widget.onPages),
      _TrayItem(Icons.filter_alt_outlined, 'Filter', widget.onFilter),
      _TrayItem(Icons.crop_free, 'Crop', widget.onCrop),
      _TrayItem(Icons.title, 'Text', widget.onText),
      _TrayItem(Icons.note_outlined, 'Note', widget.onNote),
      _TrayItem(Icons.date_range, 'Date', widget.onDate),
      _TrayItem(Icons.check_box_outlined, 'Check', widget.onCheckbox),
      _TrayItem(Icons.approval_outlined, 'Custom Seal', widget.onSeal),
      _TrayItem(Icons.print_outlined, 'Print', widget.onPrint),
      _TrayItem(Icons.mail_outline, 'Email', widget.onEmail),
      _TrayItem(Icons.brush_outlined, 'Eraser', widget.onErase),
      if (widget.onRevert != null) _TrayItem(Icons.undo, 'Revert', widget.onRevert!),
    ];

    final widgets = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      widgets.add(_buildCoach(items[i], coachFill, coachBorder, iconColor, textColor, hubColor, spokeColor));
      if (i < items.length - 1) {
        widgets.add(Container(
          width: widget.compact ? 4 : 6,
          height: widget.compact ? 3 : 4,
          margin: EdgeInsets.only(bottom: widget.compact ? 3 : 5),
          color: couplerColor,
        ));
      }
    }
    return widgets;
  }

  Widget _buildCoach(_TrayItem item, Color coachFill, Color coachBorder, Color iconColor, Color textColor, Color hubColor, Color spokeColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IOSPressable(
            onTap: item.onTap,
            child: Container(
              width: widget.compact ? 42 : 56,
              height: widget.compact ? 36 : 52,
              decoration: BoxDecoration(
                color: coachFill,
                borderRadius: BorderRadius.circular(widget.compact ? 7 : 10),
                border: Border.all(color: coachBorder, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.15),
                    offset: const Offset(0, 1),
                    blurRadius: 0,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(item.icon, color: iconColor, size: widget.compact ? 14 : 20),
                  const SizedBox(height: 2),
                  Text(
                    item.label,
                    style: TextStyle(color: textColor, fontSize: widget.compact ? 8 : 9, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            width: widget.compact ? 42 : 56,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: _wheelAngle,
                  builder: (context, angle, _) => CustomPaint(
                    size: Size(widget.compact ? 7 : 10, widget.compact ? 7 : 10),
                    painter: _WheelPainter(angle, hubColor, spokeColor),
                  ),
                ),
                ValueListenableBuilder<double>(
                  valueListenable: _wheelAngle,
                  builder: (context, angle, _) => CustomPaint(
                    size: Size(widget.compact ? 7 : 10, widget.compact ? 7 : 10),
                    painter: _WheelPainter(angle, hubColor, spokeColor),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrayItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  _TrayItem(this.icon, this.label, this.onTap);
}

class _TrackPainter extends CustomPainter {
  final Color railColor;
  final Color sleeperColor;
  final double railY;
  _TrackPainter(this.railColor, this.sleeperColor, this.railY);

  @override
  void paint(Canvas canvas, Size size) {
    // railY passed from constructor
    final railPaint = Paint()..color = railColor..strokeWidth = 2.0;
    canvas.drawLine(Offset(0, railY), Offset(size.width, railY), railPaint);
    
    final sleeperPaint = Paint()..color = sleeperColor..strokeWidth = 3.0;
    for (double x = 10; x < size.width; x += 14) {
      canvas.drawLine(Offset(x, railY - 3), Offset(x, railY + 3), sleeperPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WheelPainter extends CustomPainter {
  final double angle;
  final Color hubColor;
  final Color spokeColor;
  _WheelPainter(this.angle, this.hubColor, this.spokeColor);

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);
    
    final hubPaint = Paint()..color = hubColor;
    canvas.drawCircle(center, r, hubPaint);
    
    final spokePaint = Paint()..color = spokeColor..strokeWidth = 1.5;
    canvas.save();
    canvas.translate(r, r);
    canvas.rotate(angle);
    for (int i = 0; i < 3; i++) {
      canvas.rotate(3.14159 * 2 / 3);
      canvas.drawLine(Offset.zero, Offset(r * 0.8, 0), spokePaint);
    }
    canvas.restore();
    
    final rimPaint = Paint()..color = spokeColor..style = PaintingStyle.stroke..strokeWidth = 1.5;
    canvas.drawCircle(center, r - 0.5, rimPaint);
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) => oldDelegate.angle != angle;
}
