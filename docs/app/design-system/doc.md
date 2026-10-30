# JustUS Flutter Design System - VP Widget System & Shared UI

## Overview

The design system ("Violet Punk") lives in `Flutter/lib/shared/design_system/` and is exported through the barrel `design_system.dart`, which re-exports `vp_widgets.dart` plus its satellite components (`error_dialog.dart`, `vp_sheet.dart`, `vp_circle_button.dart`, `vp_filter_chip.dart`; the image/avatar components now live in `lib/shared/widgets/` because they depend on `ApiService`).

`vp_widgets.dart` is the **core file** and hosts 13 components plus the `VpWidgets` static helper class. The satellite files each host one component.

Design tokens are centralized in `core/theme/`:

- `app_palette.dart` - `AppPalette` theme extension: brand-fixed Violet-Punk colors (`brandPrimary` `#7F13EC`, brand neon accents, gradients, hero overlays), plus the dark and light semantic palettes (`canvas`, `surface`, `surfaceSunken`, `surfaceGroup`, the content ramp `contentPrimary` … `contentHint`, borders, shadows/scrims, status colors, neutrals, `home*`). Widgets read the active palette through `context.palette`.
- `app_radius.dart` - `AppRadius` (`xs 4`, `sm 12`, `md 16`, `lg 24`, `sheet 32`, `pill 100`).
- `app_dimens.dart` - `AppSpacing` (4/8/16/24/32) and `AppDims` (icon box 48, circle button 40, button min height 52, nav bar, checkbox, form gap).
- `app_theme.dart` - `AppTheme.dark` / `AppTheme.light` Material 3 themes (Plus Jakarta Sans text theme, seeded color scheme, appBar/card/input/button/text-button/dialog theme data) and `AppButtonStyle` (the single source of button geometry + disabled colors).
- `theme_provider.dart` - runtime mode holder: `loadSavedMode()` rehydrates the `ThemeMode` from `SharedPreferences` (`app_theme_mode`) before `runApp`, `setThemeMode()`/`toggle()` persist the change, and an unrecognized stored value falls back to `ThemeMode.dark`. Device-level preference, so `StorageService.clearAll()` preserves it across logout/wipe.

**One design language.** All feature screens — including `HomepageScreen` — use the VP system (deep-violet glass/punk). The homepage has no private "Midnight Glass" palette: its former `_C` tokens were promoted into `AppPalette` (the `home*` family), it uses the theme's Plus Jakarta Sans font, and its avatars go through `VPAvatar`/`VPUserAvatar` (which resolves protected R2 URLs + auth headers). Still specialized to the homepage are the glass widgets (`_GlassCard`, `_GlassIconButton`, `_GlassLinkNode`, `_MissYouButton`, ...).

---

## Shared UI infrastructure (outside `shared/design_system/` but part of the UI layer)

| File | Role |
|---|---|
| `core/error_handling/error_handler.dart` | The app's single feedback mechanism: `showSnackBar` (root-overlay toast, `isError` + optional `backgroundColor`), plus the error dialog and reauth dialog. `navigatorKey` doubles as the fallback context so feedback survives a route pop |
| `shared/utils/ui/dialog_utils.dart` | `DialogUtils.showError` (wraps `ErrorDialog`), `showPartnerInvite` |
| `shared/utils/ui/validators.dart` | `Validators.validateEmail/Password/Required` - localized form validation used by auth screens |
| `shared/utils/ui/media_picker_service.dart` | Camera/gallery bottom sheet (`VPSheet` + `ListTile`s, localized labels) |
| `shared/utils/auth/logout_utils.dart` | Logout confirm dialog (`VPDialog`) |
| `shared/widgets/tab_screen.dart` | `TabScreen`/`TabScreenMixin` - tab activation infrastructure |
| `features/home/widgets/home_bottom_nav.dart` | Floating 7-item bottom nav (shell component, uses tokens + `Semantics(label:)`, not part of the DS barrel) |

Feedback and dialogs are single-sourced: `ErrorHandler.showSnackBar` is the only snackbar/toast path and `VPDialog` is the only `AlertDialog` constructor. `test/feedback_system_test.dart` enforces both invariants. State-owned status messages reach that same path through the `StateMessageListener` mixin (see `docs/app/state-management/doc.md`), so no screen builds its own toast.

---

## Design tokens - `core/theme/`

Five token files, all consumed through the app barrel (`all_imports.dart`):

