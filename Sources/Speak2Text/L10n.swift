import Foundation

/// UI strings are keyed by their English text; Russian is looked up when the system language is Russian
/// (or `--lang ru` is passed, used for the Russian screenshots).
let isRussian: Bool = {
    let a = CommandLine.arguments
    if let i = a.firstIndex(of: "--lang"), i + 1 < a.count { return a[i + 1] == "ru" }
    return (Locale.preferredLanguages.first ?? "en").hasPrefix("ru")
}()

func L(_ en: String) -> String {
    isRussian ? (russian[en] ?? en) : en
}

private let russian: [String: String] = [
    // menu bar
    "Settings…": "Настройки…",
    "Quit": "Выход",
    // tabs
    "General": "Основные",
    "Model": "Модель",
    "Dictionary": "Словарь",
    "History": "История",
    "Permissions": "Разрешения",
    "About": "О программе",
    // general
    "Hotkey": "Клавиша",
    "Press a key…": "Нажмите клавишу…",
    "Click to change. Esc cancels.": "Нажмите, чтобы изменить. Esc — отмена.",
    "Reset to default": "Вернуть по умолчанию",
    "This key will no longer type its character while Speak2Text runs. Prefer F13, a modifier or a combination.": "Эта клавиша перестанет печатать свой символ, пока работает Speak2Text. Лучше F13, модификатор или сочетание.",
    "Mode": "Режим",
    "Hold to talk": "Удерживать",
    "Press to start/stop": "Нажать — старт, ещё раз — стоп",
    "Hold the key while you speak, release it to insert the text.": "Держите клавишу, пока говорите; отпустите — текст вставится.",
    "Press once to start, again to stop and insert the text. Esc cancels the recording.": "Нажмите, чтобы начать, ещё раз — чтобы остановить и вставить текст. Esc отменяет запись.",
    "Language": "Язык",
    "Auto-detect": "Автоопределение",
    "Mute other sounds while recording": "Заглушать другие звуки при записи",
    "Start and stop sounds": "Звуки старта и стопа",
    "Show overlay while recording": "Показывать плашку при записи",
    "Launch at login": "Запускать при входе",
    "Quit Speak2Text": "Выйти из Speak2Text",
    // model
    "Model is not downloaded": "Модель не скачана",
    "Preparing model…": "Подготовка модели…",
    "Accelerator": "Ускоритель",
    "Changing the accelerator recompiles CoreML: the first load can take up to about 3 minutes. Do not quit the app meanwhile.": "Смена ускорителя перекомпилирует CoreML: первая загрузка занимает до ~3 минут. Не закрывайте приложение.",
    "Downloaded": "Скачана",
    "Download": "Скачать",
    "Ready": "Готово",
    "Ready (loaded in %.1f s)": "Готово (загрузка %.1f с)",
    // dictionary
    "Fix words the model gets wrong and cut filler words. Applied to every dictation before the text is inserted.": "Исправляйте слова, которые модель путает, и убирайте слова-паразиты. Применяется к каждой диктовке перед вставкой текста.",
    "Replacements": "Замены",
    "Applied to the final text, ignoring case, on whole words only.": "Применяются к итоговому тексту, без учёта регистра, только к целым словам.",
    "Heard": "Услышано",
    "Write": "Написать",
    "Add": "Добавить",
    "Filler words": "Слова-паразиты",
    "Remove filler words": "Удалять слова-паразиты",
    "Separated by commas. Removed together with the commas around them.": "Через запятую. Удаляются вместе с запятыми рядом.",
    // history
    "Search": "Поиск",
    "No dictations yet": "Диктовок пока нет",
    "Nothing found": "Ничего не найдено",
    "No text recognized": "Текст не распознан",
    "Raw: ": "Исходный: ",
    "Copy text": "Скопировать текст",
    "Play / stop audio": "Воспроизвести / остановить",
    "Paste again": "Вставить снова",
    "Re-transcribe": "Распознать заново",
    "Show in Finder": "Показать в Finder",
    "Delete": "Удалить",
    "Save history": "Сохранять историю",
    "Keep": "Хранить",
    "Forever": "Всегда",
    "30 days": "30 дней",
    "7 days": "7 дней",
    "1 day": "1 день",
    "Clear history": "Очистить историю",
    "Clear the whole history?": "Очистить всю историю?",
    "All saved texts and recordings will be deleted. This cannot be undone.": "Все сохранённые тексты и записи будут удалены. Это нельзя отменить.",
    "Cancel": "Отмена",
    "Clear": "Очистить",
    // permissions
    "Speak2Text needs three permissions": "Speak2Text нужны три разрешения",
    "Microphone": "Микрофон",
    "Input Monitoring": "Мониторинг ввода",
    "Accessibility": "Универсальный доступ",
    "to record your voice": "чтобы записывать голос",
    "to see the hotkey": "чтобы видеть горячую клавишу",
    "to paste the text with Cmd+V": "чтобы вставлять текст через Cmd+V",
    "Speak2Text is not in the Input Monitoring list? Quit System Settings (⌘Q) and press the button again.": "Speak2Text нет в списке «Мониторинг ввода»? Закройте Системные настройки (⌘Q) и нажмите кнопку ещё раз.",
    "If the app is already in the list, remove it with the − button and add it again.": "Если приложение уже в списке, удалите его кнопкой − и добавьте снова.",
    "Granted but still showing ✗? The app must be restarted.": "Выдали, но всё ещё ✗? Приложение нужно перезапустить.",
    "Restart": "Перезапустить",
    "All set. You can close this window.": "Всё готово. Окно можно закрыть.",
    "Open Settings": "Открыть настройки",
    // about
    "Version %@": "Версия %@",
    "Local push-to-talk dictation. Nothing leaves your Mac.": "Локальная диктовка по клавише. Ничего не уходит с Mac.",
    "Check for Updates…": "Проверить обновления…",
    "Open Log": "Открыть лог",
]
