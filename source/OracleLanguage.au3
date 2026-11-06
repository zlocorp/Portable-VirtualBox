#include-once
#include "LauncherSettings.au3"
#include "PortableVmInventory.au3"
; Oracle GUI language is a user-profile preference, never a privileged verb.
; The GUI/LanguageID key and ru/C values follow Oracle's UIExtraData/UITranslator.
; Only explicitly saved launcher preferences synchronize. A temporary --lang or
; auto selection must not overwrite a separately chosen Oracle preference.

Func _OL_Saved($settings)
    If Not IsMap($settings) Then Return ""
    If Not MapExists($settings, "status") Or Not MapExists($settings, "language") Then Return ""
    If $settings["status"] <> "READY" Then Return ""
    If Not _LS_Valid($settings["language"]) Then Return ""
    Switch $settings["language"]
        Case "ru"
            Return "ru"
        Case "en"
            Return "C"
    EndSwitch
    Return ""
EndFunc

Func _OL_Command($id)
    If Not IsString($id) Or Not ($id == "ru" Or $id == "C") Then Return ""
    Return "setextradata global GUI/LanguageID " & $id
EndFunc

; Verify persisted preference using the existing bounded no-DTD/no-XXE reader.
; This is not proof that every Oracle caption was translated at runtime.
Func _OL_Verified($root, $id)
    If _OL_Command($id) == "" Then Return False
    Local $profile = _PP_Inspect($root)
    If $profile["status"] <> "READY" Then Return False
    Local $xml = _PVI_LoadXml($profile["profile"] & "\VirtualBox.xml")
    If Not IsObj($xml) Then Return False
    Local $ns = $xml.documentElement.namespaceURI
    If $ns <> "" And $ns <> "http://www.virtualbox.org/" Then Return False
    Local $globals = $xml.selectNodes('//*[local-name()="Global"]')
    If Not IsObj($globals) Then Return False
    If $globals.length <> 1 Then Return False
    Local $space = '[namespace-uri()="' & $ns & '"]'
    Local $extras = $xml.selectNodes('/*[local-name()="VirtualBox"]' & $space & _
        '/*[local-name()="Global"]' & $space & '/*[local-name()="ExtraData"]')
    If Not IsObj($extras) Then Return False
    If $extras.length <> 1 Then Return False
    Local $nodes = $xml.selectNodes('/*[local-name()="VirtualBox"]' & $space & _
        '/*[local-name()="Global"]' & $space & '/*[local-name()="ExtraData"]' & $space & _
        '/*[local-name()="ExtraDataItem"]' & $space & '[@name="GUI/LanguageID"]')
    If Not IsObj($nodes) Then Return False
    If $nodes.length <> 1 Then Return False
    Return $nodes.item(0).getAttribute("value") == $id
EndFunc