| File | Exposes | Role |
|---|---|---|
| `app_palette.dart` | `AppPalette` | brand palette + dark/light semantic surfaces + content ramp + shadows/scrims + status + neutrals + `home*` |
| `app_category_colors.dart` | `AppCategoryColors` | categorical accents for bucket categories (identity colors, not theme colors) |
| `app_radius.dart` | `AppRadius` | `xs 4`, `sm 12`, `md 16`, `lg 24`, `sheet 32`, `pill 100` |
| `app_dimens.dart` | `AppSpacing`, `AppDims` | spacing `xs 4` / `sm 8` / `md 16` / `lg 24` / `xl 32` + recurring component sizes (icon box 48, circle button 40, button min height 52, nav bar, checkbox, form gap) |
| `app_theme.dart` | `AppTheme`, `AppButtonStyle` | Material 3 themes + the shared button geometry/disabled palette |

`AppPalette` highlights (dark values; the light palette redefines the same semantic tokens):

| Token | Value | Role |
|---|---|---|
| `brandPrimary` | `0xFF7F13EC` | primary brand / buttons |
| `brandAccentAqua` | `0xFF00D4FF` | secondary accent |
| `brandNeonPurple` / `brandNeonBlue` / `brandNeonGreen` / `brandNeonPink` | `0xFFBC13FE` / `0xFF00F5FF` / `0xFF00FFD9` / `0xFFFF0080` | gradient + status accents |
| `brandGradientStart` / `brandGradientAccent` | `0xFF7F13EC` / `0xFFA855F7` | auth + picker gradients |
| `dark.canvas` / `light.canvas` | `0xFF191022` / `0xFFF7F6F8` | scaffold backgrounds |
| `dark.surface` / `light.surface` | `0xFF1A0B2E` / `0xFFFFFFFF` | cards / text fields / dialogs |
| `dark.surfaceSunken` | `0xFF120526` | darkest stage / icon well |
| `dark.surfaceGroup` | `0x662D1652` | grouped-settings fill (40% `#2D1652`) |
| `contentPrimary` … `contentHint` | theme-dependent | ink ramp |
| `overlay` / `glass` / `track` / `surfaceElevated` | theme-dependent | borders, glass fills, tracks, chip/banner fills |
| `backdrop` | `0xFF12091D` (dark) | full-screen media viewer |
| `shadow` / `shadowSoft` / `shadowStrong` / `shadowToast` / `scrim` | theme-dependent | elevation + media overlay |
| `danger` / `dangerSurface` / `success` / `warning` / `info` / `infoSurface` / `accent*` | theme-dependent | status + accents |
| `neutralMuted` / `neutralStrong` / `neutralText` | theme-dependent | media placeholders, secondary text |

`app_palette.dart` is the **only** file allowed to reference `Colors.*` or a raw
`Color(0x…)`; `test/import_hygiene_test.dart` + the analyzer keep feature code on
the semantic tokens. Alpha modulation of a token (`context.palette.accentPurple
.withValues(alpha: 0.3)`) is the sanctioned way to derive shades.

`AppTheme._build` centralizes: Material 3, `ColorScheme.fromSeed(palette.primary, brightness: palette.brightness)` with brand/surface overrides,
Plus Jakarta Sans text theme, `scaffoldBackgroundColor: palette.canvas`, `AppBarTheme`,
`CardThemeData` (radius **lg 24**), `InputDecorationTheme` (radius **md 16**),
`FilledButtonThemeData`, `TextButtonThemeData`, `DialogThemeData` (radius **lg
24**). Button geometry lives once in `AppButtonStyle` (`shape`, `padding`,
`minimumSize`, disabled palette) and is consumed by both
`FilledButtonThemeData` and `VPButton`, so the theme-level button and the
flagship component cannot drift.

---

## Component-by-component analysis

Legend: AUTH = requires logged-in session; NET = performs network/image fetch; each entry lists Purpose / API / Visual / State / Loading / Error / A11y / Theme / Loc / Deps.

### VpWidgets (static helpers) - `vp_widgets.dart:5-58`

- **Purpose**: shared typography + decoration builders used by every VP component.
- **API**: `googleFont({fontSize,fontWeight,color,letterSpacing,fontStyle,height,decoration,decorationColor})`; `boxShadow({color,blurRadius,offset})`; `cardDecoration({color,borderRadius,borderColor,boxShadow})`.
- **Behavior**: `cardDecoration` defaults color `context.palette.surface`, radius **24**, `context.palette.border` border, shadow offset(0,10) blur 20; `boxShadow` defaults `context.palette.shadow`.
- **Theme**: helper only; reads `context.palette` for defaults, callers may override.
- **Deps**: `google_fonts`, `context.palette`.
- **Usage**: 69 references across the app.

