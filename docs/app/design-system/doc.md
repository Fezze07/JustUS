# JustUS Flutter Design System - VP Widget System & Shared UI

## Overview

The design system ("Violet Punk") lives in `Flutter/lib/shared/design_system/` and is exported through the barrel `design_system.dart` (13 lines), which notably re-exports `vp_widgets.dart` plus the 8 satellite components:

```
design_system.dart  ->  export vp_widgets.dart, error_dialog.dart, protected_network_image.dart,
                        vp_circle_button.dart, vp_filter_chip.dart, vp_loading_button.dart,
                        vp_loading_overlay.dart, vp_mini_avatar.dart
```

`vp_widgets.dart` (846 lines) is the **core file** and hosts 15 components plus the `VpWidgets` static helper class. The satellite files each host one component.

Design tokens are centralized in `core/theme/`:

- `app_colors.dart` - `AppColors` static palette (primary `#7F13EC`, neon purple/blue/green/pink, `backgroundDark` `#191022`, `deepViolet` `#120526`, `punkPurple` `#2D1652`, `cardDark` `#1A0B2E`, plus light-theme text/card/border constants).
- `app_theme.dart` - `AppTheme.dark` / `AppTheme.light` Material 3 themes (Plus Jakarta Sans text theme, seeded color scheme, appBar/card/input/filledButton/dialog theme data).
- `theme_provider.dart` - runtime mode holder; always starts `ThemeMode.dark`, reads/writes nothing (preference is never persisted).

**Two coexisting design languages.** The VP system (deep-violet glass/punk) is used by all feature screens EXCEPT `HomepageScreen`, which ships a second, private "Midnight Glass" design (`homepage_screen.dart` lines 13-23 `_C` tokens, `_GlassCard`, `_GlassIconButton`, `_AvatarColumn`, `_MissYouButton`, ...). The homepage uses **zero** `AppColors` references (0 mentions), **11** hardcoded `Color(0x...)` values and **38** uses of its private `_C` palette; it also forces the `Inter` font family while the rest of the app uses Plus Jakarta Sans. This is a wholesale design-system bypass (see Findings F-DS1).

---

## Shared UI infrastructure (outside `shared/design_system/` but part of the UI layer)

| File | Role |
|---|---|
| `core/error_handling/error_handler.dart` | Global overlay snackbar / error dialog / reauth dialog (the de facto global "toast" mechanism) |
| `shared/utils/ui/snackbar_utils.dart` | `UIUtils.showSnackBar` - second snackbar mechanism (ScaffoldMessenger) |
| `shared/utils/ui/dialog_utils.dart` | `DialogUtils.showError` (wraps `ErrorDialog`), `showPartnerInvite` |
| `shared/utils/ui/validators.dart` | `Validators.validateEmail/Password/Required` - localized form validation used by auth screens |
| `shared/utils/ui/media_picker_service.dart` | Camera/gallery bottom sheet (bespoke, uses `AppColors` + raw `ListTile`) |
| `shared/utils/auth/logout_utils.dart` | Logout confirm dialog (raw `AlertDialog`, not `VPDialog`) |
| `shared/widgets/tab_screen.dart` | `TabScreen`/`TabScreenMixin` - tab activation infrastructure |
| `features/home/widgets/home_bottom_nav.dart` | Floating 7-item bottom nav (bespoke shell component, not part of barrel) |

The presence of **two snackbar systems** (`ErrorHandler` overlay vs `UIUtils` ScaffoldMessenger) is a cross-cutting inconsistency (see Findings F-DS8).

---

## Design tokens - `AppColors` (`core/theme/app_colors.dart:9-41`)

| Constant | Value | Role |
|---|---|---|
| `primary` | `0xFF7F13EC` | primary brand / buttons |
| `accentAqua` | `0xFF00D4FF` | secondary accent |
| `backgroundDark` / `backgroundLight` | `0xFF191022` / `0xFFF7F6F8` | scaffold backgrounds |
| `deepViolet` | `0xFF120526` | darkest stage / avatar icon backdrop |
| `punkPurple` | `0xFF2D1652` | slightly-lighter-than-deepViolet surfaces |
| `cardDark` | `0xFF1A0B2E` | cards / text fields / dialogs |
| `neonPurple` / `neonBlue` / `neonGreen` / `neonPink` | `0xFFBC13FE` / `0xFF00F5FF` / `0xFF00FFD9` / `0xFFFF0080` | gradient + status accents |
| `gradientStart` / `gradientEnd` | `0xFF7F13EC` / `0xFFA65CF0` | mood gradient |
| `textLight` / `textDark`, `borderLight` / `borderDark` | - | light-theme support (largely unused) |

