import 'package:flutter/material.dart';

import '../billing/pro_purchase_controller.dart';

Future<void> showProUpgradeDialog(
  BuildContext context,
  ProPurchaseController purchases,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => _ProUpgradeDialog(purchases: purchases),
  );
}

class _ProUpgradeDialog extends StatefulWidget {
  const _ProUpgradeDialog({required this.purchases});

  final ProPurchaseController purchases;

  @override
  State<_ProUpgradeDialog> createState() => _ProUpgradeDialogState();
}

class _ProUpgradeDialogState extends State<_ProUpgradeDialog> {
  final _reviewCode = TextEditingController();

  @override
  void dispose() {
    _reviewCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final purchases = widget.purchases;
    return AnimatedBuilder(
      animation: purchases,
      builder: (context, _) => AlertDialog(
        scrollable: true,
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
              if (purchases.isAndroid && !purchases.isPro) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _reviewCode,
                  enabled: !purchases.isBusy,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Review access code',
                    helperText: 'For Google Play reviewers.',
                  ),
                  onSubmitted: purchases.isBusy
                      ? null
                      : purchases.redeemReviewCode,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: purchases.isBusy
                        ? null
                        : () => purchases.redeemReviewCode(_reviewCode.text),
                    child: const Text('Activate review access'),
                  ),
                ),
              ],
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
    );
  }
}
