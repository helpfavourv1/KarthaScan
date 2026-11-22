import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/providers/subscription_provider.dart';
import '../core/services/ad_consent_service.dart';
import '../core/services/reward_service.dart';
import '../core/services/rewarded_ad_service.dart';
import '../l10n/app_localizations.dart';

String _clock(BuildContext c, DateTime t) =>
    MaterialLocalizations.of(c).formatTimeOfDay(TimeOfDay.fromDateTime(t), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(c));

String _left(Duration d) {
  final int h = d.inHours;
  final int m = d.inMinutes % 60;
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}

/// Every entry point goes through here: a clear confirmation first, then the ad.
Future<void> startRewardOffer(BuildContext context) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final bool? yes = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(l10n.rewardCardTitle, style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(l10n.rewardSheetBody),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.rewardWatch)),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.rewardNoThanks)),
          ],
        ),
      ),
    ),
  );
  if (yes != true) return;
  if (!RewardedAdService.instance.loaded.value) {
    unawaited(RewardedAdService.instance.preload());
    messenger.showSnackBar(SnackBar(content: Text(l10n.rewardNotReady)));
    return;
  }
  final bool ok = await RewardedAdService.instance.show();
  if (ok && context.mounted) {
    final DateTime end = RewardService.instance.endsAt ?? DateTime.now();
    messenger.showSnackBar(SnackBar(content: Text(l10n.rewardActiveUntil(_clock(context, end)))));
  }
}

bool _adsAllowed() {
  final ConsentOutcome o = AdConsentService.instance.outcome.value;
  return AdConsentService.instance.adsReady.value && o != ConsentOutcome.blocked && o != ConsentOutcome.unknown;
}

Listenable _all(SubscriptionProvider sub) => Listenable.merge(<Listenable>[
      RewardService.instance.changes,
      RewardService.instance.active,
      RewardedAdService.instance.loaded,
      AdConsentService.instance.adsReady,
      sub.adsRemoved,
    ]);

/// Home-list card: only when the rules in RewardService say so.
class RewardHomeCard extends StatefulWidget {
  const RewardHomeCard({super.key});
  @override
  State<RewardHomeCard> createState() => _RewardHomeCardState();
}

class _RewardHomeCardState extends State<RewardHomeCard> {
  @override
  void initState() {
    super.initState();
    unawaited(RewardedAdService.instance.preload());
  }

  @override
  Widget build(BuildContext context) {
    final SubscriptionProvider sub = Provider.of<SubscriptionProvider>(context, listen: false);
    return ListenableBuilder(
      listenable: _all(sub),
      builder: (BuildContext context, Widget? _) {
        final bool show = RewardService.instance.shouldShowCard(
          adsRemoved: sub.adsRemoved.value,
          adsAllowed: _adsAllowed(),
          adLoaded: RewardedAdService.instance.loaded.value,
        );
        if (!show) return const SizedBox.shrink();
        final AppLocalizations l10n = AppLocalizations.of(context);
        final ColorScheme cs = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
          child: Material(
            color: cs.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => startRewardOffer(context),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 4, 4),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.play_circle_outline, color: cs.onSecondaryContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(l10n.rewardCardTitle, style: TextStyle(color: cs.onSecondaryContainer, fontWeight: FontWeight.w600)),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: cs.onSecondaryContainer),
                      onPressed: () => RewardService.instance.dismissCard(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Settings / paywall row. Always shown to non-buyers.
class RewardTile extends StatefulWidget {
  const RewardTile({super.key, this.asButton = false});
  final bool asButton;
  @override
  State<RewardTile> createState() => _RewardTileState();
}

class _RewardTileState extends State<RewardTile> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    unawaited(RewardedAdService.instance.preload());
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && RewardService.instance.isActive()) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SubscriptionProvider sub = Provider.of<SubscriptionProvider>(context, listen: false);
    return ListenableBuilder(
      listenable: _all(sub),
      builder: (BuildContext context, Widget? _) {
        if (sub.adsRemoved.value) return const SizedBox.shrink();
        final AppLocalizations l10n = AppLocalizations.of(context);
        final RewardService r = RewardService.instance;
        final bool active = r.isActive();
        final bool capped = r.capReached();
        final String status = l10n.rewardStatus(_left(r.timeLeft()), r.claimsUsed());
        String title = l10n.rewardWatchButton;
        String? sub2;
        if (active) {
          title = l10n.rewardActiveUntil(_clock(context, r.endsAt!));
          sub2 = status;
        } else if (capped) {
          title = l10n.rewardBackTomorrow;
        }
        final bool enabled = !active && !capped;
        if (widget.asButton) {
          return Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            OutlinedButton.icon(
              onPressed: enabled ? () => startRewardOffer(context) : null,
              icon: const Icon(Icons.play_circle_outline),
              label: Text(title, textAlign: TextAlign.center),
            ),
            if (sub2 != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(sub2, style: Theme.of(context).textTheme.bodySmall)),
          ]);
        }
        return ListTile(
          leading: const Icon(Icons.play_circle_outline),
          title: Text(title),
          subtitle: sub2 == null ? null : Text(sub2),
          enabled: enabled,
          onTap: enabled ? () => startRewardOffer(context) : null,
        );
      },
    );
  }
}

/// Shows the short "Tired of ads?" message after an interstitial closes,
/// at most once per day and only when the card rules allow it.
class RewardPromptListener extends StatefulWidget {
  const RewardPromptListener({super.key, required this.child});
  final Widget child;
  @override
  State<RewardPromptListener> createState() => _RewardPromptListenerState();
}

class _RewardPromptListenerState extends State<RewardPromptListener> {
  @override
  void initState() {
    super.initState();
    RewardService.instance.interstitialClosedTick.addListener(_onClosed);
  }

  @override
  void dispose() {
    RewardService.instance.interstitialClosedTick.removeListener(_onClosed);
    super.dispose();
  }

  void _onClosed() {
    // Wait out the short pause after a full-screen ad, so nothing overlaps it.
    Future<void>.delayed(const Duration(seconds: 4), () async {
      if (!mounted) return;
      final SubscriptionProvider sub = Provider.of<SubscriptionProvider>(context, listen: false);
      final RewardService r = RewardService.instance;
      if (!r.shouldShowPrompt(
        adsRemoved: sub.adsRemoved.value,
        adsAllowed: _adsAllowed(),
        adLoaded: RewardedAdService.instance.loaded.value,
      )) {
        return;
      }
      await r.markPromptShown();
      if (!mounted) return;
      final AppLocalizations l10n = AppLocalizations.of(context);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(l10n.rewardPrompt),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(label: l10n.rewardWatch, onPressed: () => startRewardOffer(context)),
      ));
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
