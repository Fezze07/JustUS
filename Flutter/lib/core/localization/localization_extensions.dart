import 'package:flutter/widgets.dart';

import 'package:justus/all_imports.dart';

extension AppLocalizationBuildContext on BuildContext {
  AppLocalizations get loc => AppLocalizations.of(this);
}
