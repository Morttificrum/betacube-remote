; Beta Cube Remote Access — Installer Script
; Baseado em RustDesk (AGPL-3.0)
; Customizado por Beta Cube Soluções em TI

!define APP_NAME "Beta Cube Remote"
!define APP_VERSION "1.0.0"
!define APP_PUBLISHER "Beta Cube Soluções em TI"
!define APP_URL "https://betacube.com.br"
!define APP_EXE "betacube-remote.exe"
!define RUSTDESK_SERVER "140.238.184.251"
!define RUSTDESK_KEY "YcoVB4h1Ldi08DJmV4X1Yk7u0gi0yQFmqCgbLwZ9wsk="
!define INSTALL_DIR "$PROGRAMFILES64\${APP_NAME}"
!define UNINSTALL_REG "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}"

Name "${APP_NAME}"
OutFile "output\BetaCubeRemote-Setup.exe"
InstallDir "${INSTALL_DIR}"
RequestExecutionLevel admin
SetCompressor /SOLID lzma
Unicode True

Page directory
Page instfiles
UninstPage uninstConfirm
UninstPage instfiles

Section "Instalar ${APP_NAME}" SecMain
  SetOutPath "$INSTDIR"

  File /oname=${APP_EXE} "..\rustdesk.exe"
  File "..\hwsensor-helper.exe"

  CreateShortcut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0

  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\Desinstalar ${APP_NAME}.lnk" "$INSTDIR\uninstall.exe"

  WriteRegStr HKLM "${UNINSTALL_REG}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKLM "${UNINSTALL_REG}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKLM "${UNINSTALL_REG}" "Publisher" "${APP_PUBLISHER}"
  WriteRegStr HKLM "${UNINSTALL_REG}" "URLInfoAbout" "${APP_URL}"
  WriteRegStr HKLM "${UNINSTALL_REG}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINSTALL_REG}" "UninstallString" "$INSTDIR\uninstall.exe"
  WriteRegDWORD HKLM "${UNINSTALL_REG}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINSTALL_REG}" "NoRepair" 1

  WriteUninstaller "$INSTDIR\uninstall.exe"

  ; O nome da pasta/arquivo de config é derivado de APP_NAME em tempo de
  ; execução (hbb_common::config::APP_NAME, setado em src/common.rs::global_init).
  ; Tem que bater exatamente com "${APP_NAME}", senão o app não acha essa config.
  CreateDirectory "$APPDATA\${APP_NAME}\config"
  FileOpen $0 "$APPDATA\${APP_NAME}\config\${APP_NAME}2.toml" w
  FileWrite $0 "rendezvous_server = '${RUSTDESK_SERVER}'$\n"
  FileWrite $0 "nat_type = 1$\n"
  FileWrite $0 "serial = 0$\n"
  FileWrite $0 "$\n"
  FileWrite $0 "[options]$\n"
  FileWrite $0 "custom-rendezvous-server = '${RUSTDESK_SERVER}'$\n"
  FileWrite $0 "key = '${RUSTDESK_KEY}'$\n"
  FileWrite $0 "relay-server = '${RUSTDESK_SERVER}'$\n"
  FileWrite $0 "api-server = 'http://${RUSTDESK_SERVER}:21114'$\n"
  FileWrite $0 "direct-server = 'Y'$\n"
  FileClose $0

  ExecWait '"$INSTDIR\${APP_EXE}" --install'

  MessageBox MB_OK "Beta Cube Remote instalado com sucesso!$\n$\nO acesso remoto Beta Cube esta pronto.$\nAbra o app e passe o ID para a equipe."
SectionEnd

Section "Uninstall"
  ExecWait '"$INSTDIR\${APP_EXE}" --uninstall'
  Sleep 2000

  Delete "$INSTDIR\${APP_EXE}"
  Delete "$INSTDIR\hwsensor-helper.exe"
  Delete "$INSTDIR\uninstall.exe"
  RMDir "$INSTDIR"

  Delete "$DESKTOP\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\Desinstalar ${APP_NAME}.lnk"
  RMDir "$SMPROGRAMS\${APP_NAME}"

  DeleteRegKey HKLM "${UNINSTALL_REG}"
SectionEnd
