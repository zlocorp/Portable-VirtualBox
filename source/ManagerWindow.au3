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
            If $g_MS_AlphaMode Then
                If $ru Then Return "ALPHA: только изолированный Windows 10/11 x64. Драйверы устанавливаются с UAC. Не используйте ценные ВМ. Интерактивный UAC ещё не прошёл приёмку."
                Return "ALPHA: isolated Windows 10/11 x64 only. Drivers require UAC. Never use valuable VMs. Interactive UAC is not accepted yet."
            EndIf
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
        Case "rebind"
            If $ru Then Return "Исправить регистрацию ВМ"
            Return "Repair moved VM"
        Case "rebind_backup"
            If $ru Then Return "Выберите заранее созданную проверенную резервную копию data/."
            Return "Select the existing verified full data/ backup folder."
        Case "rebind_confirm"
            If $ru Then Return "ALPHA: регистрация одной перенесенной ВМ будет изменена командами Oracle unregistervm (без удаления) и registervm после подготовки драйвера с UAC. Это необратимая промежуточная операция при сбое. Убедитесь, что резервная копия хранится отдельно и выбран одноразовый Windows-хост. Продолжить?"
            Return "ALPHA: Oracle will unregister (NEVER delete) and re-register one moved VM after UAC/driver preparation. A crash can leave the registration incomplete. Keep a separate verified backup and use a disposable Windows host. Continue?"
        Case "reopen"
            If $ru Then Return "Открыть Manager"
            Return "Reopen Manager"
        Case "close"
            If $ru Then Return "Закрыть"
            Return "Close"
        Case "leave_declined"
            If $ru Then Return "Очистка отменена в UAC. Драйверы и службы этой сессии ОСТАНУТСЯ в системе. Завершить лаунчер без очистки и при следующем запуске явно выбрать «Восстановить после сбоя»? Для безопасной очистки сейчас нажмите «Нет», затем «Завершить сессию»."
            Return "Cleanup UAC was declined. This session's drivers/services WILL REMAIN installed. Exit without cleanup and use explicit Recover on the next launch? Choose No and Finish session to retry cleanup now."
        Case "leave_failed"
            If $ru Then Return "ALPHA: состояние ВМ, служб или драйвера НЕ ПОДТВЕРЖДЕНО. Если выйти, ресурсы могут остаться работающими. После закрытия гостевых ВМ потребуется отдельное восстановление по защищённым квитанциям, а при неопределённости откат снимка тестовой Windows. Закрыть весь лаунчер без очистки?"
            Return "ALPHA: VM, driver or service state is NOT VERIFIED. Exit may leave them running. After all guests stop, explicit protected-receipt recovery is required; unknown states need restoring the disposable Windows snapshot. Exit the entire launcher without cleanup?"
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
        Case "REBIND_UNREGISTER"
            If $ru Then Return "Oracle снимает ТОЛЬКО старую запись UUID. Диски и снимки не удаляются."
            Return "Oracle unregistering only the stale UUID. No virtual disks or snapshots deleted."
        Case "REBIND_REGISTER"
            If $ru Then Return "Oracle регистрирует исходный файл ВМ в новом каталоге."
            Return "Oracle registering the same saved VM configuration at its new location."
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
        Case "VERIFYING_CLEAN"
            If $ru Then Return "Проверка стабильного завершения процессов VirtualBox перед новым запуском."
            Return "Verifying stable absence of VirtualBox processes before another start."
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

