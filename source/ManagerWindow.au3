#include-once
#include "ManagerSession.au3"
#include "LauncherSettings.au3"
#include <GUIConstantsEx.au3>
#include <EditConstants.au3>
#include <WindowsStylesConstants.au3>

Func _MSW_Text($key)
    Local $ru = _LI_Language() == "ru"
    Switch $key
        Case "title"
            If $ru Then Return "Portable-VirtualBox | Проверка сессии Manager"
            Return "Portable-VirtualBox | Manager session test"
        Case "warning"
            If $ru Then Return "Экспериментальная сборка: только одноразовый Windows-хост. Системные операции ещё не готовы для обычного ПК."
            Return "Experimental build: disposable Windows host only. System operations are not yet approved for an ordinary PC."
        Case "start"
            If $ru Then Return "Запустить VirtualBox"
            Return "Start VirtualBox"
        Case "stop"
            If $ru Then Return "Завершить сессию"
            Return "Finish session"
        Case "recover"
            If $ru Then Return "Восстановить после сбоя"
            Return "Recover abandoned session"
        Case "reopen"
            If $ru Then Return "Открыть Manager"
            Return "Reopen Manager"
        Case "close"
            If $ru Then Return "Закрыть"
            Return "Close"
        Case "IDLE"
            If $ru Then Return "Готов к началу изолированной тестовой сессии."
            Return "Ready to start the isolated test session."
        Case "CONSENT_PREPARE"
            If $ru Then Return "Ожидание UAC Windows для подготовки драйвера. Подтвердите или отмените запрос в Windows."
            Return "Waiting for Windows UAC approval to prepare the driver. Approve or cancel in Windows."
        Case "CONSENT_RECOVER"
            If $ru Then Return "Ожидание разрешения UAC на восстановление заброшенной сессии. ВМ не завершаются автоматически."
            Return "Waiting for UAC consent to recover an abandoned session. VMs will not be stopped automatically."
        Case "RECOVERING"
            If $ru Then Return "Проверка старого контроллера, служб и документов владения перед очисткой."
            Return "Verifying old controller, services and ownership receipts before cleanup."
        Case "CONSENT_FINISH"
            If $ru Then Return "Ожидание UAC Windows для очистки. Драйверы сохраняются до подтверждённого завершения."
            Return "Waiting for Windows UAC approval to clean up. Drivers remain until cleanup is verified."
        Case "PREPARING"
            If $ru Then Return "Ожидание подтверждения Windows и подготовки драйвера."
            Return "Waiting for Windows consent and driver preparation."
        Case "CONFIGURING"
            If $ru Then Return "Настройка переносимого профиля с обычными правами пользователя."
            Return "Configuring the portable profile with ordinary user rights."
        Case "CLEANUP_DECLINED"
            If $ru Then Return "Повышение прав отменено. Ресурсы сохранены. Нажмите «Завершить сессию», чтобы повторить очистку."
            Return "Elevation was declined. Resources retained. Click Finish session to retry cleanup."
        Case "OPENING"
            If $ru Then Return "Открывается окно Oracle VirtualBox Manager."
            Return "Opening the Oracle VirtualBox Manager window."
        Case "MANAGER_OPEN"
            If $ru Then Return "Manager открыт. ВМ можно запускать в его окне."
            Return "Manager is open. Virtual machines can be started there."
        Case "CLOSING"
            If $ru Then Return "Отправлен запрос закрытия Manager. ВМ принудительно не останавливаются."
            Return "Manager close requested. Virtual machines are not force-stopped."
        Case "WAIT_GUESTS"
            If $ru Then Return "ВМ ещё работают. Драйверы сохранены. Завершите ВМ или откройте Manager снова."
            Return "VM processes are still active. Drivers remain loaded. Stop the VMs or reopen Manager."
        Case "WAIT_BACKGROUND"
            If $ru Then Return "Ожидание фоновых процессов VirtualBox. Принудительного завершения нет."
            Return "Waiting for VirtualBox background processes. No forced termination."
        Case "READY_TO_CLEAN"
            If $ru Then Return "Активность завершена. Повторная проверка перед очисткой."
            Return "Activity ended. Rechecking before cleanup."
        Case "CLEANING"
            If $ru Then Return "Удаление только созданных этой сессией служб и драйвера."
            Return "Removing only services and the driver created by this session."
        Case "CLEAN"
            If $ru Then Return "Сессия завершена. Системные ресурсы очищены, данные ВМ сохранены."
            Return "Session finished. System resources are clean; VM data is preserved."
        Case "BLOCKED"
            If $ru Then Return "Запуск заблокирован: конфликт или неподходящая среда."
            Return "Start blocked: conflict or unsupported environment."
        Case "FAILED"
            If $ru Then Return "Результат операции не подтверждён. Автоматическая очистка остановлена; проверьте журнал."
            Return "The operation could not be verified. Automatic cleanup stopped; inspect the session log."
    EndSwitch
    Return $key
