# Portable-VirtualBox · модернизация 2026 года

[English](README.md) · [Возможности](https://github.com/zlocorp/Portable-VirtualBox/blob/dev/modernization-2026/FEATURES.md) · [История изменений](https://github.com/zlocorp/Portable-VirtualBox/blob/dev/modernization-2026/CHANGELOG.md) · [Авторы](CREDITS.md)

Модернизация [vboxme/Portable-VirtualBox](https://github.com/vboxme/Portable-VirtualBox): двуязычная оболочка, проверяемые зависимости и переносимые пользовательские данные.

> **Предварительная диагностическая сборка, пока не готовый лаунчер ВМ.** Обычный интерфейс не запускает VirtualBox Manager и виртуальные машины и не устанавливает драйверы. Реальные эксперименты с драйвером и пустой ВМ выполняются только на одноразовых Windows-хостах CI. Приёмка Windows 11 с обычной учётной записью и UAC ещё впереди.

## Что изменилось относительно оригинала

**Новая русско-английская оболочка.** Язык можно переключить, явно сохранить кнопкой «Запомнить язык» и вернуть выбор по Windows. Настройка переживает перезапуск и перенос папки. Временный `--lang` её не перезаписывает. Диагностика копируется, причины отказа читаемы, окно «О программе» содержит краткую информацию о сборке.

**Без устаревших бинарников.** Из активного дерева удалены старые AutoIt, 7za, DevCon, SnetCfg, четырнадцать старых INI-переводов и заставка. Для сборки используется официальный внешний AutoIt **3.3.18.0**, для тестов зафиксирован Oracle **VirtualBox 7.2.22 r175245**. Дистрибутив проверяется по хешу и подписи, файлы извлекаются из MSI/CAB без скрытого запуска установщика.

**Проверяется не один EXE.** Оболочка называет отсутствующие или пустые обязательные EXE, DLL и файлы VBoxSup. Отдельно сообщает о недостающих папках, недоступных путях, ссылках и конфликтах с системной установкой. Наличие файлов не выдаётся за проверку подписи или разрешение запуска ВМ.

**Переносимые данные без переписывания чужих настроек.** Явная подготовка создаёт `data/.VirtualBox`, `data/Machines` и `logs`, сохраняя существующие файлы. Язык хранится в `data/launcher.ini`. Повреждённый или чужой файл не перезаписывается; новая настройка записывается через промежуточный файл в той же папке. Эти функции не редактируют Oracle XML.

**Окно Manager не равно работающей ВМ.** В отчёте раздельно показаны процессы Manager, GUI/headless-процессы ВМ и фоновые процессы. Это снимок наблюдений, а не подтверждение состояния гостевой ОС и не основание для остановки или удаления служб.

## Что можно использовать сейчас

Откройте EXE для GUI либо выполните:

```powershell
Portable-VirtualBox.exe --lang ru --help
Portable-VirtualBox.exe --save-language ru
Portable-VirtualBox.exe --save-language auto
Portable-VirtualBox.exe --prepare-profile
Portable-VirtualBox.exe --app-status
Portable-VirtualBox.exe --check-readiness
Portable-VirtualBox.exe --diagnose
Portable-VirtualBox.exe --about
```

`--save-language ru|en|auto` явно создаёт папки данных, если их ещё нет. Команды просмотра сами их не создают. `--app-status` возвращает 0 при наличии обязательных непустых файлов, 2 при отсутствии `app64`, 3 при неполном или небезопасном наборе. `--check-readiness` возвращает 3 при блокирующей причине либо 2, если проверки пройдены, но запуск отключён в этой сборке. Ни один код не включает запуск ВМ.

Если `launcher.ini` повреждён, файл сохраняется, используется язык Windows. Оставшийся `launcher.ini.pending` требует осмотра перед удалением: это может быть след прерванной записи. Не распаковывайте предварительную сборку поверх рабочей установки VirtualBox.

## Готовность и проверки

[FEATURES.md](https://github.com/zlocorp/Portable-VirtualBox/blob/dev/modernization-2026/FEATURES.md) отделяет **доступные пользователю функции**, **эксперименты CI** и **планы**. [CHANGELOG.md](https://github.com/zlocorp/Portable-VirtualBox/blob/dev/modernization-2026/CHANGELOG.md) ведётся в разделе **Unreleased**: опубликованных версий модернизации пока нет.

До этого пакета были подтверждены [сборка и ZIP](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39503487607), [нативные тесты](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39502031102) и [запуск пустой ВМ с очисткой собственных ресурсов](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39502023979). Пакет адаптаций прошёл [проверки обычного скомпилированного CLI и ZIP](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39548219426) и [18 нативных тестовых программ](https://github.com/zlocorp/Portable-VirtualBox/actions/runs/39548219415). Подробности этого этапа находятся в [отчёте](https://github.com/zlocorp/Portable-VirtualBox/blob/dev/modernization-2026/docs/EXECUTION-2026-10-21-community-adoption.md); последующие изменения упаковки отражаются в чейнджлоге.

**Пока не готово:** обычный Start/Stop Manager, проверенный привилегированный helper с UAC, полноценная миграция и восстановление ВМ, обновление Oracle с откатом, дополнительные USB/сетевые драйверы. Не заявляем запуск гостевой ОС с диском или визуальную приёмку Windows 11 и масштабирования. Успех теста на Windows Server не подменяет эту приёмку.

## Сборка, авторы и лицензия

[BUILDING.md](https://github.com/zlocorp/Portable-VirtualBox/blob/dev/modernization-2026/BUILDING.md) описывает сборку x64 через внешний AutoIt. ZIP содержит шесть файлов: лаунчер, предупреждение о статусе сборки, исходную лицензию, оба README и один CREDITS. Чейнджлог и список возможностей остаются в репозитории. Oracle, драйверы и данные ВМ в него не включены.

Основа: upstream `5b58dbbe701c3e2eb348942a9059708063b0cb96`. Сохранены исходные сведения об **авторе Michael Meyer (michaelm_007), участниках и проекте vboxme**. Модернизация ведётся в **zlocorp/Portable-VirtualBox**.

Исходная лицензия **CC BY-NC-SA 3.0** не изменена: [LICENSE.md](LICENSE.md). Источники и характер использования перечислены в [CREDITS.md](CREDITS.md); там же собраны уведомления о внешних компонентах. Упоминание Oracle, AutoIt и авторов сообщества не означает их одобрения этой сборки.