; A window X/Alt+F4 message still arrives even when the Close button is
; disabled. Never allow those paths to abandon a tracked system-action worker.
Func _MSW_MayProcessClose($worker)
    If Not IsMap($worker) Or Not MapExists($worker, "handle") Then Return False
    Return $worker["handle"] = 0
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
    Local $rebind = GUICtrlCreateButton(_MSW_Text("rebind"), 266, 294, 228, 36)
    Local $close = GUICtrlCreateButton(_MSW_Text("close"), 512, 294, 228, 36)
    Local $s = _MS_New($root, $workspace), $last = "", $tick = TimerInit(), $leftOwned = False
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
            Case $rebind
                If Not _MS_RetryAllowed($s["state"], $s["detail"]) Then ContinueLoop
                Local $plan = _PVR_Plan($root)
                If $plan["status"] <> "READY" Then
                    MsgBox(48, _MSW_Text("title"), _PVR_Text($plan), 0, $h)
                    ContinueLoop
                EndIf
                Local $backup = FileSelectFolder(_MSW_Text("rebind_backup"), "", 0x11, "", $h) ; filesystem folders only + editable path
                If $backup == "" Then ContinueLoop
                If MsgBox(0x34, _MSW_Text("title"), _PVR_Text($plan) & @CRLF & _
                        _MSW_Text("rebind_confirm"), 0, $h) <> 6 Then ContinueLoop
                ; _MS_Start re-checks the entire SHA-256 backup, stale UUID,
                ; inactive guest state and same source AFTER confirmation.
                _MS_Start($s, $backup)
            Case $close, $GUI_EVENT_CLOSE
                Local $runningWorker = $s["worker"]
                ; Disabling a GUI button never disables the window's native X.
                ; This guard applies equally to both events and Alt+F4.
                If Not _MSW_MayProcessClose($runningWorker) Then ContinueLoop
                If _MS_CanLeaveDeclined($s["state"], $s["owned"], $runningWorker["handle"]) Then
                    ; An explicit Yes leaves the original protected receipts for
                    ; next-launch Recover. Never silently request UAC again.
                    If MsgBox(0x34, _MSW_Text("title"), _MSW_Text("leave_declined"), 0, $h) == 6 Then
                        $leftOwned = True
                        ExitLoop
                    EndIf
                ElseIf $g_MS_AlphaMode And $s["state"] == "FAILED" Then
                    ; A confirmed helper failure can follow partial driver
                    ; installation, service registration, or Manager startup.
                    ; Never silently return to the main GUI holding a mutex.
                    If MsgBox(0x34, _MSW_Text("title"), _MSW_Text("leave_failed"), 0, $h) == 6 Then
                        $leftOwned = True
                        ExitLoop
                    EndIf
                ElseIf $s["state"] == "IDLE" Or $s["state"] == "CLEAN" Or $s["state"] == "BLOCKED" Or $s["state"] == "FAILED" Then
                    ExitLoop
                Else
                    _MS_Stop($s) ; normal Manager close, never kill a guest
                EndIf
        EndSwitch
        If TimerDiff($tick) > 250 Then
            _MS_Tick($s)
            $tick = TimerInit()
        EndIf
        Local $display = $s["state"] & @CRLF & _MSW_Text($s["state"]) & @CRLF & $s["detail"]
        If $last <> $display Then
            GUICtrlSetData($status, $display)
            Local $canStart = _MS_RetryAllowed($s["state"], $s["detail"])
            Local $canStop = $s["state"] == "MANAGER_OPEN" Or $s["state"] == "OPENING" Or $s["state"] == "CLEANUP_DECLINED"
            Local $canReopen = $s["state"] == "WAIT_GUESTS" Or $s["state"] == "WAIT_BACKGROUND"
            GUICtrlSetState($start, ($canStart ? $GUI_ENABLE : $GUI_DISABLE))
            GUICtrlSetState($stop, ($canStop ? $GUI_ENABLE : $GUI_DISABLE))
            GUICtrlSetState($reopen, ($canReopen ? $GUI_ENABLE : $GUI_DISABLE))
            GUICtrlSetState($recover, ((($s["state"] == "IDLE" Or $s["state"] == "BLOCKED") And $s["separated"]) ? $GUI_ENABLE : $GUI_DISABLE))
            GUICtrlSetState($rebind, ($canStart ? $GUI_ENABLE : $GUI_DISABLE))
            Local $workerNow = $s["worker"]
            Local $canClose = _MSW_MayProcessClose($workerNow) And ($s["state"] == "IDLE" Or $s["state"] == "CLEAN" Or _
                $s["state"] == "BLOCKED" Or $s["state"] == "MANAGER_OPEN" Or _
                $s["state"] == "OPENING" Or _
                (_MS_CanLeaveDeclined($s["state"], $s["owned"], $workerNow["handle"])) Or _
                ($s["state"] == "FAILED" And $workerNow["handle"] = 0))
            GUICtrlSetState($close, ($canClose ? $GUI_ENABLE : $GUI_DISABLE))
            $last = $display
        EndIf
        Sleep(15)
    WEnd
    GUIDelete($h)
    If $leftOwned Then Return 4 ; caller must EXIT, not reopen its main GUI
    If $s["state"] == "FAILED" Then Return 3
    Return 0
EndFunc