`AppTheme._build` (app_theme.dart:22-88) centralizes: Material 3, `ColorScheme.fromSeed(primary)`, Plus Jakarta Sans text theme, `scaffoldBackgroundColor`, `AppBarTheme`, `CardThemeData` (radius **12**, dark `cardDark`/`borderDark`), `InputDecorationTheme` (radius **12**), `FilledButtonThemeData` (radius **12**, padding 24/12), `DialogThemeData` (radius **24**, cardDark).

**Configuration mismatch**: the global `ThemeData` values (radii 12) do not match the VP components (radii 16-24). Any component not using `Theme.of(context)` interpolation (most) visually contradicts the theme. Also `FilledButtonThemeData` styles `FilledButton`s globally but `VPButton` is an `ElevatedButton` with its own inline style - so the app-wide button theme and the flagship `VPButton` disagree.

---

## Component-by-component analysis

Legend: AUTH = requires logged-in session; NET = performs network/image fetch; each entry lists Purpose / API / Visual / State / Loading / Error / A11y / Theme / Loc / Deps.

### VpWidgets (static helpers) - `vp_widgets.dart:5-56`

- **Purpose**: shared typography + decoration builders used by every VP component.
- **API**: `googleFont({fontSize,fontWeight,color,letterSpacing,fontStyle,height,decoration,decorationColor})`; `boxShadow({color,blurRadius,offset})`; `cardDecoration({color,borderRadius,borderColor,boxShadow})`.
- **Behavior**: `cardDecoration` defaults color `cardDark`, radius **24**, border white 5%, shadow offset(0,10) blur 20; `boxShadow` defaults black 20%.
- **Theme**: helper only; ignores `Theme.of(context)` (callers inject colors).
- **Deps**: `google_fonts`, `AppColors`.
- **Usage**: 69 references across the app.

### VPSettingGroup - `vp_widgets.dart:58-77`

- **Purpose**: rounded container grouping setting tiles.
- **API**: `VPSettingGroup({required List<Widget> children})`.
- **Visual**: `DecoratedBox` with `punkPurple` 40% fill, `punkPurple` 60% border, radius 24.
- **State/A11y**: stateless, no semantics.
- **Loc/Theme**: none (uses `AppColors` directly, dark-only).
- **Deps**: none.
- **Usage**: only `profile_screen.dart` (7 references incl. definition barrel) - profile settings groups.

### VPSettingTile - `vp_widgets.dart:79-146`

- **Purpose**: settings row (icon square + title + subtitle + trailing control).
- **API**: `{required IconData icon, required String title, required String subtitle, required Widget trailing, required Color color, VoidCallback? onTap}`.
- **Visual**: 48x48 icon container (deepViolet fill, `color`-based 20% border, radius 16); bold white 16px title, `white54` 11px letter-spaced subtitle; `InkWell` radius 24; padding 20.
- **State**: optional tap; no ripple customization beyond default.
- **A11y**: no `Semantics`; trailing widget carries the interactivity (e.g. `Switch`).
- **Theme/Loc**: dark-only hardcodes (`Colors.white`, `Colors.white54`); strings passed in pre-localized by the caller.
- **Usage**: profile screen settings only (11 refs incl. def).
- **Design smell**: `subtitle` is `required` even where there is no subtitle - callers pass fabricated strings (e.g. dark-mode row shows a subtitle for a switch).

### VPDivider - `vp_widgets.dart:148-160`

