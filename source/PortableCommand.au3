#include-once
; Run one *explicitly named* local EXE with bounded observation, capture and
; a retained query-only handle. No shell, global process names, or ProcessClose.
; If a child times out, leave it untouched, mark the result uncertain, and
; prevent the caller from guessing that cleanup is authorized.
Func _PXR_New()
    Local $r[]
    $r["status"] = "BLOCKED"
    $r["exit_code"] = -1
    $r["output"] = ""
    $r["error_output"] = ""
    $r["pid"] = 0
    Return $r
EndFunc

Func _PXR_Run($exe, $args, $cwd, $timeoutMs)
    Local $r = _PXR_New()
    If Not IsString($exe) Or Not IsString($args) Or Not IsString($cwd) Then Return $r
    If Not IsNumber($timeoutMs) Or $timeoutMs < 30 Or $timeoutMs > 120000 Then Return $r
    If $exe == "" Or StringInStr($exe, Chr(34)) Or StringInStr($exe, @CR) Or StringInStr($exe, @LF) Then Return $r
    If Not FileExists($exe) Or Not FileExists($cwd) Then Return $r
    ; STDOUT_CHILD=2, STDERR_CHILD=4. Child has dedicated redirected pipes.
    Local $pid = Run('"' & $exe & '" ' & $args, $cwd, @SW_HIDE, 6)
    If @error Or $pid = 0 Then
        $r["status"] = "START_ERROR"
        Return $r
    EndIf
    $r["pid"] = $pid
    ; Query-only, noninherited handle with SYNCHRONIZE and
    ; PROCESS_QUERY_LIMITED_INFORMATION: cannot terminate the child.
    Local $opened = DllCall("kernel32.dll", "handle", "OpenProcess", "dword", 0x00101000, "bool", False, "dword", $pid)
    If @error Or Not IsArray($opened) Then
        $r["status"] = "HANDLE_ERROR"
        Return $r
    EndIf
    If $opened[0] = 0 Then
        $r["status"] = "HANDLE_ERROR"
        Return $r
    EndIf
    Local $h = $opened[0]
    Local $clock = TimerInit(), $finished = False, $readProblem = False
    While TimerDiff($clock) < $timeoutMs
        Local $a = StdoutRead($pid)
        If IsString($a) Then $r["output"] &= $a
        Local $b = StderrRead($pid)
        If IsString($b) Then $r["error_output"] &= $b
        ; A child exceeding the small bounded audit capture is unknown.
        If StringLen($r["output"]) > 262144 Or StringLen($r["error_output"]) > 262144 Then
            $readProblem = True
            ExitLoop
        EndIf
        Local $w = DllCall("kernel32.dll", "dword", "WaitForSingleObject", "handle", $h, "dword", 0)
        If @error Or Not IsArray($w) Then
            $readProblem = True
            ExitLoop
        EndIf
        If $w[0] = 0 Then
            $finished = True
            ExitLoop
        EndIf
        If $w[0] <> 258 Then
            $readProblem = True
            ExitLoop
        EndIf
        Sleep(15)
    WEnd
    If $finished And Not $readProblem Then
        ; Consume remaining small streams after the process has exited.
        Local $tail = StdoutRead($pid)
        If IsString($tail) Then $r["output"] &= $tail
        $tail = StderrRead($pid)
        If IsString($tail) Then $r["error_output"] &= $tail
        Local $code = DllCall("kernel32.dll", "bool", "GetExitCodeProcess", "handle", $h, "dword*", 0)
        If Not @error And IsArray($code) And $code[0] <> 0 And $code[2] <> 259 And _
                StringLen($r["output"]) <= 262144 And StringLen($r["error_output"]) <= 262144 Then
            $r["status"] = "EXITED"
            $r["exit_code"] = $code[2]
        Else
            $r["status"] = "UNKNOWN"
        EndIf
    ElseIf $readProblem Then
        $r["status"] = "UNKNOWN"
    Else
        $r["status"] = "TIMEOUT"
    EndIf
    DllCall("kernel32.dll", "bool", "CloseHandle", "handle", $h)
    Return $r
EndFunc
