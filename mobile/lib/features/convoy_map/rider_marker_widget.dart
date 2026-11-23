import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../models/rider.dart';

/// Bike disc + name label.
/// - Leader: outer ring + star badge (shape, not color alone).
/// - You: different disc color and the label reads "You".
/// - Heading: a small arrow on the rim pointing where the rider is going.
/// - Offline: dimmed.
class RiderMarkerWidget extends StatelessWidget {
  const RiderMarkerWidget({
    super.key,
    required this.rider,
    this.isSelf = false,
    this.headingDeg,
    this.youLabel = 'You',
  });

  final Rider rider;
  final bool isSelf;
  final double? headingDeg;
  final String youLabel;

  static const double width = 132;
  static const double height = 86;
  static const double _disc = 40;
  static const double _box = 58;

  /// Marker alignment that puts the disc centre (not the label) on the point.
  static const Alignment anchor = Alignment(0, 0.33);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final leader = rider.isLeader;
    final discColor =
        isSelf ? scheme.tertiary : (leader ? scheme.primary : scheme.secondaryContainer);
    final iconColor =
        isSelf ? scheme.onTertiary : (leader ? scheme.onPrimary : scheme.onSecondaryContainer);
    final label = isSelf ? youLabel : rider.name;

    return Semantics(
      label: '${rider.name}${leader ? ', leader' : ''}${isSelf ? ', you' : ''}',
      child: Opacity(
        opacity: rider.status == RiderStatus.offline ? 0.5 : 1,
        child: SizedBox(
          width: width,
          height: height,
          child: Column(
            children: [
              SizedBox.square(
                dimension: _box,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (headingDeg != null)
                      Transform.rotate(
                        angle: headingDeg! * math.pi / 180,
                        child: SizedBox.square(
                          dimension: _box,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Icon(Icons.navigation, size: 16, color: discColor),
                          ),
                        ),
                      ),
                    if (leader)
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: scheme.primary, width: 3),
                        ),
                      ),
                    Container(
                      width: _disc,
                      height: _disc,
                      decoration: BoxDecoration(
                        color: discColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: scheme.surface, width: 2),
                        boxShadow: const [BoxShadow(blurRadius: 4, color: Color(0x55000000))],
                      ),
                      child: Icon(Icons.two_wheeler, size: 22, color: iconColor),
                    ),
                    if (leader)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                          child: Icon(Icons.star, size: 13, color: scheme.onPrimary),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Container(
                constraints: const BoxConstraints(maxWidth: width),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isSelf ? scheme.tertiaryContainer : scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: isSelf ? scheme.onTertiaryContainer : scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