### VPSettingGroup - `vp_widgets.dart:60-80`

- **Purpose**: rounded container grouping setting tiles.
- **API**: `VPSettingGroup({required List<Widget> children})`.
- **Visual**: `DecoratedBox` with `surfaceGroup` fill, `context.palette.border` border, `AppRadius.lg`.
- **State/A11y**: stateless, no semantics.
- **Loc/Theme**: none (uses `context.palette` directly; theme-aware).
- **Deps**: none.
- **Usage**: only `profile_screen.dart` (7 references incl. definition barrel) - profile settings groups.

### VPSettingTile - `vp_widgets.dart:82-156`

- **Purpose**: settings row (icon square + title + subtitle + trailing control).
- **API**: `{required IconData icon, required String title, required String subtitle, required Widget trailing, required Color color, VoidCallback? onTap}`.
- **Visual**: `AppDims.iconBox` (48x48) icon container (`surfaceSunken` fill, `color`-based 20% border, `AppRadius.md`); bold `contentPrimary` 16px title, `contentTertiary` 11px letter-spaced subtitle; `InkWell` radius `AppRadius.lg`; padding `AppSpacing.lg`.
- **State**: optional tap; no ripple customization beyond default.
- **A11y**: `Semantics` + `MergeSemantics` (line 103) expose icon + title + subtitle + trailing control as one row; the trailing widget (e.g. `Switch`) keeps its own state semantics.
- **Theme/Loc**: tokens only (`contentPrimary`/`contentTertiary`); strings passed in pre-localized by the caller.
- **Usage**: profile screen settings only (11 refs incl. def).
- **Design smell**: `subtitle` is `required` even where there is no subtitle - callers pass fabricated strings (e.g. dark-mode row shows a subtitle for a switch).

### VPDivider - `vp_widgets.dart:158-170`

