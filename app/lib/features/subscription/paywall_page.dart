import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../app_scope.dart';
import '../../billing/subscription.dart';

class _Feature {
  const _Feature(this.label, this.minTier);

  final String label;
  final Tier minTier;
}

const _features = [
  _Feature('متابعة التلاوة كلمة بكلمة', Tier.free),
  _Feature('البحث عن الآية بالصوت', Tier.free),
  _Feature('الاستماع لكبار القرّاء', Tier.free),
  _Feature('وضع الحفظ وإحصائيات التقدّم', Tier.free),
  _Feature('ملاحظات القراءة في الهامش: الكلمة الخاطئة والفائتة', Tier.pro),
  _Feature('مراجعة ملاحظاتك السابقة', Tier.pro),
  _Feature('تلوين أحكام التجويد في المصحف', Tier.plus),
  _Feature('ملاحظات التجويد: طول المدود والحركات', Tier.plus),
];

class PaywallPage extends StatelessWidget {
  const PaywallPage({super.key});

  @override
  Widget build(BuildContext context) {
    final sub = AppScope.of(context).subscription;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('الاشتراكات')),
      body: ListenableBuilder(
        listenable: sub,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('اختر ما يناسب رحلتك مع القرآن', style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text('بلا إعلانات في كل الباقات', textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.outline)),
            const SizedBox(height: 16),
            for (final tier in [Tier.plus, Tier.pro]) _TierCard(tier: tier, current: sub.tier),
            _FreeCard(current: sub.tier),
            if (sub.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(sub.error!, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error)),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: sub.busy ? null : sub.restore,
              child: const Text('استعادة المشتريات'),
            ),
            Text(
              'يتجدد الاشتراك تلقائيًا بنفس السعر ما لم يُلغَ قبل ٢٤ ساعة على الأقل من نهاية الفترة الحالية. '
              'يُخصم المبلغ من حسابك في المتجر، ويمكنك إدارة الاشتراك أو إلغاؤه من إعدادات حسابك.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
            ),
            if (kDebugMode) ...[
              const Divider(height: 32),
              Text('للتجربة فقط (نسخة التطوير)', textAlign: TextAlign.center, style: theme.textTheme.labelMedium),
              SegmentedButton<Tier>(
                segments: [for (final t in Tier.values) ButtonSegment(value: t, label: Text(t.label))],
                selected: {sub.tier},
                onSelectionChanged: (v) => sub.debugSetTier(v.first),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard({required this.tier, required this.current});

  final Tier tier;
  final Tier current;

  @override
  Widget build(BuildContext context) {
    final sub = AppScope.of(context).subscription;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isCurrent = tier == current;
    final highlight = tier == Tier.plus;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: highlight ? scheme.primaryContainer.withValues(alpha: 0.5) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isCurrent ? scheme.primary : Colors.transparent, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Text(tier.label, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              if (highlight) Chip(label: const Text('يشمل التجويد'), visualDensity: VisualDensity.compact),
              const Spacer(),
              if (isCurrent) Text('باقتك الحالية', style: TextStyle(color: scheme.primary)),
            ]),
            const SizedBox(height: 8),
            for (final f in _features)
              if (f.minTier.index <= tier.index)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Icon(Icons.check, size: 18, color: f.minTier == tier ? scheme.primary : scheme.outline),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(f.label,
                          style: TextStyle(fontWeight: f.minTier == tier ? FontWeight.w700 : FontWeight.normal)),
                    ),
                  ]),
                ),
            if (!isCurrent && tier.index > current.index) ...[
              const SizedBox(height: 12),
              Row(children: [
                for (final plan in plans.where((p) => p.tier == tier)) ...[
                  Expanded(child: _PlanButton(plan: plan, product: sub.products[plan.productId])),
                  if (!plan.yearly) const SizedBox(width: 8),
                ],
              ]),
              if (!sub.storeAvailable)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(sub.platformHasStore ? 'المتجر غير متاح حاليًا.' : 'الاشتراك متاح من تطبيق الجوال.',
                      textAlign: TextAlign.center, style: TextStyle(color: scheme.outline, fontSize: 13)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlanButton extends StatelessWidget {
  const _PlanButton({required this.plan, required this.product});

  final Plan plan;
  final ProductDetails? product;

  @override
  Widget build(BuildContext context) {
    final sub = AppScope.of(context).subscription;
    final period = plan.yearly ? 'سنويًا' : 'شهريًا';
    final price = product?.price;
    final label = Text(price == null ? period : '$price $period', textAlign: TextAlign.center);
    final onPressed = sub.busy || product == null ? null : () => sub.buy(plan);
    return plan.yearly
        ? FilledButton(onPressed: onPressed, child: label)
        : OutlinedButton(onPressed: onPressed, child: label);
  }
}

class _FreeCard extends StatelessWidget {
  const _FreeCard({required this.current});

  final Tier current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Text(Tier.free.label, style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              if (current == Tier.free) Text('باقتك الحالية', style: TextStyle(color: scheme.primary)),
            ]),
            const SizedBox(height: 4),
            Text(
              _features.where((f) => f.minTier == Tier.free).map((f) => f.label).join(' · '),
              style: TextStyle(color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
