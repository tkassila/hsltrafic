import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/localization.dart';
import '../models/transit_region.dart';
import '../state/app_state.dart';
import '../theme/hsl_colors.dart';

/// Avaa aluevalintalevyn (Bottom Sheet), josta käyttäjä voi valita haluamansa liikennealueen
/// tai kytkeä automaattisen sijaintipohjaisen tunnistuksen päälle.
Future<void> showTransitRegionSheet(BuildContext context) async {
  final settings = context.read<SettingsController>();
  final loc = settings.s.location;
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return Consumer<SettingsController>(
        builder: (context, st, _) {
          return Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, -4)),
              ],
            ),
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 14,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: theme.dividerColor.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                Row(
                  children: [
                    const Icon(Icons.location_city_rounded, color: HslColors.primaryBlue, size: 24),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Valitse liikennealue & reititin',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                Text(
                  'Valitse kaupunki tai valtakunnallinen kaukoliikenne. Automaattinen asetus vaihtaa alueen GPS-sijaintisi mukaan.',
                  style: TextStyle(fontSize: 12, color: theme.hintColor),
                ),
                const SizedBox(height: 14),

                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.55,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: TransitRegion.values.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (c, idx) {
                      final reg = TransitRegion.values[idx];
                      final isSelected = st.region == reg;

                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          st.setRegion(reg);
                          Navigator.of(ctx).pop();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? HslColors.primaryBlue.withValues(alpha: 0.12)
                                : (isDark
                                    ? theme.colorScheme.surfaceContainerHigh
                                    : Colors.grey.shade100),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? HslColors.primaryBlue : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                reg == TransitRegion.auto
                                    ? Icons.my_location_rounded
                                    : (reg == TransitRegion.finland
                                        ? Icons.train_rounded
                                        : Icons.location_on_rounded),
                                color: isSelected ? HslColors.primaryBlue : theme.hintColor,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          reg.name,
                                          style: TextStyle(
                                            fontWeight:
                                                isSelected ? FontWeight.bold : FontWeight.w600,
                                            fontSize: 14,
                                            color: isSelected ? HslColors.primaryBlue : null,
                                          ),
                                        ),
                                        if (reg == TransitRegion.auto) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: HslColors.successGreen.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Text(
                                              'Suositus',
                                              style: TextStyle(
                                                color: HslColors.successGreen,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      reg == TransitRegion.auto
                                          ? '${reg.description} (${reg.effectiveDisplayName(loc.position)})'
                                          : reg.description,
                                      style: TextStyle(fontSize: 11, color: theme.hintColor),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                const Icon(Icons.check_circle_rounded,
                                    color: HslColors.primaryBlue, size: 20),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => showWalttiInfoDialog(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 16, color: HslColors.primaryBlue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${AppStrings.get('waltti_cities_title')} Katso kaupunkilista ➔',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: HslColors.primaryBlue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

/// Avaa dialogin, jossa kerrotaan käyttäjän kielellä mitä Waltti-kaupungit ovat ja mitkä kaupungit siihen kuuluvat.
void showWalttiInfoDialog(BuildContext context) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          const Icon(Icons.location_city_rounded, color: HslColors.primaryBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppStrings.get('waltti_cities_title'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.get('waltti_cities_desc'),
              style: TextStyle(fontSize: 13, color: theme.hintColor, height: 1.35),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? theme.colorScheme.surfaceContainerHigh : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
              ),
              child: Text(
                AppStrings.get('waltti_cities_list'),
                style: const TextStyle(fontSize: 13, height: 1.5, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: HslColors.primaryBlue,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Sulje'),
        ),
      ],
    ),
  );
}

/// Yläpalkkiin tai hakukorttiin sijoitettava kompakti painike/pilleri aktiivisen alueen näyttämiseen ja vaihtamiseen.
class TransitRegionSelectorPill extends StatelessWidget {
  final bool compact;
  const TransitRegionSelectorPill({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final loc = settings.s.location;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final displayName = settings.region.effectiveDisplayName(loc.position);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => showTransitRegionSheet(context),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: HslColors.primaryBlue.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              settings.region == TransitRegion.auto
                  ? Icons.my_location_rounded
                  : (settings.region == TransitRegion.finland
                      ? Icons.train_rounded
                      : Icons.location_on_rounded),
              size: compact ? 13 : 15,
              color: HslColors.primaryBlue,
            ),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: compact ? 110 : 150),
              child: Text(
                displayName,
                style: TextStyle(
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: compact ? 16 : 18,
              color: HslColors.primaryBlue,
            ),
          ],
        ),
      ),
    );
  }
}

