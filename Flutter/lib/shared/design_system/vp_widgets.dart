import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:justus/all_imports.dart';

abstract class VpWidgets {
  static TextStyle googleFont({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    FontStyle? fontStyle,
    double? height,
    TextDecoration? decoration,
    Color? decorationColor,
  }) {
    return GoogleFonts.plusJakartaSans(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      fontStyle: fontStyle,
      height: height,
      decoration: decoration,
      decorationColor: decorationColor,
    );
  }

  static BoxShadow boxShadow(
    BuildContext context, {
    Color? color,
    double blurRadius = 20.0,
    Offset offset = Offset.zero,
  }) {
    return BoxShadow(
      color: color ?? context.palette.shadow,
      blurRadius: blurRadius,
      offset: offset,
    );
  }

  static BoxDecoration cardDecoration(
    BuildContext context, {
    Color? color,
    double borderRadius = AppRadius.lg,
    Color? borderColor,
    List<BoxShadow>? boxShadow,
  }) {
    return BoxDecoration(
      color: color ?? context.palette.surface,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: borderColor ?? context.palette.border,
      ),
      boxShadow:
          boxShadow ?? [VpWidgets.boxShadow(context, offset: const Offset(0, 10))],
    );
  }
}

class VPSettingGroup extends StatelessWidget {
  final List<Widget> children;

  const VPSettingGroup({
    super.key,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceGroup,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: palette.border),
      ),
      child: Column(children: children),
    );
  }
}

class VPSettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final Color color;
  final VoidCallback? onTap;

  const VPSettingTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      container: true,
      button: onTap != null,
      child: MergeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Container(
                  width: AppDims.iconBox,
                  height: AppDims.iconBox,
                  decoration: BoxDecoration(
                    color: palette.surfaceSunken,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: color.withValues(alpha: 0.2)),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: VpWidgets.googleFont(
                          fontWeight: FontWeight.bold,
                          color: palette.contentPrimary,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: VpWidgets.googleFont(
                          color: palette.contentTertiary,
                          fontSize: 11,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class VPDivider extends StatelessWidget {
  const VPDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: AppDims.hairline,
      color: context.palette.divider,
      indent: AppSpacing.md,
      endIndent: AppSpacing.md,
    );
  }
}

class VPButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Color? backgroundColor;
  final double? width;

  const VPButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.backgroundColor,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final background = backgroundColor ?? palette.primary;

    return FilledButton(
      onPressed: isLoading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: background,
        disabledBackgroundColor: AppButtonStyle.disabledBackground(background),
        minimumSize: Size(width ?? 0, AppDims.buttonMinHeight),
      ),
      child: isLoading
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: AppSpacing.lg,
                  height: AppSpacing.lg,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.onPrimary,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                Text(
                  label,
                  style: VpWidgets.googleFont(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            )
          : Text(
              label,
              style: VpWidgets.googleFont(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
    );
  }
}

class VPTextField extends StatelessWidget {
  final TextEditingController controller;
  final String? label;
  final String hint;
  final IconData? icon;
  final bool isPassword;
  final bool obscureText;
  final VoidCallback? onTogglePassword;
  final TextInputType inputType;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const VPTextField({
    super.key,
    required this.controller,
    this.label,
    required this.hint,
    this.icon,
    this.isPassword = false,
    this.obscureText = false,
    this.onTogglePassword,
    this.inputType = TextInputType.text,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Padding(
            padding: const EdgeInsets.only(
              left: AppRadius.xs,
              bottom: AppSpacing.sm,
            ),
            child: Text(
              label!,
              style: VpWidgets.googleFont(
                color: palette.contentSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: palette.border),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: inputType,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            style: VpWidgets.googleFont(color: palette.contentPrimary),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: VpWidgets.googleFont(color: palette.contentHint),
              errorText: errorText,
              prefixIcon: icon != null
                  ? Icon(icon, color: palette.contentDisabled)
                  : null,
              suffixIcon: isPassword
                  ? IconButton(
                      tooltip: obscureText
                          ? context.loc.common_showPassword
                          : context.loc.common_hidePassword,
                      icon: Icon(
                        obscureText
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: palette.contentDisabled,
                      ),
                      onPressed: onTogglePassword,
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.md,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class VPHeader extends StatelessWidget {
  final String title;
  final bool showBackButton;
  final VoidCallback? onBack;
  final List<Widget>? trailing;
  final Widget? leading;

  const VPHeader({
    super.key,
    required this.title,
    this.showBackButton = true,
    this.onBack,
    this.trailing,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          leading ??
              (showBackButton
                  ? IconButton(
                      tooltip: context.loc.common_back,
                      icon: Icon(
                        Icons.arrow_back_ios_new,
                        color: palette.contentSecondary,
                        size: 20,
                      ),
                      onPressed: onBack ?? () => Navigator.pop(context),
                    )
                  : const SizedBox(width: AppDims.circleButton)),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: VpWidgets.googleFont(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: palette.contentPrimary,
              ),
            ),
          ),
          if (trailing != null)
            ...trailing!
          else
            const SizedBox(width: AppDims.circleButton),
        ],
      ),
    );
  }
}

class VPCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Color? borderColor;
  final Color? shadowColor;
  final double blurRadius;

  const VPCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = AppRadius.lg,
    this.borderColor,
    this.shadowColor,
    this.blurRadius = 20.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
      decoration: VpWidgets.cardDecoration(
        context,
        borderRadius: borderRadius,
        borderColor: borderColor,
        boxShadow: [
          VpWidgets.boxShadow(
            context,
            color: shadowColor,
            blurRadius: blurRadius,
            offset: shadowColor == null ? const Offset(0, 10) : Offset.zero,
          ),
        ],
      ),
      child: child,
    );
  }
}

