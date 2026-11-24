import 'package:flutter/material.dart';

import '../billing/pro_purchase_controller.dart';

Future<void> showProUpgradeDialog(
  BuildContext context,
  ProPurchaseController purchases,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => AnimatedBuilder(
      animation: purchases,
      builder: (context, _) => AlertDialog(
        title: const Text('Claviera Pro'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Unlock advanced notation and take your music with you.',
              ),
              const SizedBox(height: 12),
              for (final feature in const [
                'Articulations, ornaments, and arpeggios',
                'Dynamics and hairpins',
                'PDF, MIDI, and MusicXML exports',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(feature)),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              const Text('One-time purchase. No subscription.'),
              if (!purchases.isAndroid) ...[
                const SizedBox(height: 12),
                const Text('Pro purchases are currently available on Android.'),
              ],
              if (purchases.message != null) ...[
                const SizedBox(height: 12),
                Text(
                  purchases.message!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (purchases.isAndroid)
            TextButton(
              onPressed: purchases.isAvailable && !purchases.isBusy
                  ? purchases.restorePurchases
                  : null,
              child: const Text('Restore purchases'),
            ),
          if (purchases.isPro)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            )
          else if (purchases.isAndroid)
            FilledButton.icon(
              onPressed:
                  purchases.isAvailable &&
                      purchases.localizedPrice != null &&
                      !purchases.isBusy
                  ? purchases.buyPro
                  : null,
              icon: purchases.isBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.lock_open),
              label: Text(
                purchases.localizedPrice == null
                    ? purchases.isBusy
                          ? 'Loading price…'
                          : 'Price unavailable'
                    : 'Unlock Pro · ${purchases.localizedPrice}',
              ),
            ),
          if (!purchases.isPro)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Not now'),
            ),
        ],
      ),
    ),
  );
}
