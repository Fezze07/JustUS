import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:justus/all_imports.dart';

class LocalizationScreen extends StatelessWidget {
  const LocalizationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;

    return VPScaffold(
      backgroundColor: AppColors.deepViolet,
      showAppBar: false,
      body: SafeArea(
        child: Consumer<LanguageProvider>(
          builder: (context, languageProvider, _) {
            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              children: [
                VPHeader(
                  title: loc.settingsTitle.toUpperCase(),
                  onBack: () => Navigator.pop(context),
                ),
                const SizedBox(height: 12),
                Text(
                  loc.settingsSubtitle,
                  textAlign: TextAlign.center,
                  style: VpWidgets.googleFont(
                    color: Colors.white54,
                    fontSize: 13,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 32),
                VPSectionHeader(title: loc.languageSectionTitle),
                VPSettingGroup(
                  children: [
                    for (var i = 0; i < languageProvider.supportedLanguages.length; i++) ...[
                      _LanguageTile(
                        language: languageProvider.supportedLanguages[i],
                        selectedCode: languageProvider.locale.languageCode,
                      ),
                      if (i < languageProvider.supportedLanguages.length - 1) const VPDivider(),
                    ],
                  ],
                ),
                const SizedBox(height: 24),
                VPSectionHeader(title: loc.aiTranslationSectionTitle),
                VPSettingGroup(
                  children: [
                    VPSettingTile(
                      icon: Icons.auto_awesome,
                      title: loc.aiTranslationReadyTitle,
                      subtitle: loc.aiTranslationReadySubtitle,
                      trailing: const Icon(Icons.psychology, color: Colors.white54),
                      color: AppColors.neonPurple,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  final AppLanguage language;
  final String selectedCode;

  const _LanguageTile({
    required this.language,
    required this.selectedCode,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selectedCode == language.code;

    return VPSettingTile(
      icon: Icons.language,
      title: '${language.flagEmoji} ${language.nativeName}',
      subtitle: '${context.loc.currentLanguageLabel}: ${language.englishName}',
      trailing: Icon(
        isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
        color: isSelected ? AppColors.neonGreen : Colors.white38,
      ),
      color: isSelected ? AppColors.neonGreen : AppColors.neonBlue,
      onTap: isSelected
          ? null
          : () async {
              await context.read<LanguageProvider>().setLanguageCode(language.code);
              if (!context.mounted) return;

              UIUtils.showSnackBar(
                context,
                context.loc.languageSavedMessage,
                backgroundColor: AppColors.neonPurple,
              );
            },
    );
  }
}
