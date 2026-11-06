# Localization

ScriptDeck supports English (`en`) and Simplified Chinese (`zh-Hans`). Project documentation, bundled authoring guidance, and release notes use English.

## Language selection

The default follows the first system language. Chinese system variants use Simplified Chinese; unsupported languages fall back to English. **Settings → General → App Language** lets the user choose Follow System, English, or Simplified Chinese. Selection is stored as `appLanguage` in the app's preferences. An explicit selection also sets the app's `AppleLanguages` preference so native menus and dialogs use it on the next launch. Follow System removes that override.

Quit and reopen the app after changing the setting. Changing the preference does not terminate or restart tasks. The language remains consistent throughout the current app session. Dates and weekdays follow the active app language, while schedule time-zone rules remain unchanged.

## String resources

`Localization/en.lproj/Localizable.strings` and `Localization/zh-Hans.lproj/Localizable.strings` contain matching English keys. `L("Run")` looks up app-owned copy. Dynamic messages use numbered placeholders, for example `L("Exit code {0}", "\(code)")`. Preserve the exact placeholder set when translating. Replacements happen in one pass so braces in user values are preserved.

SwiftPM builds `ScriptDeck_ScriptDeck.bundle`; the build script embeds it in app resources. The installed scheduling helper receives its own copy so moving the app does not break lookups. Missing resources fall back to readable English keys rather than crashing. Add both translations for every new key.

Only app-owned text is localized. Script names, custom groups, option labels, parameter values, filenames, output, and existing log messages remain user data. The reserved ungrouped category keeps a stable internal identifier and localizes only its displayed name. Never use translated text as a persisted identifier or argument value.

## Validation

Self-checks validate both catalogs, placeholder parity, language fallback, interpolation safety, preference persistence, and stable grouping behavior. Existing process and navigation checks run using temporary fixtures. `SCRIPTDECK_LANGUAGE=en bash test.sh` runs them in English; the default test language is Simplified Chinese. This environment override also supports isolated UI inspection without changing the user's preferences.

When adding a language, extend `AppLanguage`, add the corresponding string table and bundle localization metadata, update helper resource installation, and verify native panels and layouts. Keep English as the fallback.
