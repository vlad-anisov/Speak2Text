# Dictate: push-to-talk диктовка (WhisperKit, локально)

Menu-bar приложение без иконки в Dock. Держишь Right Option, говоришь, отпускаешь, текст вставляется в активное приложение (буфер обмена сохраняется и восстанавливается через ~0.5 с).
Модель: whisper-large-v3-v20240930_turbo_632MB, `.all` (Neural Engine), язык ru, живое распознавание: каждую секунду перераспознаётся буфер, слова фиксируются по LocalAgreement-2.

## Сборка
    ~/dictation-bench/dictate-app/build.sh      # swift build -c release + Dictate.app + ad-hoc codesign

## Запуск
    open ~/dictation-bench/dictate-app/Dictate.app

Иконка в строке меню: микрофон = готов, микрофон красный + REC = запись, `...` = финализация, песочные часы = загрузка модели.
Первый старт после сборки ОЧЕНЬ долгий (до ~3 мин, компиляция CoreML-графов для ANE), дальше ~4 с. Пока висят песочные часы, хоткей не работает.
Меню: Open log, Quit.

## Разрешения (macOS спросит сам при первом запуске / первой диктовке)
1. Микрофон: запись голоса.
2. Универсальный доступ (Accessibility): отправка Cmd+V в другое приложение.
3. Мониторинг ввода (Input Monitoring): отслеживание Right Option (CGEventTap).
Включаются в Системные настройки > Конфиденциальность и безопасность. После выдачи Accessibility/Input Monitoring приложение перезапустить. Разрешения привязаны к бандлу (ad-hoc подпись); после каждого `build.sh` подпись меняется, и macOS может потребовать выдать их заново (удалить старую запись Dictate и добавить снова).

## Конфиг: config.json
`hotkey`: right_option (по умолчанию), left_option, right_command, left_command, right_control, left_control, right_shift, left_shift, fn. Также `model_folder`, `language`, `live_step_s`. Применяется после перезапуска.

## Лог
`logs/dictate.log`: строка на диктовку: длительность аудио, final_wait (отпускание -> текст вставлен), длина текста, текст.

## Тест без микрофона
    .build/release/dictate --file <wav>     # подаёт wav в реальном времени кусками по 100 мс, печатает текст и final wait

## Конфликт со Spokenly
Если Spokenly использует ту же клавишу (Right Option), обе программы сработают одновременно. Поменяй хоткей в одной из них или закрой Spokenly.

## Автозапуск
LaunchAgent `~/Library/LaunchAgents/local.vlad.dictate.plist` (RunAtLoad, `open Dictate.app`), без KeepAlive — Quit из меню не перезапускает.
Отключить: `launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/local.vlad.dictate.plist` и удалить plist.
Подпись — Apple Development (build.sh), разрешения переживают пересборку.
