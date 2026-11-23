import 'package:material_ui/material_ui.dart';

import '../../models/rider.dart';

/// Bike disc + name label. The leader is distinct by shape, not color alone:
/// an outer ring and a star badge. Offline riders are dimmed.
class RiderMarkerWidget extends StatelessWidget {
  const RiderMarkerWidget({super.key, required this.rider});

  final Rider rider;

  static const double width = 132;
  static const double height = 82;
  static const double _disc = 40;

  /// Marker alignment that puts the disc centre (not the label) on the point.
  static const Alignment anchor = Alignment(0, 0.34);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final leader = rider.isLeader;
    final disc = Container(
      width: _disc,
      height: _disc,
      decoration: BoxDecoration(
        color: leader ? scheme.primary : scheme.secondaryContainer,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.surface, width: 2),
        boxShadow: const [BoxShadow(blurRadius: 4, color: Color(0x55000000))],
      ),
      child: Icon(
        Icons.two_wheeler,
        size: 22,
        color: leader ? scheme.onPrimary : scheme.onSecondaryContainer,
      ),
    );
    return Semantics(
      label: '${rider.name}${leader ? ', leader' : ''}',
      child: Opacity(
        opacity: rider.status == RiderStatus.offline ? 0.5 : 1,
        child: SizedBox(
          width: width,
          height: height,
          child: Column(
            children: [
              SizedBox(
                width: 54,
                height: 54,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (leader)
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: scheme.primary, width: 3),
                        ),
                      ),
                    disc,
                    if (leader)
                      Positioned(
                        right: 2,
                        top: 2,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration:
                              BoxDecoration(color: scheme.tertiary, shape: BoxShape.circle),
                          child: Icon(Icons.star, size: 13, color: scheme.onTertiary),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Container(
                constraints: const BoxConstraints(maxWidth: width),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  rider.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurface,
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
