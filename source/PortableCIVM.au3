#include-once
#include "PortableCISession.au3"
#include "PortableCommand.au3"
; Interface-only red checkpoint; no VM operations.
Func _PCVM_Allowed($actions,$runner,$os,$repo,$root,$temp)
    Return False
EndFunc
Func _PCVM_ExpectedSup($obs)
    Return False
EndFunc
Func _PCVM_State($raw)
    Return ""
EndFunc
Func _PCVM_UUID($raw)
    Return ""
EndFunc
Func _PCVM_Execute($root)
    Return 9
EndFunc
