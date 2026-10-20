#include-once
#include "PortableProfile.au3"
#include "HostPreflight.au3"
Func _PVS_Allowed($actions, $runner, $os, $repo, $root, $temp)
    Return False
EndFunc
Func _PVS_CanonicalImage($text)
    Return ""
EndFunc
Func _PVS_Execute($root)
    Return 9
EndFunc
