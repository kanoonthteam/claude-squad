---
name: flutter-ui
description: Flutter UI patterns with widget composition, theming with AppColors and Material 3, reusable widgets (PrimaryButton, AppCard, feedback widgets), screen patterns with ConsumerStatefulWidget, and modal/toast patterns for ironmove-app
---

# Flutter UI & Widget Patterns

UI patterns used in ironmove-app. Covers the theme system with AppColors and Google Fonts (Noto Sans Thai), screen patterns using ConsumerStatefulWidget with WidgetsBindingObserver, reusable shared widgets, state display widgets (loading, error, empty), modal bottom sheets, and toast notifications.

## Table of Contents

1. [Theme System](#theme-system)
2. [Screen Pattern](#screen-pattern)
3. [Reusable Widgets](#reusable-widgets)
4. [Feedback Widgets](#feedback-widgets)
5. [Widget Organization](#widget-organization)
6. [Modal Patterns](#modal-patterns)
7. [Toast Notifications](#toast-notifications)
8. [State Handling in Screens](#state-handling-in-screens)
9. [Best Practices](#best-practices)
10. [Anti-Patterns](#anti-patterns)

---

## Theme System

### AppColors Constants

All colors are defined as static constants in `AppColors`. Never hardcode hex values in widgets.

```dart
// lib/core/theme.dart
class AppColors {
  static const Color primary = Color(0xFF6366F6);
  static const Color text = Color(0xFF212933);
  static const Color background = Color(0xFFF2F3F6);
  static const Color card = Color(0xFFFFFFFF);
  static const Color panel = Color(0xFFFFFFFF);
  static const Color authPageBackground = Color(0xFFFFFFFF);

  // Semantic colors
  static const Color error = Color(0xFFEF4444);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF3B82F6);

  // Text hierarchy
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFF9CA3AF);

  // Borders
  static const Color border = Color(0xFFE5E7EB);
  static const Color divider = Color(0xFFF3F4F6);
}
```

### AppTheme with Material 3

Single light theme using Material 3, Google Fonts Noto Sans Thai, and AppColors throughout.

```dart
// lib/core/theme.dart
class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: AppColors.background,
      cardColor: AppColors.card,

      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.primary,
        surface: AppColors.card,
        error: AppColors.error,
        onPrimary: Colors.white,
        onSurface: AppColors.text,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.text,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.notoSansThai(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
        ),
      ),

      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: GoogleFonts.notoSansThai(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        hintStyle: GoogleFonts.notoSansThai(color: AppColors.textTertiary),
      ),

      textTheme: GoogleFonts.notoSansThaiTextTheme(
        const TextTheme(
          displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.text),
          headlineLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.text),
          titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: AppColors.text),
          bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.normal, color: AppColors.text),
          bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.normal, color: AppColors.text),
          bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: AppColors.textSecondary),
          labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.text),
        ),
      ),
    );
  }
}
```

---

## Screen Pattern

Screens use `ConsumerStatefulWidget` with `WidgetsBindingObserver` for lifecycle management. Data fetches on init and on app resume.

```dart
// lib/screens/tasks/task_list_screen.dart
class TaskListScreen extends ConsumerStatefulWidget {
  const TaskListScreen({super.key});

  @override
  ConsumerState<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends ConsumerState<TaskListScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Fetch data when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshTasks();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshTasks();  // Re-fetch on app resume
    }
  }

  void _refreshTasks() {
    if (mounted) {
      ref.read(tasksProvider.notifier).fetchTasks();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasksState = ref.watch(tasksProvider);
    final tasks = tasksState.tasks;
    final isLoading = tasksState.isLoading;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(color: Colors.white),
              child: Row(
                children: [
                  Text(
                    context.l10n.taskQueue,
                    style: GoogleFonts.notoSansThai(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ),
            ),

            // Content with state handling
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : tasks.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: () async {
                            await ref.read(tasksProvider.notifier).fetchTasks();
                          },
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: tasks.length,
                            itemBuilder: (context, index) {
                              return _buildTaskCard(task: tasks[index]);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
```

### Detail Screen Pattern

```dart
// lib/screens/tasks/task_details_screen.dart
class TaskDetailsScreen extends ConsumerStatefulWidget {
  final String taskId;

  const TaskDetailsScreen({super.key, required this.taskId});

  @override
  ConsumerState<TaskDetailsScreen> createState() => _TaskDetailsScreenState();
}

class _TaskDetailsScreenState extends ConsumerState<TaskDetailsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(tasksProvider.notifier).fetchTaskDetails(widget.taskId);
    });
  }

  Future<void> _refresh() async {
    await ref.read(tasksProvider.notifier).fetchTaskDetails(widget.taskId);
  }

  @override
  Widget build(BuildContext context) {
    final tasksState = ref.watch(tasksProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header with back button
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(color: Colors.white),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => context.pop(),
                    child: const Icon(Icons.chevron_left, size: 24, color: AppColors.text),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.l10n.taskDetailsTitle,
                    style: GoogleFonts.notoSansThai(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ),
            ),

            // Content with RefreshIndicator
            Expanded(
              child: tasksState.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildTaskInfoCard(task),
                            const SizedBox(height: 8),
                            _buildLocationsSection(task),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
      // Status-dependent bottom action bar
      bottomNavigationBar: _buildBottomActionBar(task),
    );
  }
}
```

---

## Reusable Widgets

### PrimaryButton

Supports filled/outlined types, loading state, icons, and width control.

```dart
// lib/widgets/shared/buttons/primary_button.dart
enum PrimaryButtonType { filled, outlined }

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isEnabled;
  final double height;
  final double fontSize;
  final IconData? icon;
  final PrimaryButtonType type;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool expandWidth;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.isEnabled = true,
    this.height = 48,
    this.fontSize = 16,
    this.icon,
    this.type = PrimaryButtonType.filled,
    this.backgroundColor,
    this.foregroundColor,
    this.expandWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveOnPressed = isEnabled && !isLoading ? onPressed : null;

    // Show CircularProgressIndicator when loading, icon when provided, empty otherwise
    final Widget iconWidget = isLoading
        ? SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, ...),
          )
        : icon != null
            ? Icon(icon, size: 20)
            : const SizedBox.shrink();

    final Widget button = type == PrimaryButtonType.filled
        ? FilledButton.icon(onPressed: effectiveOnPressed, icon: iconWidget, label: labelWidget)
        : OutlinedButton.icon(onPressed: effectiveOnPressed, icon: iconWidget, label: labelWidget);

    if (expandWidth) {
      return SizedBox(width: double.infinity, height: height, child: button);
    }
    return SizedBox(height: height, child: button);
  }
}
```

Usage patterns:

```dart
// Full-width filled (default)
PrimaryButton(label: 'Start Task', onPressed: () => _startTask())

// Outlined variant
PrimaryButton(
  label: 'Logout',
  onPressed: () => _showLogoutConfirmation(context),
  type: PrimaryButtonType.outlined,
  backgroundColor: AppColors.error,
)

// With loading state
PrimaryButton(
  label: 'Sending...',
  onPressed: () => _submit(),
  isLoading: _isSubmitting,
)

// Compact with icon
PrimaryButton(
  label: 'Retry',
  onPressed: onRetry,
  icon: Icons.refresh,
  height: 40,
  fontSize: 14,
  expandWidth: false,
)
```

### AppCard

Container with white background, rounded corners, and subtle shadow.

```dart
// lib/widgets/shared/cards/app_card.dart
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Color? backgroundColor;
  final List<BoxShadow>? boxShadow;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius = 8,
    this.backgroundColor = Colors.white,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: boxShadow ?? [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}
```

---

## Feedback Widgets

### ErrorDisplay

Supports both inline and full-screen error states with optional retry.

```dart
// lib/widgets/shared/feedback/error_display.dart
class ErrorDisplay extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final bool isFullScreen;
  final IconData? icon;

  const ErrorDisplay({
    super.key,
    required this.message,
    this.onRetry,
    this.isFullScreen = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isFullScreen) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon ?? Icons.error_outline, size: 64,
                color: theme.colorScheme.error.withValues(alpha: 0.7)),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium),
              if (onRetry != null) ...[
                const SizedBox(height: 24),
                SizedBox(
                  width: 140,
                  child: PrimaryButton(
                    label: 'Retry', onPressed: onRetry,
                    icon: Icons.refresh, height: 40, fontSize: 14,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Inline error display
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon ?? Icons.error_outline, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
          if (onRetry != null)
            IconButton(onPressed: onRetry, icon: const Icon(Icons.refresh)),
        ],
      ),
    );
  }
}
```

### LoadingIndicator

Optional message text, supports both inline and full-screen modes.

```dart
// lib/widgets/shared/feedback/loading_display.dart
class LoadingIndicator extends StatelessWidget {
  final String? message;
  final bool fullScreen;

  const LoadingIndicator({super.key, this.message, this.fullScreen = false});

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
        ),
        if (message != null) ...[
          const SizedBox(height: 16),
          Text(message!, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
        ],
      ],
    );

    if (fullScreen) {
      return Scaffold(backgroundColor: AppColors.background, body: Center(child: content));
    }
    return Center(child: content);
  }
}

// Loading overlay for blocking UI during async operations
class LoadingOverlay extends StatelessWidget {
  final Widget child;
  final bool isLoading;
  final String? message;

  const LoadingOverlay({super.key, required this.child, required this.isLoading, this.message});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Container(
            color: Colors.black.withValues(alpha: 0.3),
            child: LoadingIndicator(message: message),
          ),
      ],
    );
  }
}
```

### EmptyState

Icon, title, optional subtitle, and optional action widget.

```dart
// lib/widgets/shared/feedback/empty_display.dart
class EmptyState extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 80,
              color: AppColors.textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.text, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!,
                style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                textAlign: TextAlign.center),
            ],
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
```

---

## Widget Organization

```
lib/widgets/
  shared/                          # Reusable across all features
    buttons/
      primary_button.dart          # PrimaryButton (filled/outlined + loading)
      slide_action_button.dart     # Swipe-to-confirm button
    cards/
      app_card.dart                # Standard card container
    feedback/
      custom_toast.dart            # Animated overlay toast
      empty_display.dart           # EmptyState widget
      error_display.dart           # ErrorDisplay (inline + fullscreen)
      loading_display.dart         # LoadingIndicator + LoadingOverlay
    progress/
      animated_location_progress.dart
      location_progress_bar.dart
  tasks/                           # Task-feature-specific widgets
    task_card.dart
  expenses/                        # Expense-feature-specific widgets
    expense_card.dart
  location/                        # Location-feature-specific widgets
    tracking_indicator.dart
```

Convention: `widgets/shared/` for cross-feature reusable widgets, `widgets/<feature>/` for feature-specific widgets that are extracted from screens but only used in that feature.

---

## Modal Patterns

### Confirmation Bottom Sheet

Used for destructive actions (logout, start task). Returns `bool` via `Navigator.pop`.

```dart
// lib/screens/tasks/task_list_screen.dart
Future<void> _showLogoutConfirmation(BuildContext context) async {
  final l10n = context.l10n;

  final confirm = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (modalContext) => Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title + message
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 16, left: 16, right: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(modalContext.l10n.logoutConfirmTitle,
                    style: GoogleFonts.notoSansThai(
                      fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(modalContext.l10n.logoutConfirmMessage,
                    style: GoogleFonts.notoSansThai(
                      fontSize: 14, color: const Color(0xFF62697B))),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Action buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(modalContext).pop(false),
                      child: Text(modalContext.l10n.cancelButton),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PrimaryButton(
                      label: modalContext.l10n.logout,
                      onPressed: () => Navigator.of(modalContext).pop(true),
                      backgroundColor: AppColors.error,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ),
  );

  if (confirm == true && mounted) {
    await ref.read(authProvider.notifier).logout();
    if (mounted) context.go('/login');
  }
}
```

### StatefulBuilder in Bottom Sheet

For modals that need local state (e.g., loading during async action):

```dart
showModalBottomSheet(
  context: context,
  builder: (BuildContext context) {
    bool isLoading = false;
    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setModalState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 32, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(context.l10n.readyToStartTitle, ...),
            Row(
              children: [
                Expanded(
                  child: PrimaryButton(
                    label: context.l10n.notReadyButton,
                    onPressed: () => Navigator.of(context).pop(),
                    isEnabled: !isLoading,
                    type: PrimaryButtonType.outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PrimaryButton(
                    label: context.l10n.readyButton,
                    onPressed: () async {
                      setModalState(() => isLoading = true);
                      try {
                        await ref.read(tasksProvider.notifier).startTask(task.id);
                        Navigator.of(context).pop();
                        context.go('/tasks/${task.id}/ongoing');
                      } catch (e) {
                        setModalState(() => isLoading = false);
                        Navigator.of(context).pop();
                        CustomToast.show(
                          context: context,
                          message: 'Error: ${e.toString()}',
                          type: ToastType.error,
                        );
                      }
                    },
                    isEnabled: !isLoading,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  },
);
```

---

## Toast Notifications

Animated overlay toast with slide-up + fade animation. Auto-dismisses after 3 seconds.

```dart
// lib/widgets/shared/feedback/custom_toast.dart
enum ToastType { success, error, warning, info }

class CustomToast {
  static void show({
    required BuildContext context,
    required String message,
    ToastType type = ToastType.success,
    IconData? icon,
  }) {
    final overlay = Overlay.of(context);
    final overlayEntry = OverlayEntry(
      builder: (context) => _ToastWidget(
        message: message, type: type, icon: icon,
      ),
    );

    overlay.insert(overlayEntry);
    Future.delayed(const Duration(seconds: 3), () {
      overlayEntry.remove();
    });
  }
}
```

Usage:

```dart
// Success toast
CustomToast.show(
  context: context,
  message: l10n.logoutSuccess,
  type: ToastType.success,
);

// Error toast
CustomToast.show(
  context: context,
  message: 'Error: ${e.toString()}',
  type: ToastType.error,
);
```

Toast positions above keyboard when visible, otherwise 128px from bottom.

---

## State Handling in Screens

Every list screen handles all four states explicitly: loading, error, empty, data.

```dart
// Pattern used in TaskListScreen
Expanded(
  child: isLoading
      ? const Center(child: CircularProgressIndicator())
      : tasksState.error != null
          ? ErrorDisplay(
              message: tasksState.error!,
              onRetry: _refreshTasks,
              isFullScreen: true,
            )
          : tasks.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: () async {
                    await ref.read(tasksProvider.notifier).fetchTasks();
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: tasks.length,
                    itemBuilder: (context, index) => _buildTaskCard(tasks[index]),
                  ),
                ),
)

// Empty state inline (when not using EmptyState widget)
Widget _buildEmptyState() {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.assignment_outlined, size: 64, color: AppColors.textTertiary),
        const SizedBox(height: 16),
        Text(context.l10n.noTasks,
          style: GoogleFonts.notoSansThai(
            fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text)),
        const SizedBox(height: 8),
        Text('New tasks will appear here',
          style: GoogleFonts.notoSansThai(
            fontSize: 14, color: AppColors.textSecondary)),
      ],
    ),
  );
}
```

---

## Best Practices

1. **Always use AppColors constants** -- never hardcode hex color values in widgets
2. **Use GoogleFonts.notoSansThai** for all text styles -- consistent Thai typography
3. **Use ConsumerStatefulWidget + WidgetsBindingObserver** for screens that fetch data
4. **Handle all states explicitly**: loading, error, empty, data -- never leave a state unhandled
5. **Wrap list screens with RefreshIndicator** for pull-to-refresh
6. **Use showModalBottomSheet for confirmations** -- not AlertDialog
7. **Use StatefulBuilder inside bottom sheets** for local state (loading spinners)
8. **Check `mounted` after every async gap** before using context or setState
9. **Use `WidgetsBinding.instance.addPostFrameCallback`** for initial data fetch in initState
10. **Use `context.l10n`** extension for all user-facing strings -- never hardcode Thai text in widgets

---

## Anti-Patterns

- **Hardcoding colors** instead of using AppColors constants (breaks theme consistency)
- **Not handling loading/error/empty states** in screens (only showing data state)
- **Using AlertDialog** instead of showModalBottomSheet for confirmations (app uses bottom sheets)
- **Using context after async gaps** without checking `mounted` first (causes crashes)
- **Creating new TextStyle objects** in build instead of using `GoogleFonts.notoSansThai()` or theme (inconsistent typography)
- **Nesting Scaffold widgets** unnecessarily (causes layout issues)
- **Not adding WidgetsBindingObserver** on screens that fetch data (stale data on app resume)
- **Not wrapping list content in RefreshIndicator** (users can't pull to refresh)
- **Putting feature-specific widgets in `widgets/shared/`** (shared is for cross-feature only)
- **Not using SafeArea** in bottom sheets (content can be hidden behind system UI)