class VPScaffold extends StatelessWidget {
  final String? title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? leading;
  final Widget? bottomNavigationBar;
  final bool showAppBar;
  final bool centerTitle;
  final Color? backgroundColor;
  final Widget? floatingActionButton;

  const VPScaffold({
    super.key,
    this.title,
    required this.body,
    this.actions,
    this.leading,
    this.bottomNavigationBar,
    this.showAppBar = true,
    this.centerTitle = true,
    this.backgroundColor,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final background = backgroundColor ?? palette.canvas;
    return Scaffold(
      backgroundColor: background,
      appBar: showAppBar
          ? AppBar(
              backgroundColor: background.withValues(alpha: 0.8),
              elevation: 0,
              centerTitle: centerTitle,
              title: title != null
                  ? Text(
                      title!,
                      style: VpWidgets.googleFont(
                        fontWeight: FontWeight.bold,
                        color: palette.contentPrimary,
                      ),
                    )
                  : null,
              leading: leading,
              actions: actions,
            )
          : null,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      body: body,
    );
  }
}

class VPSectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onActionTap;
  final EdgeInsets padding;

  const VPSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onActionTap,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.md,
    ),
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: padding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: VpWidgets.googleFont(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: palette.contentTertiary,
              letterSpacing: 1.2,
            ),
          ),
          if (actionLabel != null)
            Semantics(
              button: true,
              label: actionLabel,
              child: GestureDetector(
                onTap: onActionTap,
                behavior: HitTestBehavior.opaque,
                child: Text(
                  actionLabel!,
                  style: VpWidgets.googleFont(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: palette.primaryVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class VPSegmentedControl<T> extends StatelessWidget {
  final List<VPSegmentedControlOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  const VPSegmentedControl({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((option) {
          final isSelected = option.value == value;
          return Semantics(
            button: true,
            selected: isSelected,
            label: option.label,
            child: InkWell(
              onTap: isSelected ? null : () => onChanged(option.value),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? palette.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      option.icon,
                      size: 14,
                      color: isSelected
                          ? palette.onPrimary
                          : palette.contentTertiary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      option.label,
                      style: VpWidgets.googleFont(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? palette.onPrimary
                            : palette.contentSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class VPSegmentedControlOption<T> {
  final T value;
  final String label;
  final IconData icon;

  const VPSegmentedControlOption({
    required this.value,
    required this.label,
    required this.icon,
  });
}

class VPDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final List<Widget>? actions;

  const VPDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: content,
      actions: actions,
    );
  }
}

class VPAuthLayout extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget? footer;

  const VPAuthLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.canvas,
      body: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height,
          ),
          child: IntrinsicHeight(
            child: Column(
              children: [
                // Header Section with Gradient
                Container(
                  height: MediaQuery.of(context).size.height * 0.35,
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppPalette.brandGradientStart, AppPalette.brandNeonPurple],
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Decorative circles
                      Positioned(
                        top: -50,
                        left: -50,
                        child: Container(
                          width: 200,
                          height: 200,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppPalette.brandHeroOverlay,
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 50,
                        right: -30,
                        child: Container(
                          width: 150,
                          height: 150,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppPalette.brandHeroOverlay,
                          ),
                        ),
                      ),

                      // Content
                      SafeArea(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                decoration: BoxDecoration(
                                  color: AppPalette.brandHeroGlass,
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.lg),
                                ),
                                child: const Icon(Icons.favorite,
                                    color: Colors.white, size: 48),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                context.loc.appTitle,
                                style: VpWidgets.googleFont(
                                  fontSize: 40,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 1,
                                ),
                              ),
                              Text(
                                context.loc.appTagline,
                                style: VpWidgets.googleFont(
                                  fontSize: 14,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Curve overlap
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 32,
                          decoration: BoxDecoration(
                            color: palette.canvas,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(AppRadius.sheet)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Form Section
                Expanded(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          title,
                          style: VpWidgets.googleFont(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: palette.contentPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          subtitle,
                          style: VpWidgets.googleFont(
                            fontSize: 14,
                            color: palette.contentTertiary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        ...children,
                        const Spacer(),
                        if (footer != null) footer!,
                        const SizedBox(height: AppSpacing.xl),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class VPAuthLink extends StatelessWidget {
  final String text;
  final String actionText;
  final VoidCallback onTap;

  const VPAuthLink({
    super.key,
    required this.text,
    required this.actionText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          text,
          style: VpWidgets.googleFont(
              color: palette.contentTertiary, fontSize: 14),
        ),
        TextButton(
          onPressed: onTap,
          child: Text(
            actionText,
            style: VpWidgets.googleFont(
              color: palette.accentPurple,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
