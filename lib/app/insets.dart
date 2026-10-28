import 'package:flutter/widgets.dart';

/// Room to leave free under content that reaches the bottom edge of the
/// screen: the keyboard while it is open, else the system navigation bar.
///
/// Android 15 and later draw apps edge to edge, under the navigation bar, and
/// a bottom sheet's `useSafeArea` only keeps the top and the sides clear, so
/// a button at the bottom of a sheet ended up under the system bar on the
/// tablet. [extra] is added on top so buttons do not sit right on the bar.
double bottomSafeSpace(BuildContext context, {double extra = 0}) =>
    MediaQuery.paddingOf(context).bottom +
    MediaQuery.viewInsetsOf(context).bottom +
    extra;

/// [bottomSafeSpace] as padding: [base] with the safe space added at the
/// bottom.
EdgeInsets withBottomSafeSpace(
  BuildContext context,
  EdgeInsets base, {
  double extra = 0,
}) =>
    base.copyWith(bottom: base.bottom + bottomSafeSpace(context, extra: extra));

/// Padding that keeps a popup menu off every system bar, plus [margin].
EdgeInsets menuSafePadding(BuildContext context, {double margin = 8}) =>
    MediaQuery.paddingOf(context) + EdgeInsets.all(margin);
