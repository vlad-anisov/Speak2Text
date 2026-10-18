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
]
