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

  static BoxShadow boxShadow({
    Color? color,
    double blurRadius = 20.0,
    Offset offset = Offset.zero,
  }) {
    return BoxShadow(
      color: color ?? Colors.black.withValues(alpha: 0.2),
      blurRadius: blurRadius,
      offset: offset,
    );
  }

  static BoxDecoration cardDecoration({
    Color? color,
    double borderRadius = 24.0,
    Color? borderColor,
    List<BoxShadow>? boxShadow,
  }) {
    return BoxDecoration(
      color: color ?? AppColors.cardDark,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: borderColor ?? Colors.white.withValues(alpha: 0.05),
      ),
      boxShadow:
          boxShadow ?? [VpWidgets.boxShadow(offset: const Offset(0, 10))],
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.punkPurple.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.punkPurple.withValues(alpha: 0.6)),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.deepViolet,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: VpWidgets.googleFont(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: VpWidgets.googleFont(
                      color: Colors.white54,
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
    );
  }
}

class VPDivider extends StatelessWidget {
  const VPDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      color: AppColors.deepViolet.withValues(alpha: 0.5),
      indent: 16,
      endIndent: 16,
    );
  }
}

class VPAvatar extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final Color borderColor;
  final bool isUploading;

  const VPAvatar({
    super.key,
    this.imageUrl,
    this.size = 80,
    this.borderColor = AppColors.neonPink,
    this.isUploading = false,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = ApiService.resolveProtectedMediaUrl(imageUrl);

    return Stack(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: 2),
            boxShadow: [
              BoxShadow(
                color: borderColor.withValues(alpha: 0.3),
                blurRadius: 20,
              ),
            ],
          ),
          child: resolved == null
              ? SizedBox(
                  width: size,
                  height: size,
                  child:
                      Icon(Icons.person, size: size / 2, color: Colors.white54),
                )
              : ClipOval(
                  child: ProtectedNetworkImage(
                    url: imageUrl!,
                    cacheManager: MediaCacheManager(),
                    fit: BoxFit.cover,
                    width: size,
                    height: size,
                    placeholder: (context, url) => SizedBox(
                      width: size,
                      height: size,
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (context, url, error) => SizedBox(
                      width: size,
                      height: size,
                      child: const Icon(Icons.error, color: Colors.white54),
                    ),
                  ),
                ),
        ),
        if (isUploading)
          Positioned.fill(
            child: Center(
              child: CircularProgressIndicator(color: borderColor),
            ),
          ),
      ],
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
    if (isLoading) {
      return Center(
          child: CircularProgressIndicator(
              color: backgroundColor ?? AppColors.neonBlue));
    }

    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor ?? AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 8,
        shadowColor:
            (backgroundColor ?? AppColors.primary).withValues(alpha: 0.5),
        minimumSize: width != null ? Size(width!, 50) : null,
      ),
      child: Text(
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
  final String label;
  final String hint;
  final IconData? icon;
  final bool isPassword;
  final bool obscureText;
  final VoidCallback? onTogglePassword;
  final TextInputType inputType;

  const VPTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.icon,
    this.isPassword = false,
    this.obscureText = false,
    this.onTogglePassword,
    this.inputType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: VpWidgets.googleFont(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.cardDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: inputType,
            style: VpWidgets.googleFont(color: Colors.white),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: VpWidgets.googleFont(color: Colors.white24),
              prefixIcon:
                  icon != null ? Icon(icon, color: Colors.white38) : null,
              suffixIcon: isPassword
                  ? IconButton(
                      icon: Icon(
                        obscureText
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: Colors.white38,
                      ),
                      onPressed: onTogglePassword,
                    )
                  : null,
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          leading ??
              (showBackButton
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new,
                          color: Colors.white70, size: 20),
                      onPressed: onBack ?? () => Navigator.pop(context),
                    )
                  : const SizedBox(width: 40)),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: VpWidgets.googleFont(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          if (trailing != null) ...trailing! else const SizedBox(width: 40),
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
    this.borderRadius = 24.0,
    this.borderColor,
    this.shadowColor,
    this.blurRadius = 20.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding ?? const EdgeInsets.all(24),
      decoration: VpWidgets.cardDecoration(
        borderRadius: borderRadius,
        borderColor: borderColor,
        boxShadow: [
          VpWidgets.boxShadow(
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

class VPUserAvatar extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final Widget? indicator;
  final double size;

  static Widget get onlineIndicator => Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: AppColors.neonGreen,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.backgroundDark, width: 2),
          boxShadow: [
            BoxShadow(
                color: AppColors.neonGreen.withValues(alpha: 0.5),
                blurRadius: 8),
          ],
        ),
      );

  const VPUserAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.indicator,
    this.size = 80,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          children: [
            VPAvatar(
              imageUrl: imageUrl,
              size: size,
              borderColor: Colors.white.withValues(alpha: 0.1),
            ),
            if (indicator != null)
              Positioned(
                right: 0,
                bottom: 0,
                child: indicator!,
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          name,
          style: VpWidgets.googleFont(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
      ],
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
    return Scaffold(
      backgroundColor: backgroundColor ?? AppColors.backgroundDark,
      appBar: showAppBar
          ? AppBar(
              backgroundColor: (backgroundColor ?? AppColors.backgroundDark)
                  .withValues(alpha: 0.8),
              elevation: 0,
              centerTitle: centerTitle,
              title: title != null
                  ? Text(
                      title!,
                      style: VpWidgets.googleFont(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
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
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
  });

  @override
  Widget build(BuildContext context) {
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
              color: Colors.white54,
              letterSpacing: 1.2,
            ),
          ),
          if (actionLabel != null)
            GestureDetector(
              onTap: onActionTap,
              child: Text(
                actionLabel!,
                style: VpWidgets.googleFont(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
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
      backgroundColor: AppColors.cardDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        title,
        style: VpWidgets.googleFont(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),
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
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
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
                      colors: [AppColors.primary, AppColors.neonPurple],
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
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 50,
                        right: -30,
                        child: Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.1),
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
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: const Icon(Icons.favorite,
                                    color: Colors.white, size: 48),
                              ),
                              const SizedBox(height: 16),
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
                          decoration: const BoxDecoration(
                            color: AppColors.backgroundDark,
                            borderRadius:
                                BorderRadius.vertical(top: Radius.circular(32)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Form Section
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 16),
                        Text(
                          title,
                          style: VpWidgets.googleFont(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          subtitle,
                          style: VpWidgets.googleFont(
                            fontSize: 14,
                            color: Colors.white54,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        ...children,
                        const Spacer(),
                        if (footer != null) footer!,
                        const SizedBox(height: 32),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          text,
          style: VpWidgets.googleFont(color: Colors.white54, fontSize: 14),
        ),
        TextButton(
          onPressed: onTap,
          child: Text(
            actionText,
            style: VpWidgets.googleFont(
              color: AppColors.neonPurple,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