- **Purpose**: themed hairline separator.
- **API**: `VPDivider()` (no params).
- **Visual**: Material `Divider`, height `AppDims.hairline`, `context.palette.divider`, indent/endIndent `AppSpacing.md` (16).
- **Theme/Loc**: theme-aware (`context.palette.divider`); no strings.
- **Usage**: profile (bug: divider inside `VPDivider`'s own children used between setting tiles) and elsewhere minimally.

### VPAvatar - `shared/widgets/vp_avatars.dart:5-76`

- **Purpose**: couple-profile avatar (used for user & partner photos).
- **API**: `{String? imageUrl, double size=80, Color? borderColor, bool isUploading=false}`.
- **Behavior**: `imageUrl` is passed through `ApiService.resolveProtectedMediaUrl()` (line 21) to rewrite R2 object keys into `/api/v1/media/file?filename=...`. When resolved, renders `ProtectedNetworkImage` (cached, authenticated headers) inside `ClipOval`. When null → placeholder `Icons.person` in `contentTertiary`.
- **Visual**: circular ring (`borderColor`, default `context.palette.accentPink`) 2px + glow shadow (30% alpha, blur 20); optional full-cover upload spinner `CircularProgressIndicator` with the ring color.
- **Loading**: `CircularProgressIndicator(strokeWidth:2)` placeholder + full-cover overlay when `isUploading`.
- **Error**: `Icons.error` in `contentTertiary`.
- **A11y**: none (no `Semantics`, no `excludeFromSemantics` for decorative circle).
- **Theme/Loc**: theme-aware; border default `accentPink` (no string params).
- **Auth**: image fetch uses `ApiService.authHeaders` (needs a live Supabase session).
- **NET**: yes (cached network image).
- **Deps**: `ApiService`, `MediaCacheManager`, `ProtectedNetworkImage`.
- **Usage**: profile_screen.dart:183,192; partner_screen.dart:211; inside `VPUserAvatar`.

### VPUserAvatar - `shared/widgets/vp_avatars.dart:78-125`

- **Purpose**: avatar + uppercase name label + optional status indicator (game player cards).
- **API**: `{required String name, String? imageUrl, Widget? indicator, double size=80}`.
- **Behavior**: delegates image rendering to `VPAvatar` with a subdued border (`context.palette.overlay`); overlays `indicator` bottom-right; caption 12px bold letter-spaced `contentPrimary`.
- **A11y**: none.
- **Theme/Loc**: theme-aware; `name` pre-localized by caller.
- **NET/Auth**: inherits from `VPAvatar` when an image is present.
- **Usage**: only `game_screen.dart:373,387` (question status columns).

### VPButton - `vp_widgets.dart:172-232`

- **Purpose**: primary full-width action button (login / register / change-password / partner invite).
- **API**: `{required String label, VoidCallback? onPressed, bool isLoading=false, Color? backgroundColor, double? width}`.
- **Visual**: `FilledButton` with `AppButtonStyle` geometry (`AppRadius.md` **16**, padding 16, min height **52**, primary shadow, white foreground, 16px bold label) - identical to the app-wide `FilledButtonThemeData` so a `FilledButton` and a `VPButton` are visually the same control.
- **Loading behavior**: the label is swapped **in place** for a `Row(spinner + label)` with `onPressed: null`; the button keeps its size and semantics (it is a `Busy` node via `Semantics`) instead of collapsing to a bare spinner.
- **Disabled state**: `onPressed: null` with the shared `AppButtonStyle.disabledBackground` / `disabledForeground` palette, identical for `VPButton` and every themed `FilledButton`; a per-call `backgroundColor` derives its disabled shade with `withValues(alpha:)`.
- **A11y**: text label always present (also while loading); `Semantics(button: true, busy: isLoading)`.
- **Theme**: consumes `Theme.of(context).filledButtonTheme`/theme tokens - no inline elevation, radius or color literals.
- **Loc**: label pre-localized by caller.
- **Deps**: `VpWidgets`, `AppButtonStyle`, `AppDims`, `context.palette`.
- **Usage**: login_screen, register_screen, change_password_screen, partner_invite_dialog.

### VPTextField - `vp_widgets.dart:234-329`

- **Purpose**: branded text input (auth + invite flows).
- **API**: `{required controller, required hint, String? label, IconData? icon, bool isPassword, bool obscureText, VoidCallback? onTogglePassword, TextInputType inputType, String? errorText, ValueChanged<String>? onChanged, ValueChanged<String>? onSubmitted}`.
- **Visual**: optional floating label (12px `contentSecondary`, left 4/bottom 8) above a `DecoratedBox` (`surface` fill, `AppRadius.md`, `border` border) wrapping a `TextField` with `InputBorder.none`; inside: `contentPrimary` text, `contentHint` hint, `contentDisabled` prefix icon and visibility toggle, and a red inline `errorText` when provided.
- **State**: fully controlled (controller passed in); visibility toggle driven by caller (`obscureText` + `onTogglePassword`).
- **Error behavior**: two sanctioned paradigms — inline `errorText` for field-scoped problems (bucket add, emoji picker) and `ErrorHandler.showSnackBar(..., isError: true)` for form-wide problems (login/register). The component supports the first; the second stays with the caller.
- **A11y**: no `labelText`/`semanticLabel` (the visible label is a separate `Text`), no `autofillHints`, no `onTapOutside` handling.
- **Theme**: theme-aware (`surface` fill + content ramp), adapts to light theme.
- **Loc**: `label`/`hint` passed pre-localized; the password toggle is localizable via the `onTogglePassword` caller's tooltip.
- **Deps**: `google_fonts`, `context.palette`, `context.loc`.
- **Usage**: login/register/change-password/partner-invite, bucket add dialog, emoji picker.

### VPHeader - `vp_widgets.dart:331-389`

- **Purpose**: top bar with centered title + back button / leading / trailing.
- **API**: `{required String title, bool showBackButton=true, VoidCallback? onBack, List<Widget>? trailing, Widget? leading}`.
- **Behavior**: `leading ?? (showBackButton ? IconButton(tooltip: context.loc.common_back, arrow_back_ios_new, contentSecondary, onBack ?? `Navigator.pop`) : SizedBox(width: AppDims.circleButton))`; balance-width placeholders preserve centering.
- **A11y**: the back `IconButton` carries a localized `Tooltip` (also announced as its semantic label).
- **Theme/Loc**: theme-aware (`contentSecondary` back icon, `contentPrimary` title); title pre-localized.
- **Usage**: change_password, bucket_list, game, localization, mood, profile, favorites, drive, reset_password (9 screens).

### VPCard - `vp_widgets.dart:391-432`

- **Purpose**: generic glass card.
- **API**: `{required child, EdgeInsetsGeometry? padding, EdgeInsetsGeometry? margin, double borderRadius=AppRadius.lg, Color? borderColor, Color? shadowColor, double blurRadius=20}`.
- **Behavior**: `VpWidgets.cardDecoration`; `shadowColor==null` → centered shadow; otherwise shadow aligned to offset zero.
- **Visual**: `surface` fill, `border` border (or given), `AppRadius.lg` (default).
- **Theme/Loc**: theme-aware.
- **Usage**: minimal (5 refs incl. def) - most screens use bespoke `Container`s or raw `Card`s instead.

### VPScaffold - `vp_widgets.dart:434-487`

- **Purpose**: app-level scaffold wrapper.
- **API**: `{String? title, required Widget body, List<Widget>? actions, Widget? leading, Widget? bottomNavigationBar, bool showAppBar=true, bool centerTitle=true, Color? backgroundColor, Widget? floatingActionButton}`.
- **Behavior**: `Scaffold` with `canvas` bg; AppBar with 80%-opacity background, no elevation, centered bold `contentPrimary` title; honors extras.
- **Theme**: theme-aware (`canvas`/`contentPrimary`).
- **Usage**: bucket_list, game, homepage (with `showAppBar:false`), mood, partner, localization, profile, change_password, favorites. **Bypassed** by `splash_screen.dart`, `drive_item_screen.dart`, `drive_screen.dart` (raw `Scaffold` + custom sliver appbar) and the auth screens (which use `VPAuthLayout`).

### VPSectionHeader - `vp_widgets.dart:489-544`

- **Purpose**: 12px uppercase letter-spaced section label + optional action link.
- **API**: `{required String title, String? actionLabel, VoidCallback? onActionTap, EdgeInsets padding}`.
- **Behavior**: `contentTertiary` title + `primaryVariant` 12px bold action inside `Semantics(button: true, label: actionLabel)`; default padding 24/16.
- **A11y**: action announces as a button; there is no tap-disabled-state guard (`onActionTap` is passed straight to `GestureDetector`).
- **Usage**: mood, profile, others (9 refs).

### VPSegmentedControl - `vp_widgets.dart:546-629`

- **Purpose**: pill segmented selector (icon + label per option).
- **API**: `VPSegmentedControl<T>({required List<VPSegmentedControlOption<T>> options, required T value, required ValueChanged<T> onChanged})`; option `{value, label, IconData icon}`.
- **Visual**: `surfaceSunken` pill track with `border`, selected segment filled `primary` with `onPrimary` icon/text, unselected `contentTertiary`/`contentSecondary`.
- **A11y**: each option is `Semantics(button: true, selected: isSelected, label: option.label)`; the selected option ignores taps.
- **Theme/Loc**: theme-aware; labels pre-localized.
- **Status**: defined but unused anywhere in `lib/` - dead component candidate.

### VPDialog - `vp_widgets.dart:631-651`

- **Purpose**: the app's only `AlertDialog` wrapper — the single dialog component.
- **API**: `{required String title, required Widget content, List<Widget>? actions}`.
- **Behavior**: plain `AlertDialog` that inherits the app `dialogTheme` (surface `surface`, `AppRadius.lg`, 20px bold title) - no forced `Brightness` override, so it follows the active theme.
- **A11y**: inherits the dialog route's modal semantics; the forced-brightness contrast caveat is gone.
- **Usage**: the only place `AlertDialog` is constructed — register confirm-email, update dialog, logout, captcha, bucket add, drive delete, profile wipe/edit, reauth, `ErrorDialog`, and others (12 call sites). Screens pass localized `title` + `content` + `actions`, so copy and button order are decided once by the theme rather than per screen.

### VPAuthLayout - `vp_widgets.dart:653-818`

- **Purpose**: login/register screen shell.
- **API**: `{required String title, required String subtitle, required List<Widget> children, Widget? footer}`.
- **Behavior**: full-height `SingleChildScrollView`/`ConstrainedBox`/`IntrinsicHeight`/`Column`; **hero header** = 35% viewport gradient (`AppPalette.brandGradientStart→brandNeonPurple`), decorative `brandHeroOverlay` circles, heart icon in `brandHeroGlass` rounded square, **`context.loc.appTitle`** at 40px + `context.loc.appTagline`; a 32px curved `canvas` overlap; form area with title/subtitle (28px/14px), children, `Spacer`, footer.
- **Loc**: reads `appTitle`/`appTagline` internally (the only DS component using `context.loc` directly); title/subtitle passed by caller.
- **Theme**: theme-aware for the form/canvas; the hero gradient is brand-fixed in both themes.
- **Usage**: login_screen:26, register_screen:27.

### VPAuthLink - `vp_widgets.dart:820-857`

- **Purpose**: auth footer tappable link ("No account? Sign up").
- **API**: `{required String text, required String actionText, required VoidCallback onTap}`.
- **Behavior**: centered `Row`; neutral 14px text (`contentTertiary`) + `TextButton` with `accentPurple` bold action.
- **A11y**: text separate from button (screen readers read both); no location hint.
- **Usage**: login:29, register:30.

### VPCircleButton - `vp_circle_button.dart`

- **Purpose**: circular icon button (40px default).
- **API**: `{required IconData icon, required Color color, required VoidCallback onTap, bool isFill=false, double size=24, bool hasShadow=true, String? tooltip}`.
- **Behavior**: `InkWell` (radius `AppRadius.pill`) on a frosted container (`overlay` fill, `border` border, `AppDims.circleButton` 40x40), `Icon` with optional `fill:1.0` and matching-color glow shadow.
- **A11y**: `Semantics(button: true, label: tooltip)` + `InkWell` button semantics; when `tooltip` is non-null the button is wrapped in a `Tooltip`.
- **Theme**: theme-aware (`overlay`/`border`).
- **Usage**: drive_screen back button, drive media action controls.

### VPFilterChip - `vp_filter_chip.dart`

- **Purpose**: pill filter chip (drive media by type).
- **API**: `{required String label, bool isActive=false, IconData? icon, Color? iconColor, VoidCallback? onTap}`.
- **Behavior**: `GestureDetector` pill; active = `accentPurple` fill + glow shadow + `onAccent` bold 11px uppercase text; inactive = `surfaceElevated` with `contentTertiary` text and an `accentPurple` 30% border; optional `icon` tinted by `iconColor`.
- **A11y**: `Semantics(button: true, selected: isActive, label: label)`; a null `onTap` is announced as disabled.
- **Theme/Loc**: theme-aware; labels pre-localized and `.toUpperCase()`-ed by the chip.
- **Usage**: drive_screen.

### InvitationTile - `features/partnership/widgets/invitation_tile.dart`

- **Purpose**: one tile for pending partnership invitations and the partner's cancellation request (reused rather than a parallel card).
- **API**: `{required PartnershipInvitation invite, required bool isReceived, VoidCallback? onAccept, VoidCallback? onReject, String? title, String? subtitle, IconData? leadingIcon, String? acceptTooltip, String? rejectTooltip, bool showAccept = false, bool showReject = false}`.
- **Defaults**: reproduce the invitation rendering exactly - `title` falls back to the invite username, `subtitle` to `partner_wantsToConnect` / `partner_waitingResponse`, `leadingIcon` to `person_add_outlined` / `mail_outline`; received rows show accept + reject, sent rows show the cancel-request action.
- **Custom variant**: the cancellation card passes its own copy, the broken-heart icon and both actions, while `acceptTooltip` / `rejectTooltip` override the default labels.
- **Deps**: `PartnershipInvitation`, `VpWidgets`, `AppPalette`; strings are passed pre-localized by the caller.
- **Tests**: `test/invitation_tile_test.dart` pins the default received/sent rendering and the custom variant.

### Loading: no dedicated component

Loading is inline in `VPButton` (label swap + `Semantics(busy: true)`). There is no
separate loading button or full-screen loading overlay component; a screen that
needs a blocking scrim must build it itself from `context.palette.scrim` + a
`CircularProgressIndicator`.

### ErrorDialog - `error_dialog.dart:9-...`

- **Purpose**: standard error / retry dialog.
- **API**: constructor `{required String message, String title='', String? details, String? errorCode, VoidCallback? onRetry}` + static `ErrorDialog.show(context, {...})`.
- **Behavior**: `AlertDialog`; resolved title falls back to `context.loc.error_dialogTitle`; message; debug-only error-code badge (`Colors.red` 10% fill, monospace 11px) and debug-only details block; actions: close (`common_close`) + optional retry (`common_retry`) that pops then calls `onRetry`.
- **A11y**: no explicit semantics; title auto-label.
- **Loc**: only the two labels localized; title/message passed by caller.
- **Theme**: follows the app theme (no forced brightness override).
- **Deps**: `DialogUtils.showError` uses it (error_handler reauth/error dialogs path).
- **Usage**: via `DialogUtils.showError` (error_handler.dart:240) and `ErrorDialog.show` (5 refs).

### ProtectedNetworkImage - `shared/widgets/protected_network_image.dart:7-...`

- **Purpose**: authenticated image loader wrapping `cached_network_image`.
- **API**: `{required String url, BoxFit? fit, placeholder, errorWidget, double? width, double? height, BaseCacheManager? cacheManager}`.
- **Behavior**: resolves via `ApiService.resolveProtectedMediaUrl(url) ?? url` (line 29) and fetches with `httpHeaders: ApiService.authHeaders` (line 33) and a `BaseCacheManager` (typically `MediaCacheManager()`). Defaults: centered `CircularProgressIndicator` placeholder; `Icons.broken_image` 64px error.
- **Auth**: YES - requires a live Supabase session token in headers.
- **NET**: yes; caching controlled by passed manager.
- **Deps**: `cached_network_image`, `flutter_cache_manager`, `ApiService`.
- **Location note**: coupled to `ApiService`, so it was **relocated out of the DS** to `lib/shared/widgets/` in todo 6.2 (F-DS12) and removed from the `design_system.dart` barrel. It is intent-coupled (`ApiService`), not a generic DS asset.
- **Usage**: `VPAvatar` (via `MediaCacheManager`); direct use 4 refs.

### VPSheet - `shared/design_system/vp_sheet.dart`

- **Purpose**: shared frosted bottom-sheet container (drag handle + optional title + children).
- **API**: `{String? title, required List<Widget> children, double? maxHeightFactor}`.
- **Behavior**: the sheet's column shrink-wraps its content (`mainAxisSize: min`), so a sheet without flexible children (drive media picker, drive reaction picker) is docked to the bottom of the screen instead of stretching to the top; `surface` fill, `AppRadius.sheet` top radius, `accentPurple` shadow; padding `fromLTRB(24, 16, 24, viewInsets.bottom + 24)`; draggable handle in `track`; inside a single `Column(crossAxisAlignment: stretch)`; shadow is drawn **only** on the outer `DecoratedBox` - the inner `Material` carries the fill so a shadowed rounded edge is not clipped into a hard line.
- **`maxHeightFactor`** (0..1 of the screen height) is applied as a `BoxConstraints(maxHeight:)` around the `Material`, so a sheet that does want a tall layout (the emoji picker passes `0.85`) caps the space available to its one flexible child. It is a cap, not a fixed height: the sheet still shrink-wraps when the content is shorter.
- **Why it owns a `Material`**: without one, `ListTile` tap/hover ink and the media-picker background have no ancestor `Material` to draw on, which trips the `ListTile background color or ink splashes may be invisible.` assertion at runtime (F-DS15 follow-up; the media picker and drive reaction picker both rely on it).
- **Why `children` (list) and not `child`**: consumers must be able to put flex children (e.g. `Expanded`) as **direct** children of the sheet column. Nesting the content in an extra `Column` makes the modal route's intrinsic-height probe hit an `Expanded` under unbounded height -> `RenderFlex` assertion + infinite semantic-refresh loop. Keep flex children flat.
- **Usage**: emoji picker (mood), `MediaPickerService.showPickerSheet`, drive reaction picker.

---

## Usage map

| Component | Active call sites | Barely used / dead |
|---|---|---|
| VpWidgets helpers | 69 refs | - |
| VPSettingGroup / VPSettingTile / VPDivider | profile only | - |
| VPAvatar | profile, partner, VPUserAvatar, game history (24px) | - |
| VPUserAvatar | game screen only | - |
| VPButton | login, register, change-password, partner-invite | - |
| VPTextField | auth + partner-invite, bucket add dialog, emoji picker | - |
| VPHeader | 9 screens | - |
| VPCard | 3 files | underused (most screens use raw Container) |
| VPScaffold | 9 screens | bypassed by 4 screens (splash, drive, drive item, auth) |
| VPSectionHeader | 4 files | - |
| VPSegmentedControl | 0 call sites | dead component |
| VPDialog | 11 files (sole `AlertDialog` constructor) | - |
| VPAuthLayout / VPAuthLink | login + register | - |
| VPCircleButton | drive back button + drive media action controls | - |
| VPFilterChip | drive | - |
| InvitationTile | partner invitations + cancellation request card | - |
| VPSheet | emoji picker, media picker service, drive reactions | - |
| ErrorDialog | via DialogUtils/ErrorHandler | - |
| ProtectedNetworkImage (relocated to shared/widgets) | via VPAvatar | - |

---

## Findings

*No active findings.*

## Implementation status

| Area | Status |
|---|---|
| Central tokens (`AppPalette` + `AppRadius` + `AppDims`) | IMPLEMENTED (radius/dims adopted; a few one-off `SizedBox` gaps still inline) |
| Central theme (`AppTheme` dark/light) | IMPLEMENTED |
| Button system | IMPLEMENTED (`AppButtonStyle` shared by `FilledButtonThemeData` + `VPButton`; feature `ElevatedButton`s migrated) |
| Branded core components (inputs, buttons, cards, dialogs, layout) | IMPLEMENTED |
| Unified avatar component | IMPLEMENTED (`VPAvatar` + `VPUserAvatar`) |
| Unified loading component | IMPLEMENTED (inline in `VPButton`) |
| Unified dialog component | IMPLEMENTED (`VPDialog` is the only `AlertDialog` constructor; `ErrorDialog` builds on it) |
| Unified snackbar/toast | IMPLEMENTED (`ErrorHandler.showSnackBar`, root-overlay; `UIUtils`/ScaffoldMessenger path deleted; state-owned messages surfaced via `StateMessageListener`) |
| Accessibility (Semantics/Tooltip) | IMPLEMENTED for DS components + home nav + drive controls (no golden/a11y regression tests) |
| Localization inside DS | IMPLEMENTED (`AppLocalizations` for shared UI, emoji picker, media picker, home nav, drive actions) |
| Light-mode support | IMPLEMENTED (`AppPalette.light` theme extension + adaptive components) |
| Theme preference persistence | IMPLEMENTED (`ThemeProvider.storageKey`, restored pre-`runApp`, setting tile in ProfileScreen) |
| Homepage alignment to DS | IMPLEMENTED (`home*` palette tokens, theme font, `VPUserAvatar` avatars) |
| Dead component cleanup | DONE (VPLoadingButton, VPLoadingOverlay, VPMiniAvatar, PartnerUserTile, PartnerRequestTile, onlineIndicator are no longer part of the system; `VPSegmentedControl` is defined but unused) |
| Unified bottom sheet | IMPLEMENTED (`VPSheet` in 3 call sites) |
| Color/radius tokenization | IMPLEMENTED for colors (`app_palette.dart` is the only `Colors.*`/`Color(0x…)` site) and radii (`AppRadius`); spacing migration partial |

---

## Notes

- **Import policy**: all project code is consumed through `lib/all_imports.dart`; granular `package:justus/...` imports are forbidden. `test/import_hygiene_test.dart` enforces both directions (no granular imports; barrel present in every non-exempt file) and lists the legitimate exceptions: the barrel itself, the five `core/theme` token files, generated localization, `firebase_options.dart`, and pure-leaf files with no `lib/` dependency. Note that `Flutter/.gitignore` ignores `/test/`, so the guardrail runs locally through `flutter test` rather than in CI.
- `design_system.dart` barrel is re-exported by `all_imports.dart`; importing the app barrel already provides all DS components - no per-file imports needed.
- File naming is inconsistent: `vp_widgets.dart` hosts 13 components while peer components each live in their own file; `VpWidgets` (helper class) vs `VP*` (components) capitalization differs.
- Token adoption is mechanical: a raw `Colors.white70` is a tokenization bug, not a style choice. The only sanctioned non-token colors left in `lib/` are `Colors.transparent` (15 uses: gradient stops, transparent surfaces) and alpha modulation via `withValues(alpha:)` on an existing token; bucket category accents live in `core/theme/app_category_colors.dart` (`AppCategoryColors`).
- **Feedback/dialog single-sourcing**: `ErrorHandler.showSnackBar` is the only toast and `VPDialog` the only dialog; `test/feedback_system_test.dart` fails on any `UIUtils`/`ScaffoldMessenger.of` use and on any `AlertDialog(` outside `vp_widgets.dart`. The overlay is inserted on the root Navigator, so "show feedback after `Navigator.pop`" needs no messenger plumbing and no `await route.completed` Hero workaround — if the caller's context is already unmounted, `ErrorHandler` falls back to `navigatorKey.currentContext`.
- No golden/storybook tests exist for the DS; widget tests cover `VPSheet`, `InvitationTile` and the feedback invariants. A visual regression (spacing, radius, contrast) is still caught only by eye, so token changes need a manual pass over the affected screens.
- Bottom-sheet gotchas: pass flex children (e.g. `Expanded`) as **direct** `VPSheet(children: ...)` entries (never nested in an intermediate `Column`), and note that a sheet must paint its own `Material` - a transparent `DecoratedBox` leaves `ListTile` ink/hover invisible and trips "ListTile background color or ink splashes may be invisible." A sheet must also never let its column fill the available height: `showModalBottomSheet(isScrollControlled: true)` hands the child the full screen height, so without `mainAxisSize: min` every sheet opens full-screen (covered by `test/vp_sheet_test.dart`).
- Flutter 3.47.5 constraints worth remembering: there is no `Colors.white20` (use a token such as `context.palette.glass`) and `DialogThemeData` has no `actionTextStyle` (style actions with `TextButtonThemeData`).