EndFunc

Func _MSW_Show($root, $workspace)
    Local $h = GUICreate(_MSW_Text("title"), 760, 360)
    Local $warning = GUICtrlCreateLabel(_MSW_Text("warning"), 20, 16, 720, 48)
    GUICtrlSetFont($warning, 10, 600, 0, "Segoe UI")
    Local $status = GUICtrlCreateEdit("", 20, 76, 720, 136, BitOR($ES_READONLY, $WS_VSCROLL))
    GUICtrlSetFont($status, 11, 400, 0, "Segoe UI")
    Local $start = GUICtrlCreateButton(_MSW_Text("start"), 20, 232, 228, 38)
    Local $stop = GUICtrlCreateButton(_MSW_Text("stop"), 266, 232, 228, 38)
    Local $reopen = GUICtrlCreateButton(_MSW_Text("reopen"), 512, 232, 228, 38)
    Local $recover = GUICtrlCreateButton(_MSW_Text("recover"), 20, 294, 228, 36)
    Local $close = GUICtrlCreateButton(_MSW_Text("close"), 512, 294, 228, 36)
    Local $s = _MS_New($root, $workspace), $last = "", $tick = TimerInit()
    GUISetState(@SW_SHOW, $h)
    While 1
        Local $event = GUIGetMsg()
        Switch $event
            Case $start
                _MS_Start($s)
            Case $stop
                _MS_Stop($s)
            Case $reopen
                _MS_Reopen($s)
            Case $recover
                ; Never auto-delete services or guests. Every recovery needs
                ; an explicit click AND a separate Windows consent action.
                _MS_Recover($s)
            Case $close, $GUI_EVENT_CLOSE
                If $s["state"] == "IDLE" Or $s["state"] == "CLEAN" Or $s["state"] == "BLOCKED" Or $s["state"] == "FAILED" Then ExitLoop
                _MS_Stop($s) ; do not abandon a live normal session on window close
        EndSwitch
        If TimerDiff($tick) > 250 Then
            _MS_Tick($s)
            $tick = TimerInit()
        EndIf
        Local $display = $s["state"] & @CRLF & _MSW_Text($s["state"]) & @CRLF & $s["detail"]
        If $last <> $display Then
            GUICtrlSetData($status, $display)
            Local $canStart = $s["state"] == "IDLE" Or $s["state"] == "CLEAN"
            Local $canStop = $s["state"] == "MANAGER_OPEN" Or $s["state"] == "OPENING" Or $s["state"] == "CLEANUP_DECLINED"
            Local $canReopen = $s["state"] == "WAIT_GUESTS" Or $s["state"] == "WAIT_BACKGROUND"
            GUICtrlSetState($start, ($canStart ? $GUI_ENABLE : $GUI_DISABLE))
            GUICtrlSetState($stop, ($canStop ? $GUI_ENABLE : $GUI_DISABLE))
            GUICtrlSetState($reopen, ($canReopen ? $GUI_ENABLE : $GUI_DISABLE))
            GUICtrlSetState($recover, ((($s["state"] == "IDLE" Or $s["state"] == "BLOCKED") And $s["separated"]) ? $GUI_ENABLE : $GUI_DISABLE))
            $last = $display
        EndIf
        Sleep(15)
    WEnd
    GUIDelete($h)
    If $s["state"] == "FAILED" Then Return 3
    Return 0
EndFunc
