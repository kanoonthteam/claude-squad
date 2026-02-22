---
name: flutter-localization
description: Flutter skill — ARB-based localization, Flutter Localizations, locale switching, plurals, date/number formatting, and RTL support
---

# Flutter Localization & Internationalization

Localization patterns for the ironmove-app logistics driver application. Covers ARB-based localization with Flutter's built-in gen_l10n tooling, the `context.l10n` extension for type-safe access, Thai-first locale configuration, placeholder syntax for dynamic values, ExceptionMessages for user-friendly Thai error text, and the full 100+ key coverage across authentication, tasks, expenses, validation, and navigation screens.

## Table of Contents

1. [Setup and Configuration](#setup-and-configuration)
2. [ARB File Structure](#arb-file-structure)
3. [Key Categories](#key-categories)
4. [Placeholder Syntax](#placeholder-syntax)
5. [Context Extension](#context-extension)
6. [Thai-First Locale Setup](#thai-first-locale-setup)
7. [ExceptionMessages Class](#exceptionmessages-class)
8. [Generated Localizations Class](#generated-localizations-class)
9. [Best Practices](#best-practices)
10. [Anti-Patterns](#anti-patterns)

---

## Setup and Configuration

### l10n.yaml

The `l10n.yaml` file at the project root configures the Flutter gen_l10n code generation tool. In ironmove-app, this is minimal:

```yaml
# l10n.yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
```

Key settings:

- **arb-dir** -- Directory containing all ARB translation files (`lib/l10n/`).
- **template-arb-file** -- English is the template ARB file that defines the interface and placeholder metadata.
- **output-localization-file** -- The generated Dart file name for the abstract class and delegate.

### File Structure

```
lib/
├── l10n/
│   ├── app_en.arb                  # English (template, 100+ keys)
│   ├── app_th.arb                  # Thai (primary user-facing language)
│   ├── app_localizations.dart      # Generated abstract class + delegate
│   ├── app_localizations_en.dart   # Generated English implementation
│   └── app_localizations_th.dart   # Generated Thai implementation
├── core/
│   ├── extensions.dart             # LocalizationsX extension (context.l10n)
│   └── exceptions.dart             # ExceptionMessages Thai error mapper
└── main.dart                       # Locale delegates + Thai-first config
```

---

## ARB File Structure

### Template File (app_en.arb)

The English ARB file is the template. It defines every localization key, placeholder metadata, and serves as the source of truth for the generated Dart interface. The app has 100+ keys covering all user-facing strings.

```json
{
  "@@locale": "en",

  "welcomeTitle": "Welcome to Ironmove",
  "welcomeSubtitle": "Please verify your identity with phone number",
  "phoneNumberLabel": "Mobile Phone Number",
  "phoneNumberHint": "0812345678",
  "getOtpButton": "Get OTP",
  "loginButton": "Login",
  "otpSentTitle": "We've sent you a code",
  "otpInstruction": "Please enter the 6-digit code sent to",
  "verifyingOtp": "Verifying...",
  "resendOtp": "Resend Code",
  "resendOtpIn": "Resend code in {seconds} seconds",
  "@resendOtpIn": {
    "placeholders": {
      "seconds": {
        "type": "int"
      }
    }
  },

  "taskQueue": "Your Task Queue",
  "ongoingTaskPrefix": "Ongoing",
  "noTasks": "No assigned tasks",
  "noTasksMessage": "When there are new tasks, you'll see them here",

  "slideWhenArrived": "Slide when arrived",
  "slideToComplete": "Slide to complete",
  "viewTaskDetails": "View Task Details",
  "taskCompleteTitle": "Awesome! Task completed",
  "taskCompleteMessage": "Take a break before starting the next task",

  "expenseTotal": "Total ฿{amount}",
  "@expenseTotal": {
    "placeholders": {
      "amount": {
        "type": "String"
      }
    }
  },

  "willFinishWithin": "Will finish within {date} {period}",
  "@willFinishWithin": {
    "placeholders": {
      "date": { "type": "String" },
      "period": { "type": "String" }
    }
  },

  "imageLimit": "Maximum {count} images",
  "@imageLimit": {
    "placeholders": {
      "count": { "type": "int" }
    }
  },

  "fieldRequired": "{fieldName} is required",
  "@fieldRequired": {
    "placeholders": {
      "fieldName": { "type": "String" }
    }
  },

  "fieldMinLength": "{fieldName} must be at least {minLength} characters",
  "@fieldMinLength": {
    "placeholders": {
      "fieldName": { "type": "String" },
      "minLength": { "type": "int" }
    }
  },

  "fieldMaxLength": "{fieldName} must not exceed {maxLength} characters",
  "@fieldMaxLength": {
    "placeholders": {
      "fieldName": { "type": "String" },
      "maxLength": { "type": "int" }
    }
  }
}
```

### Thai Translation File (app_th.arb)

The Thai file mirrors every key from the template. Thai is the primary user-facing language. Placeholders use the same `{name}` syntax.

```json
{
  "@@locale": "th",

  "welcomeTitle": "ยินดีต้อนรับสู่ Ironmove",
  "welcomeSubtitle": "โปรดยืนยันตัวตนด้วยหมายเลขโทรศัพท์",
  "phoneNumberLabel": "หมายเลขโทรศัพท์มือถือ",
  "getOtpButton": "ขอรหัสผ่าน",
  "loginButton": "เข้าสู่ระบบ",
  "resendOtpIn": "ส่งรหัสอีกครั้งใน {seconds} วินาที",

  "taskQueue": "คิวงานของคุณ",
  "ongoingTaskPrefix": "กำลังทำ",
  "noTasks": "ไม่มีงานที่ได้รับมอบหมาย",
  "noTasksMessage": "เมื่อมีงานใหม่ คุณจะเห็นรายการที่นี่",

  "slideWhenArrived": "เลื่อนเมื่อถึงจุดหมาย",
  "slideToComplete": "เลื่อนเพื่อจบงาน",
  "viewTaskDetails": "ดูรายละเอียดคิวงาน",
  "taskCompleteTitle": "สุดยอด! คุณทำงานสำเร็จ",
  "taskCompleteMessage": "พักสักหน่อย แล้วค่อยเริ่มงานต่อไปนะ",

  "expenseTotal": "รวม ฿{amount}",
  "willFinishWithin": "จะจบงานภายใน {date} {period}",
  "imageLimit": "เพิ่มรูปได้สูงสุด {count} รูป",
  "fieldRequired": "กรุณากรอก{fieldName}",
  "fieldMinLength": "{fieldName}ต้องมีอย่างน้อย {minLength} ตัวอักษร",
  "fieldMaxLength": "{fieldName}ต้องไม่เกิน {maxLength} ตัวอักษร"
}
```

### Key Rules

- Every key in `app_en.arb` must also exist in `app_th.arb`.
- Placeholders use `{name}` syntax and must appear in all translations.
- The `@key` metadata entries (with `placeholders`) are only required in the template ARB file.
- The `@@locale` field identifies the locale for that file.

---

## Key Categories

The 100+ localization keys in ironmove-app are organized into these functional categories:

### Authentication (16 keys)
Login flow, OTP verification, phone validation:
`welcomeTitle`, `welcomeSubtitle`, `phoneNumberLabel`, `phoneNumberHint`, `getOtpButton`, `loginButton`, `otpSentTitle`, `otpInstruction`, `verifyingOtp`, `resendOtp`, `resendOtpIn`, `logout`, `logoutConfirmTitle`, `logoutConfirmMessage`, `logoutSuccess`, `otpSentSuccessfully`

### Task Management (18 keys)
Task queue, ongoing task, completion:
`taskQueue`, `ongoingTaskPrefix`, `continueButton`, `taskDetailsTitle`, `startTaskButton`, `readyToStartTitle`, `readyToStartMessage`, `notReadyButton`, `readyButton`, `noTasks`, `noTasksMessage`, `slideWhenArrived`, `slideToComplete`, `viewTaskDetails`, `viewDetails`, `taskCompleteTitle`, `taskCompleteMessage`, `backToHome`

### Expense Tracking (22 keys)
Recording, editing, deleting expenses with type labels:
`expenses`, `expense`, `recordExpense`, `deleteExpense`, `confirmDeleteExpense`, `deleteExpenseMessage`, `addExpense`, `editExpense`, `expenseTotal`, `expenseType`, `amount`, `note`, `allowanceSound`, `overnightPrice`, `fuelOil`, `depositFee`, `expressway`, `repairMaintenance`, `tireRubber`, `addPhoto`, `photos`, `baht`

### Validation (12 keys)
Form validation messages with parameterized fields:
`phoneNumberRequired`, `invalidThaiPhoneNumber`, `otpRequired`, `otpMustBe6Digits`, `amountRequired`, `invalidAmount`, `amountMustBePositive`, `amountTooLarge`, `fieldRequired`, `emailRequired`, `invalidEmail`, `fieldMinLength`, `fieldMaxLength`

### Network/API Errors (9 keys)
Connection and server error messages:
`connectionTimeout`, `noInternetConnection`, `unknownError`, `unauthorizedAccess`, `accessForbidden`, `resourceNotFound`, `serverError`, `requestCancelled`, `unexpectedError`

### Location/GPS (10 keys)
Map and navigation status messages:
`unknownLocation`, `arriving`, `navigating`, `pickupCompleted`, `deliveryCompleted`, `allTasksCompleted`, `routeError`, `locationPermissionDenied`, `locationServiceDisabled`, `gpsSignalLost`, `noGpsSignal`, `weakGpsSignal`, `searchingGps`, `locationAccuracyLow`, `backgroundLocationMessage`

### Logistics Domain (9 keys)
Vehicle, driver, scheduling:
`vehicle`, `driver`, `startDate`, `duration`, `halfDay`, `fullDay`, `willFinishWithin`, `morning`, `afternoon`, `evening`

### Common UI (12 keys)
Month abbreviations, buttons, general labels:
`save`, `delete`, `cancel`, `cancelButton`, `confirmButton`, `confirmDelete`, `tryAgain`, `retry`, `errorOccurred`, `monthJan` through `monthDec`

---

## Placeholder Syntax

The app uses several patterns for dynamic values in localized strings:

### Single Parameter (int)

```json
"resendOtpIn": "Resend code in {seconds} seconds",
"@resendOtpIn": {
  "placeholders": {
    "seconds": { "type": "int" }
  }
}
```

Generated method: `String resendOtpIn(int seconds)`

Usage: `context.l10n.resendOtpIn(30)` produces "Resend code in 30 seconds" / "ส่งรหัสอีกครั้งใน 30 วินาที"

### Single Parameter (String)

```json
"expenseTotal": "Total ฿{amount}",
"@expenseTotal": {
  "placeholders": {
    "amount": { "type": "String" }
  }
}
```

Generated method: `String expenseTotal(String amount)`

Usage: `context.l10n.expenseTotal('1,500')` produces "Total ฿1,500" / "รวม ฿1,500"

### Multiple Parameters

```json
"willFinishWithin": "Will finish within {date} {period}",
"@willFinishWithin": {
  "placeholders": {
    "date": { "type": "String" },
    "period": { "type": "String" }
  }
}
```

Generated method: `String willFinishWithin(String date, String period)`

Usage: `context.l10n.willFinishWithin('25 ก.พ.', context.l10n.morning)`

### Parameterized Validation

```json
"fieldMinLength": "{fieldName} must be at least {minLength} characters",
"@fieldMinLength": {
  "placeholders": {
    "fieldName": { "type": "String" },
    "minLength": { "type": "int" }
  }
}
```

Thai: `"{fieldName}ต้องมีอย่างน้อย {minLength} ตัวอักษร"` -- note no space before the field name in Thai, as Thai grammar connects differently.

---

## Context Extension

The `LocalizationsX` extension on `BuildContext` provides concise access to localized strings via `context.l10n`:

```dart
// lib/core/extensions.dart
import 'package:flutter/material.dart';
import 'package:ironmove_app/l10n/app_localizations.dart';

extension LocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}
```

### Usage in Widgets

```dart
// Using context.l10n throughout widget code
import 'package:ironmove_app/core/extensions.dart';

// Simple string access
Text(context.l10n.taskQueue)           // "คิวงานของคุณ"
Text(context.l10n.slideWhenArrived)    // "เลื่อนเมื่อถึงจุดหมาย"
Text(context.l10n.viewTaskDetails)     // "ดูรายละเอียดคิวงาน"

// Parameterized strings
Text(context.l10n.resendOtpIn(30))     // "ส่งรหัสอีกครั้งใน 30 วินาที"
Text(context.l10n.expenseTotal('500')) // "รวม ฿500"
Text(context.l10n.imageLimit(5))       // "เพิ่มรูปได้สูงสุด 5 รูป"

// Validation messages
context.l10n.fieldRequired('อีเมล')    // "กรุณากรอกอีเมล"
context.l10n.fieldMinLength('รหัสผ่าน', 8) // "รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร"
```

### Real Usage from OngoingTaskScreen

```dart
// lib/screens/tasks/ongoing_task_screen.dart
// Marker info window uses localized strings
InfoWindow(
  title: context.l10n.unknownLocation,
  snippet: context.l10n.defaultDriverName,
),

// Button labels
Text(context.l10n.viewTaskDetails),
Text(context.l10n.cancelButton),

// Navigation status
Text(context.l10n.slideWhenArrived),
Text(context.l10n.slideToComplete),
```

---

## Thai-First Locale Setup

Ironmove-app is configured with Thai as the default locale. English is a fallback. The locale configuration lives in `main.dart` inside the `MaterialApp.router`:

```dart
// lib/main.dart
return MaterialApp.router(
  title: 'Ironmove',
  theme: AppTheme.lightTheme,
  debugShowCheckedModeBanner: false,
  routerConfig: router,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: const [
    Locale('th', ''), // Thai (default)
    Locale('en', ''), // English
  ],
  locale: const Locale('th', ''), // Set Thai as default
);
```

Key points:

- **Thai is listed first** in `supportedLocales` and explicitly set as `locale`.
- **Four delegates are registered**: the app's own delegate plus the three global Material/Widgets/Cupertino delegates for system widgets (date pickers, dialogs, etc.).
- **No runtime locale switching** -- the app is hardcoded to Thai. English exists as a development/fallback reference.

---

## ExceptionMessages Class

The `ExceptionMessages` class maps exception types to user-friendly Thai messages. This centralizes error message translation in a single place rather than scattering translation logic across catch blocks.

```dart
// lib/core/exceptions.dart
class ExceptionMessages {
  static String getUserMessage(Exception exception) {
    if (exception is NetworkException) {
      if (exception.isNoConnection) {
        return 'ไม่สามารถเชื่อมต่ออินเทอร์เน็ต กรุณาตรวจสอบการเชื่อมต่อ';
      }
      if (exception.isTimeout) {
        return 'การเชื่อมต่อใช้เวลานานเกินไป กรุณาลองใหม่อีกครั้ง';
      }
      if (exception.isServerError) {
        return 'เซิร์ฟเวอร์ขัดข้อง กรุณาลองใหม่ภายหลัง';
      }
      if (exception.statusCode == 404) {
        return 'ไม่พบข้อมูลที่ต้องการ';
      }
      return 'เกิดข้อผิดพลาดในการเชื่อมต่อ กรุณาลองใหม่อีกครั้ง';
    }

    if (exception is AuthException) {
      if (exception.isSessionExpired) {
        return 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่';
      }
      if (exception.code == 'INVALID_OTP') {
        return 'รหัส OTP ไม่ถูกต้อง กรุณาตรวจสอบอีกครั้ง';
      }
      return 'ไม่สามารถยืนยันตัวตนได้ กรุณาลองใหม่อีกครั้ง';
    }

    if (exception is ValidationException) {
      return exception.message;
    }

    if (exception is ParseException) {
      return 'ข้อมูลไม่ถูกต้อง กรุณาลองใหม่อีกครั้ง';
    }

    return 'เกิดข้อผิดพลาดที่ไม่ทราบสาเหตุ';
  }
}
```

Exception type mapping:

| Exception Type | Condition | Thai Message |
|---|---|---|
| `NetworkException` | No connection | ไม่สามารถเชื่อมต่ออินเทอร์เน็ต กรุณาตรวจสอบการเชื่อมต่อ |
| `NetworkException` | Timeout | การเชื่อมต่อใช้เวลานานเกินไป กรุณาลองใหม่อีกครั้ง |
| `NetworkException` | Server error (5xx) | เซิร์ฟเวอร์ขัดข้อง กรุณาลองใหม่ภายหลัง |
| `NetworkException` | 404 | ไม่พบข้อมูลที่ต้องการ |
| `AuthException` | Session expired | เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่ |
| `AuthException` | Invalid OTP | รหัส OTP ไม่ถูกต้อง กรุณาตรวจสอบอีกครั้ง |
| `ValidationException` | Any | Uses the exception's own message |
| `ParseException` | Any | ข้อมูลไม่ถูกต้อง กรุณาลองใหม่อีกครั้ง |
| Fallback | Unknown | เกิดข้อผิดพลาดที่ไม่ทราบสาเหตุ |

Note: The ARB files also contain localized versions of these same error strings (e.g., `connectionTimeout`, `noInternetConnection`, `serverError`). The `ExceptionMessages` class is used for catch-block error handling where context may not be available, while the ARB keys are used in widgets that have a `BuildContext`.

---

## Generated Localizations Class

The generated `AppLocalizations` abstract class in `lib/l10n/app_localizations.dart` provides:

- **Static `delegate`** -- A `LocalizationsDelegate<AppLocalizations>` for registering with `MaterialApp`.
- **Static `localizationsDelegates`** -- A convenience list of all four required delegates.
- **Static `supportedLocales`** -- `[Locale('en'), Locale('th')]`.
- **`of(context)`** -- Returns `AppLocalizations?` from the widget tree.
- **String getters** for simple keys (e.g., `String get welcomeTitle`).
- **String methods** for parameterized keys (e.g., `String resendOtpIn(int seconds)`).

The delegate loads the correct locale implementation synchronously:

```dart
// Generated in app_localizations.dart
AppLocalizations lookupAppLocalizations(Locale locale) {
  switch (locale.languageCode) {
    case 'en': return AppLocalizationsEn();
    case 'th': return AppLocalizationsTh();
  }
  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale".',
  );
}
```

---

## Best Practices

1. **Always use `context.l10n.keyName`** via the `LocalizationsX` extension instead of calling `AppLocalizations.of(context)!` directly. The extension is shorter and enforces consistency.

2. **Never hardcode user-visible strings in Dart code.** Every string the user sees must come from an ARB file -- including error messages, button labels, tooltips, snackbar content, and info window titles.

3. **Keep Thai as the primary language.** The app's target users are Thai truck drivers. English keys serve as the template and developer reference only.

4. **Use ExceptionMessages for catch-block errors** where BuildContext may not be available. Use ARB keys via `context.l10n` in widgets that have a context.

5. **Add new keys to both ARB files simultaneously.** If you add a key to `app_en.arb`, add the Thai translation to `app_th.arb` in the same commit. Missing keys cause build failures.

6. **Use parameterized strings instead of string concatenation.** Write `context.l10n.resendOtpIn(seconds)` instead of `'ส่งรหัสอีกครั้งใน $seconds วินาที'`.

7. **Group related keys together in ARB files** with blank lines between groups. The app organizes keys by feature: auth, tasks, expenses, validation, errors, location.

8. **Thai month abbreviations are localized in ARB** (`monthJan` through `monthDec`) rather than relying on the `intl` package's Thai date formatting.

---

## Anti-Patterns

- **Hardcoding Thai strings in widgets** (e.g., `Text('เลื่อนเมื่อถึงต้นทาง')`) instead of using ARB keys. This makes it impossible to maintain translations and breaks the localization system.

- **Using `AppLocalizations.of(context)!` with the null assertion** instead of the `context.l10n` extension. The extension is the project convention and produces cleaner code.

- **Building messages with string interpolation** (`'ส่งรหัสอีกครั้งใน $seconds วินาที'`) instead of using parameterized ARB keys. Interpolated strings bypass the translation system.

- **Adding error messages directly in catch blocks** instead of using `ExceptionMessages.getUserMessage()`. Scattered Thai strings in error handlers are hard to find and maintain.

- **Forgetting to add new keys to app_th.arb** when adding them to `app_en.arb`. This causes a build failure from gen_l10n because the Thai translation file is incomplete.

- **Storing locale-specific formats (dates, currencies) as hardcoded strings** instead of using the month abbreviation keys or parameterized strings like `expenseTotal`.

- **Using separate string files per feature.** All translations live in a single pair of ARB files per locale. Splitting creates merge conflicts and makes key management harder.