- **Purpose**: themed 1-px separator.
- **API**: `VPDivider()` (no params).
- **Visual**: Material `Divider`, height 1, `deepViolet` 50%, indent/endIndent 16.
- **Theme/Loc**: dark-only.
- **Usage**: profile (bug: divider inside `VPDivider`'s own children used between setting tiles) and elsewhere minimally.

### VPAvatar - `vp_widgets.dart:162-231`

- **Purpose**: couple-profile avatar (used for user & partner photos).
- **API**: `{String? imageUrl, double size=80, Color borderColor=neonPink, bool isUploading=false}`.
- **Behavior**: `imageUrl` is passed through `ApiService.resolveProtectedMediaUrl()` (line 178) to rewrite R2 object keys into `/api/v1/media/file?filename=...`. When resolved, renders `ProtectedNetworkImage` (cached, authenticated headers) inside `ClipOval`. When null → placeholder `Icons.person` in `white54`.
- **Visual**: circular `borderColor` 2px + glow shadow (30% alpha, blur 20); optional full-cover upload spinner `CircularProgressIndicator` with `borderColor`.
- **Loading**: `CircularProgressIndicator(strokeWidth:2)` placeholder + full-cover overlay when `isUploading`.
- **Error**: `Icons.error` in `white54`.
- **A11y**: none (no `Semantics`, no `excludeFromSemantics` for decorative circle).
- **Theme/Loc**: dark-only; border default `neonPink`.
- **Auth**: image fetch uses `ApiService.authHeaders` (needs a live Supabase session).
- **NET**: yes (cached network image).
- **Deps**: `ApiService`, `MediaCacheManager`, `ProtectedNetworkImage`.
- **Usage**: profile_screen.dart:183,192; partner_screen.dart:211; inside `VPUserAvatar`.

### VPUserAvatar - `vp_widgets.dart:448-510`

- **Purpose**: avatar + uppercase name label + optional status indicator (game player cards).
- **API**: `{required String name, String? imageUrl, Widget? indicator, double size=80}`. Static getter `onlineIndicator` (12-line green-dot ornament, lines 454-467).
- **Behavior**: delegates image rendering to `VPAvatar` with a subdued border (white 10%); overlays `indicator` bottom-right; caption 12px bold letter-spaced white.
- **A11y**: none.
- **Theme/Loc**: dark-only; `name` pre-localized by caller.
- **NET/Auth**: inherits from `VPAvatar` when an image is present.
- **Usage**: only `game_screen.dart:373,387` (question status columns).
- **Dead API**: `onlineIndicator` is never referenced anywhere outside its definition.

### VPButton - `vp_widgets.dart:233-280`

- **Purpose**: primary full-width action button (login / register / change-password / partner invite).
- **API**: `{required String label, VoidCallback? onPressed, bool isLoading=false, Color? backgroundColor, double? width}`.
- **Visual**: `ElevatedButton` with radius **16**, vertical padding 16, elevation **8**, primary shadow 50%, white foreground, 16px bold label.
- **Loading behavior - layout jump**: when `isLoading` is true the widget **replaces the entire button with a centered `CircularProgressIndicator`** (lines 251-255) - the control disappears and the layout height collapses (no `SizedBox`/min-height retained). This is a repeating visual bug distinct from `VPLoadingButton` (dead) which keeps the button shape. Verify: `VPButton(isLoading:true)` returns `Center(child: CircularProgressIndicator)` - it is not inside the button, so no disabled semantics, no label, dimensions change.
- **Disabled state**: `onPressed: null` on `ElevatedButton` (standard grey-out) only when not loading.
- **A11y**: text label exists; loading state removes all semantics.
- **Theme**: **ignores `ThemeData`** (does not use `filledButtonTheme`/`buttonTheme`/`colorScheme.primary`); hardcodes `AppColors.primary` foreground white, elevation 8.
- **Loc**: label pre-localized by caller.
- **Deps**: `VpWidgets`, `AppColors`.
- **Usage**: login_screen:85, register_screen:69, change_password_screen:90, partner_invite_dialog:74.

### VPTextField - `vp_widgets.dart:282-356`

- **Purpose**: branded text input (auth + invite flows).
- **API**: `{required controller, required label, required hint, IconData? icon, bool isPassword, bool obscureText, VoidCallback? onTogglePassword, TextInputType inputType}`.
- **Visual**: floating label (12px `white70`, left 4/bottom 8) above a `DecoratedBox` (cardDark fill, radius **16**, `white10` border) wrapping a `TextField` with `InputBorder.none`; inside: `white` text, `white24` hint, `white38` prefix icon, optional visibility toggle.
- **State**: fully controlled (controller passed in); visibility toggle driven by caller (`obscureText` + `onTogglePassword`).
- **Error behavior**: **no inline validation** - there is no `errorText`/`validator` plumbing; callers validate ad-hoc and surface errors via `UIUtils.showSnackBar` (see login_screen.dart:92-101, register_screen.dart:86-94). Contrast with the raw emoji `TextField` (emoji_picker_sheet.dart:218) which DOES use `errorText` inline - two validation paradigms.
- **A11y**: no `labelText`/`semanticLabel` (the visible label is a separate `Text`), no `autofillHints`, no `onTapOutside` handling.
- **Theme**: dark-only (cardDark bg, white text) - broken in light theme.
- **Loc**: `label`/`hint` passed pre-localized.
- **Deps**: none beyond Flutter.
- **Usage**: login/register/change-password/partner-invite (9 call sites).

### VPHeader - `vp_widgets.dart:358-405`

- **Purpose**: top bar with centered title + back button / leading / trailing.
- **API**: `{required String title, bool showBackButton=true, VoidCallback? onBack, List<Widget>? trailing, Widget? leading}`.
- **Behavior**: `leading ?? (showBackButton ? IconButton(arrow_back_ios_new, white70, onBack ?? `Navigator.pop`) : SizedBox(width:40))`; balance-height placeholders preserve centering.
- **A11y**: back `IconButton` has no `tooltip`/semantic label.
- **Theme/Loc**: dark-only; title pre-localized.
- **Usage**: change_password:35, bucket_list:138, game:40, localization:22, profile:132.

### VPCard - `vp_widgets.dart:407-446`

- **Purpose**: generic glass card.
- **API**: `{required child, EdgeInsetsGeometry? padding (default 24 all), EdgeInsetsGeometry? margin, double borderRadius=24, Color? borderColor, Color? shadowColor, double blurRadius=20}`.
- **Behavior**: `VpWidgets.cardDecoration`; `shadowColor==null` → centered shadow; otherwise shadow aligned to offset zero.
- **Visual**: cardDark fill, white-5% border (or given), radius 24 (default).
- **Theme/Loc**: dark-only.
- **Usage**: minimal (5 refs incl. def) - most screens use bespoke `Container`s or raw `Card`s instead.

### VPScaffold - `vp_widgets.dart:512-564`

- **Purpose**: app-level scaffold wrapper.
- **API**: `{String? title, required Widget body, List<Widget>? actions, Widget? leading, Widget? bottomNavigationBar, bool showAppBar=true, bool centerTitle=true, Color? backgroundColor, Widget? floatingActionButton}`.
- **Behavior**: `Scaffold` with `backgroundDark` bg; AppBar with 80%-opacity background, no elevation, centered bold white title; honors extras.
- **Theme**: dark-only (light theme not considered).
- **Usage**: bucket_list:127, game:34, homepage:90 (with `showAppBar:false`), mood:42, partner:34, localization:13, profile:114. **Bypassed** by `change_password_screen.dart:30`, `splash_screen.dart:59`, `drive_item_screen.dart:212`, `drive_screen.dart:50` (raw `Scaffold` + custom sliver appbar), `favorites_screen.dart:32`.

### VPSectionHeader - `vp_widgets.dart:566-612`

- **Purpose**: 12px uppercase letter-spaced section label + optional action link.
- **API**: `{required String title, String? actionLabel, VoidCallback? onActionTap, EdgeInsets padding}`.
- **Behavior**: `GestureDetector` action with `AppColors.primary` 12px bold text; default padding 24/16.
- **A11y**: `GestureDetector` (no button semantics, no `onTap` disabled-state guard).
- **Usage**: mood, profile, others (9 refs).

### VPDialog - `vp_widgets.dart:614-645`

- **Purpose**: branded `AlertDialog` wrapper.
- **API**: `{required String title, required Widget content, List<Widget>? actions}`.
- **Behavior**: wraps content in `Theme(data: ThemeData(brightness: Brightness.dark))` — **forces dark brightness** regardless of app theme — `AlertDialog(cardDark, radius 24, 20px bold title)`.
- **A11y**: forced brightness changes contrast semantics for a11y tooling.
- **Usage**: register confirm-email (register:116), update dialog (update_service.dart:65), and 3 more.

### VPAuthLayout - `vp_widgets.dart:647-809`

- **Purpose**: login/register screen shell.
- **API**: `{required String title, required String subtitle, required List<Widget> children, Widget? footer}`.
- **Behavior**: full-height `SingleChildScrollView`/`ConstrainedBox`/`IntrinsicHeight`/`Column`; **hero header** = 35% viewport gradient (`primary→neonPurple`), decorative alpha circles, heart icon in frosted rounded square, **`context.loc.appTitle`** at 40px + `context.loc.appTagline`; a 32px curved `backgroundDark` overlap; form area with title/subtitle (28px/14px), children, `Spacer`, footer.
- **Loc**: reads `appTitle`/`appTagline` internally (the only DS component using `context.loc` directly); title/subtitle passed by caller.
- **Theme**: dark-only.
- **Usage**: login_screen:26, register_screen:27.

### VPAuthLink - `vp_widgets.dart:811-846`

- **Purpose**: auth footer tappable link ("No account? Sign up").
- **API**: `{required String text, required String actionText, required VoidCallback onTap}`.
- **Behavior**: centered `Row`; neutral 14px text (`white54`) + `TextButton` with `neonPurple` bold action.
- **A11y**: text separate from button (screen readers read both); no location hint.
- **Usage**: login:29, register:30.

### VPMiniAvatar - `vp_mini_avatar.dart:5-49`

- **Purpose**: tiny 24px avatar for lists (game history).
- **API**: `{String? imageUrl, double size=24}`.
- **Behavior**: resolves URL via `ApiService.resolveProtectedMediaUrl` (line 17) then renders **`Image.network` directly** (line 29) - **not cached, no auth headers, no placeholder** (only `errorBuilder` to fallback). Distinct from `VPAvatar` (which uses `ProtectedNetworkImage` = cached + authenticated).
- **A11y**: none.
- **Usage**: game_history_card.dart:76,79.
- **Design smell**: same problem-domain component as `VPAvatar` implemented a different way (see Findings F-DS3).

### VPCircleButton - `vp_circle_button.dart:3-53`

- **Purpose**: 40px circular icon button.
- **API**: `{required IconData icon, required Color color, required VoidCallback onTap, bool isFill=false, double size=24, bool hasShadow=true}`.
- **Behavior**: `InkWell` (radius 50) on frosted container (white 10% fill, white-5% border), `Icon` with optional `fill:1.0` and matching-color glow shadow.
- **A11y**: no tooltip/`Semantics`.
- **Usage**: ONLY drive_screen.dart:91 (back button). Nearly dead.

### VPFilterChip - `vp_filter_chip.dart:6-62`

- **Purpose**: pill filter chip (drive media by type).
- **API**: `{required String label, bool isActive=false, IconData? icon, Color? iconColor, VoidCallback? onTap}`.
- **Behavior**: `GestureDetector` pill; active = `neonPurple` fill + glow shadow + white bold 11px uppercase text; inactive = **hardcoded `Color(0xFF1E0B36)`** (line 29) with `Colors.grey[300]` text and `neonPurple` 30% border.
- **A11y**: `GestureDetector` raw (no `FilterChip`/`Chip` semantics, no disabled state).
- **Theme/Loc**: dark-only; labels pre-localized and `.toUpperCase()`-ed by the chip.
- **Usage**: drive_screen.dart:149-157.

### VPLoadingButton (DEAD CODE) - `vp_loading_button.dart:7-54`

- **Purpose**: `FilledButton` with inline 20px spinner.
- **API**: `{required Future<void> Function()? onPressed, required String text, bool isLoading=false, IconData? icon}`.
- **Usage**: **zero usages** across the app (only definition + barrel export). Unstale `FilledButton` that also contradicts `VPButton`'s loading semantics.

### VPLoadingOverlay (DEAD CODE) - `vp_loading_overlay.dart:7-48`

- **Purpose**: full-screen scrim + centered `Card` with spinner/optional message.
- **API**: `{required bool isLoading, String? message, required Widget child}`.
- **Visual/Theme**: black 50% scrim, default theme `Card` (no `AppColors` styling).
- **Usage**: **zero usages**.

### ErrorDialog - `error_dialog.dart:9-102`

- **Purpose**: standard error / retry dialog.
- **API**: constructor `{required String message, String title='', String? details, String? errorCode, VoidCallback? onRetry}` + static `ErrorDialog.show(context, {...})`.
- **Behavior**: `AlertDialog`; resolved title falls back to `context.loc.error_dialogTitle`; message; debug-only error-code badge (`Colors.red` 10% fill, monospace 11px) and debug-only details block; actions: close (`common_close`) + optional retry (`common_retry`) that pops then calls `onRetry`.
- **A11y**: no explicit semantics; title auto-label.
- **Loc**: only the two labels localized; title/message passed by caller.
- **Theme**: follows app theme (not forced dark, unlike `VPDialog`) - inconsistent with `VPDialog`.
- **Deps**: `DialogUtils.showError` uses it (error_handler reauth/error dialogs path).
- **Usage**: via `DialogUtils.showError` (error_handler.dart:240) and `ErrorDialog.show` (5 refs).

### ProtectedNetworkImage - `protected_network_image.dart:7-42`

- **Purpose**: authenticated image loader wrapping `cached_network_image`.
- **API**: `{required String url, BoxFit? fit, placeholder, errorWidget, double? width, double? height, BaseCacheManager? cacheManager}`.
- **Behavior**: resolves via `ApiService.resolveProtectedMediaUrl(url) ?? url` (line 29) and fetches with `httpHeaders: ApiService.authHeaders` (line 33) and a `BaseCacheManager` (typically `MediaCacheManager()`). Defaults: centered `CircularProgressIndicator` placeholder; `Icons.broken_image` 64px error.
- **Auth**: YES - requires a live Supabase session token in headers.
- **NET**: yes; caching controlled by passed manager.
- **Deps**: `cached_network_image`, `flutter_cache_manager`, `ApiService`.
- **Usage**: `VPAvatar` (via `MediaCacheManager`); direct use 4 refs.

---

## Usage map

| Component | Active call sites | Barely used / dead |
|---|---|---|
| VpWidgets helpers | 69 refs | - |
| VPSettingGroup / VPSettingTile / VPDivider | profile only | - |
| VPAvatar | profile, partner, VPUserAvatar | - |
| VPUserAvatar | game screen only | `onlineIndicator` never used |
| VPButton | login, register, change-password, partner-invite | - |
| VPTextField | auth + partner-invite | - |
| VPHeader | 5 screens | - |
| VPCard | 5 refs | underused (most screens use raw Container) |
| VPScaffold | 7 screens | bypassed by 5 screens |
| VPSectionHeader | 9 refs | - |
| VPDialog | 5 refs | - |
| VPAuthLayout / VPAuthLink | login + register | - |
| VPMiniAvatar | game history | - |
| VPCircleButton | drive back button | deathly quiet |
| VPFilterChip | drive | - |
| VPLoadingButton | - | **dead** |
| VPLoadingOverlay | - | **dead** |
| ErrorDialog | via DialogUtils/ErrorHandler | - |
| ProtectedNetworkImage | via VPAvatar | - |
| PartnerUserTile / PartnerRequestTile (partner_widgets.dart) | - | **dead** |

---

## Findings

### F-DS1: HomepageScreen bypasses the entire design system

**What**: `HomepageScreen` defines a private token class `_C` (9 colors), 11 hardcoded `Color(0x...)` literals, zero `AppColors` usage, its own font family (`Inter`) instead of Plus Jakarta Sans, and 8 private "glass" widgets (`_GlassCard` 592, `_NavIconButton` 629, `_AvatarColumn` 650, `_GlassLinkNode` 704, `_EmojiDisplay` 733, `_MissYouButton` 764, `_GlassIconButton` 837, `_AtmosphericBlob` 867). It is the app's landing screen (tab 0).
**Where**: homepage_screen.dart:13-23, 592-884.
**Impact**: visual fragmentation; the main screen doesn't share the spacing/typography/radius language of every other screen; tokens duplicated and drift-prone.
**Confidence**: HIGH.

### F-DS2: `VPButton` loading state collapses the layout

**What**: when `isLoading` is set, `VPButton` returns a bare centered `CircularProgressIndicator` (vp_widgets.dart:251-255). The button vanishes, form layout jumps, and there is no disabled/loading semantics.
**Where**: vp_widgets.dart:233-280.
**Impact**: every auth submit re-layouts; screen readers lose the button entirely.
**Confidence**: HIGH.

### F-DS3: Three divergent avatar implementations

**What**: `VPAvatar` (resolved URL + cached + auth headers + placeholder/error), `VPMiniAvatar` (resolved URL + uncached `Image.network`, no auth header, error-only), and homepage `_AvatarColumn` (raw `Image.network` **without** `resolveProtectedMediaUrl`, homepage_screen.dart:674).
**Where**: vp_widgets.dart:162-231, vp_mini_avatar.dart:5-49, homepage_screen.dart:650-701.
**Impact**: the same domain concept rendered three ways; the homepage variant breaks on R2-protected URLs (no resolution → HTTP-scheme-less path fails) and none of the three are backed by a single component. The `_AvatarColumn` instance is also the reason homepage avatars are broken (see architecture doc F2).
**Confidence**: HIGH.

### F-DS4: Dead/redundant components

**What**: `VPLoadingButton`, `VPLoadingOverlay`, `PartnerUserTile`, `PartnerRequestTile`, `VPUserAvatar.onlineIndicator` are unreferenced. They also duplicate `VPButton`'s loading semantics and bare-Material tile rendering respectively.
**Where**: vp_loading_button.dart, vp_loading_overlay.dart, partner_widgets.dart:10-68.
**Impact**: triples the button/spinner API surface (VPButton spinner swap, VPLoadingButton inline spinner, VPLoadingOverlay scrim) and keeps unreviewed "design system" surface alive.
**Confidence**: HIGH.

### F-DS5: Theme-vs-component radius/button mismatch

**What**: `AppTheme` sets card radius 12 / input radius 12 / FilledButton radius 12 (app_theme.dart:58,66,75) while VP components use 24 (cards/dialogs), 16 (text field/button); `VPButton` is an `ElevatedButton` (own style, elevation 8) instead of relying on `FilledButtonThemeData`; `VPDialog` forces its own dark `ThemeData`.
**Where**: app_theme.dart:38-88 vs vp_widgets.dart (multiple).
**Impact**: appearance is non-tokenized; changing theme config does not restyle the app; two button subsets that look different.
**Confidence**: HIGH.

### F-DS6: Hardcoded colors / dimensions not in tokens

**What**:
- `VPFilterChip` inactive `Color(0xFF1E0B36)` (vp_filter_chip.dart:29) - a near-duplicate of `cardDark` `0xFF1A0B2E`; also `Colors.grey[300]`.
- homepage `_C` palette + `Color(0x661E1E1E)` (homepage_screen.dart:608,107).
- emoji picker `Color(0xFFA855F7)` (emoji_picker_sheet.dart:242).
- pervasive `Colors.white54/70/24/38` literals across all feature screens (38+ hits outside `design_system`), hardcoded 40px/48px icon-box sizes, `Colors.red`/`green` for accept/reject and wipe buttons.
**Where**: multiple files ('features/**', 'shared/**').
**Impact**: token drift; the centralized palette is not authoritative.
**Confidence**: HIGH.

### F-DS7: Light theme is effectively unsupported

**What**: every VP component and most feature screens hardcode dark colors (`cardDark`, `backgroundDark`, `deepViolet`, `Colors.white` text). `AppTheme.light` exists and `ThemeProvider` can switch, but nothing reads `Brightness`; `VPDialog` even forces `Brightness.dark`, and `RefreshIndicator` backgrounds hardcode `backgroundDark` (e.g. mood_screen.dart:64).
**Where**: entire DS + features.
**Impact**: toggling to light theme yields broken contrast (white-on-white text in cards, dark chips everywhere). Combined with `ThemeProvider` not persisting, the mode is cosmetic-only.
**Confidence**: HIGH.

### F-DS8: Two snackbar systems and inconsistent dialog families

**What**: `ErrorHandler` global overlay snackbar vs `UIUtils.showSnackBar` (ScaffoldMessenger). Dialogs split across `VPDialog`, `ErrorDialog`, and bare `AlertDialog`s (logout_utils.dart:13, profile wipe profile_screen.dart:67, bucket add bucket_list_screen.dart:46, drive-item delete drive_item_screen.dart:196-205, partner invite) - each re-styling independently.
**Where**: error_handler.dart:155-235, snackbar_utils.dart:9-39.
**Impact**: mixed UX (overlay vs floating toast; dark-only vs themed dialogs), duplicated code, and no single dialog component.
**Confidence**: HIGH.

### F-DS9: Two TextField families and two validation paradigms

**What**: `VPTextField` (cardDark box, no errorText) vs raw `TextField`s re-styled inline in bucket_list_screen.dart:54-70 and emoji_picker_sheet.dart:211-232 (the latter with inline `errorText`). Validation: snackbar-based (login/register) vs inline errorText (emoji picker).
**Impact**: inconsistent field look and error UX across screens.
**Confidence**: HIGH.

### F-DS10: Localization gaps in the "shared" UI

**What**: emoji picker ships hardcoded Italian strings `'Scegli il tuo Mood'`, `'Inserisci un'emoji...'` (emoji_picker_sheet.dart:199,215); `AppTheme`/`error_dialog` are fine, but `MediaPickerService` labels are localized while the emoji picker's are not. The `mood` bottom sheet is a shared-style component with feature text baked in.
**Impact**: unlocalized UI breaks the it/en language system.
**Confidence**: HIGH.

### F-DS11: Accessibility not implemented

**What**: **zero** `Semantics` and zero `Tooltip` usages anywhere in `lib/`. Icon-only `IconButton`s (mood back/analytics, bucket delete, drive ellipsis, invitation check/close) have no tooltips; nav icon buttons and link/text-buttons frequently use `GestureDetector` without button semantics (`VPSectionHeader` action, `VPFilterChip`, `VPAuthLink`, homepage `_NavIconButton`, `_GlassIconButton`); toggles lack state announcements.
**Impact**: screen-reader UX degraded; no accessibility regression protection.
**Confidence**: HIGH.

### F-DS12: Components masquerading as generic but coupled to feature/infra

**What**: `ProtectedNetworkImage` and `VPAvatar`/`VPMiniAvatar` depend on `ApiService` (they are the correct design for protected media, but they cement infra into the DS). `VPAuthLayout` proudly renders the brand (appTitle/appTagline) - reusable only for auth. `HomeBottomNav` is shell-specific. `VPUserAvatar.onlineIndicator` is decorative-only dead code (never materialized anywhere).
**Impact**: "reusable component" classification is misleading; refactoring `ApiService` signature ripples into the DS.
**Confidence**: HIGH.

### F-DS13: ChangePasswordScreen styling bypass

**What**: the screen uses raw `Scaffold` (change_password_screen.dart:30) plus `VPHeader`/`VPTextField`/`VPButton` - a hybrid that doesn't use `VPScaffold`.
**Impact**: minor inconsistency with sibling auth flows.
**Confidence**: HIGH.

### F-DS14: `VPButton`/`FilledButton` disabled styling divergence

**What**: VPButton disabled = default ElevatedButton grey; game answer buttons set `disabledBackgroundColor: Colors.white10`; update dialog 'now' buttons have no explicit disabled style; `VPLoadingButton` disabled = `onPressed:null`. Disabled/loading visual language is not unified.
**Confidence**: HIGH.

### F-DS15: `EmojiPickerSheet`/bottom-sheet family

**What**: mood bottom sheet (ScrollDraggableSheet) vs `MediaPickerService.showPickerSheet` - both bespoke bottom sheets with duplicated frosted-styling, neither part of the DS barrel.
**Confidence**: HIGH.

---

## Implementation status

| Area | Status |
|---|---|
| Central tokens (`AppColors`) | IMPLEMENTED (partial adoption) |
| Central theme (`AppTheme` dark/light) | IMPLEMENTED (light unused) |
| Branded core components (inputs, buttons, cards, dialogs, layout) | IMPLEMENTED |
| Unified avatar component | PARTIALLY IMPLEMENTED (3 divergent variants) |
| Unified loading component | NOT IMPLEMENTED (3 contenders, 2 dead) |
| Unified dialog component | PARTIALLY IMPLEMENTED (VPDialog + ErrorDialog + raw AlertDialogs) |
| Unified snackbar/toast | NOT IMPLEMENTED (2 systems) |
| Accessibility (Semantics/Tooltip) | NOT IMPLEMENTED |
| Localization inside DS | PARTIALLY IMPLEMENTED (emoji picker bypass) |
| Light-mode support | NOT IMPLEMENTED |
| Homepage alignment to DS | NOT IMPLEMENTED (wholesale bypass) |
| Dead component cleanup | NOT DONE (VPLoadingButton, VPLoadingOverlay, PartnerUserTile, PartnerRequestTile) |

---

## Notes

- `design_system.dart` barrel is re-exported by `all_imports.dart`; importing the app barrel already provides all DS components - no per-file imports needed.
- File naming is inconsistent: `vp_widgets.dart` hosts 15+ components while peer components each live in their own file; `VpWidgets` (helper class) vs `VP*` (components) capitalization differs.
- No design-token dims/spacing file exists; every spacing (`SizedBox`, padding) is inline magic numbers.
- No widget/storybook/golden tests exist for the DS (`Flutter/test/` has only state/API unit tests); a design-system regression is caught only visually.
- Consistency recommendation: promote homepage `_C` into `AppColors`, unify on `ProtectedNetworkImage` for all avatars, delete dead components, route all buttons through one `VPButton`/`FilledButtonThemeData`, unify dialogs into `VPDialog`+`ErrorDialog`, pick one snackbar, and add `Semantics`/tooltips, plus an `errorText` slot on `VPTextField`.