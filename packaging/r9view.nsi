; Installer for r9view on Windows.
;
; Built by tools/package-windows.ps1, which stages dist\r9view\ first and then
; runs makensis over this. It installs for the current user, so it never asks
; for administrator rights.
;
;   makensis -DSTAGE=..\dist\r9view -DVERSION=1.0.0 -DOUTFILE=..\dist\setup.exe r9view.nsi

Unicode true
ManifestDPIAware true

; Installs for the current user only, which means no UAC prompt on the way in
; and none on the way out either. Everything it writes is under the user's own
; profile and HKEY_CURRENT_USER. An all-users install would need administrator
; rights for an application that has no reason to want them.
RequestExecutionLevel user

!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "WordFunc.nsh"
!include "LogicLib.nsh"

!ifndef VERSION
  !define VERSION "1.0.0"
!endif
!ifndef STAGE
  !define STAGE "..\dist\r9view"
!endif
!ifndef OUTFILE
  !define OUTFILE "..\dist\r9view-${VERSION}-windows-x64-setup.exe"
!endif

!define APPNAME "r9view"
!define PUBLISHER "Rhineul Islam"
!define PROGID "r9view.media"
!define UNINSTKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\r9view"

Name "${APPNAME} ${VERSION}"
InstallDir "$LOCALAPPDATA\Programs\r9view"
InstallDirRegKey HKCU "${UNINSTKEY}" "InstallLocation"
OutFile "${OUTFILE}"
BrandingText "${APPNAME} ${VERSION}"
; The payload is already deflate-compressed Qt and a 115 MB libmpv; LZMA earns
; its keep here.
SetCompressor /SOLID lzma
SetCompressorDictSize 64

!define MUI_ABORTWARNING
!define MUI_ICON "r9view.ico"
!define MUI_UNICON "r9view.ico"
!define MUI_FINISHPAGE_RUN "$INSTDIR\r9view.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Open ${APPNAME}"

!insertmacro MUI_PAGE_LICENSE "..\LICENSE"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

; These headers only declare the macros; the functions behind them have to be
; asked for, and the uninstaller needs its own copy of each.
!insertmacro GetSize
!insertmacro WordFind
!insertmacro un.WordFind

; Every extension r9view will offer to open. It is added to "Open with" rather
; than made the default for anything -- taking over every video on a machine
; uninvited is not an installer's decision to make.
Var Ext

Function RegisterOne
  ; $Ext holds one extension, e.g. ".mkv"
  WriteRegStr HKCU "Software\Classes\$Ext\OpenWithProgids" "${PROGID}" ""
  WriteRegStr HKCU "Software\Classes\Applications\r9view.exe\SupportedTypes" "$Ext" ""
FunctionEnd

Function un.UnregisterOne
  DeleteRegValue HKCU "Software\Classes\$Ext\OpenWithProgids" "${PROGID}"
FunctionEnd

; NSIS has no list type, so the extensions live in one space-separated string
; and WordFind walks it. TAG only exists to keep the labels unique between the
; installer and uninstaller copies -- a function name cannot be used for that,
; because the uninstaller's is "un.UnregisterOne" and a label cannot hold a dot.
!define EXTLIST ".cbz .cbr .cb7 .cbt .png .jpg .jpeg .jpe .jfif .webp .avif .jxl .heic .heif .gif .bmp .tif .tiff .psd .svg .ico .tga .jp2 .exr .qoi .dds .xcf .mkv .mp4 .m4v .avi .mov .webm .ts .m2ts .mts .wmv .asf .flv .mpg .mpeg .m2v .vob .ogv .rm .rmvb .3gp .divx .mxf .mk3d .mp3 .flac .m4a .aac .ogg .oga .opus .wav .wma .alac .ape .mka .ac3 .dts .aiff .dsf .mpc .wv"

!macro EachExtension FN TAG U
  StrCpy $R0 1
  loop_${TAG}:
    ClearErrors
    ${${U}WordFind} "${EXTLIST}" " " "E+$R0" $Ext
    IfErrors done_${TAG}
    StrCmp $Ext "" done_${TAG}
    Call ${FN}
    IntOp $R0 $R0 + 1
    Goto loop_${TAG}
  done_${TAG}:
!macroend

Section "r9view" SecMain
  SectionIn RO
  SetOutPath "$INSTDIR"
  File /r "${STAGE}\*.*"

  CreateShortcut "$SMPROGRAMS\${APPNAME}.lnk" "$INSTDIR\r9view.exe" "" "$INSTDIR\r9view.exe" 0 \
      SW_SHOWNORMAL "" "Touch-first image, comic and video viewer"

  WriteRegStr HKCU "Software\Classes\${PROGID}" "" "Media file"
  WriteRegStr HKCU "Software\Classes\${PROGID}\DefaultIcon" "" "$INSTDIR\r9view.exe,0"
  WriteRegStr HKCU "Software\Classes\${PROGID}\shell\open\command" "" '"$INSTDIR\r9view.exe" "%1"'
  WriteRegStr HKCU "Software\Classes\Applications\r9view.exe" "FriendlyAppName" "${APPNAME}"
  WriteRegStr HKCU "Software\Classes\Applications\r9view.exe\shell\open\command" "" '"$INSTDIR\r9view.exe" "%1"'
  !insertmacro EachExtension RegisterOne INST ""

  WriteUninstaller "$INSTDIR\uninstall.exe"
  WriteRegStr HKCU "${UNINSTKEY}" "DisplayName" "${APPNAME}"
  WriteRegStr HKCU "${UNINSTKEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINSTKEY}" "Publisher" "${PUBLISHER}"
  WriteRegStr HKCU "${UNINSTKEY}" "DisplayIcon" "$INSTDIR\r9view.exe"
  WriteRegStr HKCU "${UNINSTKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTKEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegStr HKCU "${UNINSTKEY}" "QuietUninstallString" '"$INSTDIR\uninstall.exe" /S'
  WriteRegDWORD HKCU "${UNINSTKEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTKEY}" "NoRepair" 1
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKCU "${UNINSTKEY}" "EstimatedSize" "$0"

  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, i 0, i 0)'
SectionEnd

Section "Uninstall"
  Delete "$SMPROGRAMS\${APPNAME}.lnk"
  !insertmacro EachExtension un.UnregisterOne UNINST "un."
  DeleteRegKey HKCU "Software\Classes\${PROGID}"
  DeleteRegKey HKCU "Software\Classes\Applications\r9view.exe"
  DeleteRegKey HKCU "${UNINSTKEY}"
  Delete "$INSTDIR\uninstall.exe"
  RMDir /r "$INSTDIR"
  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, i 0, i 0)'
SectionEnd
