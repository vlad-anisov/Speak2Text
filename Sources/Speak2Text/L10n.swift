import Foundation

/// UI strings are keyed by their English text; Russian is looked up when the system language is Russian
/// (or `--lang ru` is passed, used for the Russian screenshots).
let isRussian: Bool = {
    let a = CommandLine.arguments
    if let i = a.firstIndex(of: "--lang"), i + 1 < a.count { return a[i + 1] == "ru" }
    return (systemLanguages().first ?? "en").hasPrefix("ru")
}()

func L(_ en: String) -> String {
    isRussian ? (russian[en] ?? en) : en
}

private let russian: [String: String] = [
    // menu bar
    "Settings": "Настройки",
    "Hold": "Удерживать",
    "Press": "Нажать",
    "Same as system": "Как в системе",
    "Permissions needed": "Нужны разрешения",
    "Downloading": "Загрузка",
    "Preparing…": "Подготовка…",
    "Retry": "Повторить",
    "Undo": "Отменить", "Cut": "Вырезать", "Paste": "Вставить", "Select All": "Выбрать всё", "Edit": "Правка",
    "Quit": "Закрыть",
    // tabs
    "General": "Основные",
    "History": "История",
    "About": "О программе",
    // general
    "Hotkey": "Клавиша",
    "Press a key…": "Нажмите клавишу…",
    "Click to change. Esc cancels.": "Нажмите, чтобы изменить. Esc — отмена.",
    "Reset to default": "Вернуть по умолчанию",
    "This key will no longer type its character while Speak2Text runs. Prefer F13, a modifier or a combination.": "Эта клавиша перестанет печатать свой символ, пока работает Speak2Text. Лучше F13, модификатор или сочетание.",
    "Right": "Правый", "Left": "Левый",
    "Mode": "Режим",
    "Language": "Язык",
    "Auto-detect": "Автоопределение",
    "Mute other sounds while recording": "Заглушать другие звуки при записи",
    "Sound": "Звук",
    "None": "Без звука",
    "Two notes": "Две ноты", "Pluck": "Щипок", "Marimba": "Маримба", "Glass": "Стекло", "Wood": "Дерево",
    "Chime": "Колокольчик", "Pop": "Пузырёк", "Breath": "Дыхание", "Bell": "Звон", "Tick": "Тик",
    "Show overlay while recording": "Показывать плашку при записи",
    "Launch at login": "Запускать при входе",
    // model
    "Accelerator": "Ускоритель",
    "Ready": "Готово",
    // dictionary
    "Remove filler words": "Убирать слова-паразиты",
    // history
    "Search": "Поиск",
    "No dictations yet": "Диктовок пока нет",
    "Nothing found": "Ничего не найдено",
    "No text recognized": "Текст не распознан",
    "Raw: ": "Исходный: ",
    "Copy": "Копировать",
    "Play": "Прослушать",
    "Stop": "Стоп",
    "Re-transcribe": "Распознать заново",
    "Transcribing…": "Распознаю…",
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
    "Open Settings": "Открыть настройки",
    // about
    "Version %@": "Версия %@",
    "Local push-to-talk dictation. Nothing leaves your Mac.": "Локальная диктовка по клавише. Ничего не уходит с Mac.",
    "Check for Updates…": "Проверить обновления…",
    "Open Log": "Открыть лог",
]
