import Foundation

/// UI strings are keyed by their English text; Russian is looked up when the system language is Russian.
let isRussian: Bool = (Locale.preferredLanguages.first ?? "en").hasPrefix("ru")

func L(_ en: String) -> String {
    isRussian ? (russian[en] ?? en) : en
}

private let russian: [String: String] = [
    // menu
    "Status: ": "Статус: ",
    "Loading model…": "Загрузка модели…",
    "Preparing model…": "Подготовка модели…",
    "Ready": "Готово",
    "Recording…": "Запись…",
    "Recognizing…": "Распознавание…",
    "Model failed to load": "Не удалось загрузить модель",
    "Model is not downloaded": "Модель не скачана",
    "Settings…": "Настройки…",
    "Permissions…": "Разрешения…",
    "Check for Updates…": "Проверить обновления…",
    "Open Log": "Открыть лог",
    "Quit": "Выход",
    "Missing permissions: ": "Нет доступа: ",
    "Microphone": "Микрофон",
    "Input Monitoring": "Мониторинг ввода",
    "Accessibility": "Универсальный доступ",
    "General": "Основные",
    "Hotkey": "Клавиша",
    "Press a key or combination…": "Нажмите клавишу или сочетание…",
    "Cancel": "Отмена",
    "Record": "Записать",
    "Reset": "Сбросить",
    "This key will no longer type its character while Speak2Text runs. Prefer F13, a modifier or a combination.": "Эта клавиша перестанет печатать свой символ, пока работает Speak2Text. Лучше F13, модификатор или сочетание.",
    "Mode": "Режим",
    "Hold to talk": "Удержание",
    "Press to start, press to stop": "Нажатие: старт и стоп",
    "Hold the key, speak, release: the text is inserted.": "Держите клавишу, говорите, отпустите: текст вставится.",
    "Esc cancels the recording.": "Esc отменяет запись.",
    "Language": "Язык",
    "Mute other sounds while recording": "Заглушать другие звуки при записи",
    "Volume while recording": "Громкость при записи",
    "Show overlay while recording": "Показывать плашку при записи",
    "Auto-detect": "Автоопределение",
]
