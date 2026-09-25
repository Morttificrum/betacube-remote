; Beta Cube Remote Access — Installer Script
; Baseado em RustDesk (AGPL-3.0)
; Customizado por Beta Cube Soluções em TI

!define APP_NAME "Beta Cube Remote"
!define APP_VERSION "1.0.0"
!define APP_PUBLISHER "Beta Cube Soluções em TI"
!define APP_URL "https://betacube.com.br"
; TEM QUE bater exatamente com "{app_name}.exe" que o próprio RustDesk usa
; internamente (src/platform/windows.rs: get_install_info_with_subkey monta
; `exe = format!("{}\{}.exe", path, get_app_name())`, e rename_exe_cmd RENOMEIA
; o exe em disco pra esse nome se não bater -- com "betacube-remote.exe"
; (hífen, sem espaço) isso nunca batia, o --install (chamado abaixo)
; renomeava o exe por baixo dos panos e os atalhos/registro do NSIS ficavam
; órfãos, apontando pro nome antigo. É por isso que a instalação "terminava
; sem erro" mas o atalho não abria nada.
!define APP_EXE "${APP_NAME}.exe"
!define RUSTDESK_SERVER "140.238.184.251"
!define RUSTDESK_KEY "YcoVB4h1Ldi08DJmV4X1Yk7u0gi0yQFmqCgbLwZ9wsk="
!define INSTALL_DIR "$PROGRAMFILES64\${APP_NAME}"
!define UNINSTALL_REG "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}"

; STORE_NAME: tag de loja/cliente, passada via "makensis /DSTORE_NAME=...".
; Vazio = instalador genérico de sempre (guard pra continuar buildável sem
; o parâmetro, ex. teste local). Ver betacube-bridge: vira o campo
; preset-note no sysinfo, usado pra criar/associar a Entidade da loja no GLPI.
!ifndef STORE_NAME
!define STORE_NAME ""
!endif

Name "${APP_NAME}"
!if "${STORE_NAME}" == ""
OutFile "output\BetaCubeRemote-Setup.exe"
!else
OutFile "output\betacube-remote-${STORE_NAME}-setup.exe"
!endif
InstallDir "${INSTALL_DIR}"
RequestExecutionLevel admin
SetCompressor /SOLID lzma
Unicode True

Page directory
Page instfiles
UninstPage uninstConfirm
UninstPage instfiles

Section "Instalar ${APP_NAME}" SecMain
  ; NAO extrai direto em $INSTDIR -- ver get_uninstall() em
  ; src/platform/windows.rs: "if exist "{path}" rd /s /q "{path}"" roda
  ; INCONDICIONALMENTE (nao depende do registro) no INICIO de todo
  ; --install, apagando o diretorio de instalacao inteiro antes de
  ; recopiar a partir de onde o exe atual esta rodando (current_exe()).
  ; Se a gente extrai tudo direto em $INSTDIR e roda o exe de la, essa
  ; limpeza apaga TUDO que acabamos de colocar -- inclusive o proprio exe
  ; em execucao -- e o XCOPY de repopulacao que vem depois (copy_exe_cmd,
  ; a partir do current_exe(), que agora e um caminho fantasma) falha
  ; silenciosamente pra boa parte dos arquivos. Foi essa a causa raiz real
  ; do "instala mas fica com pasta incompleta / janela em branco".
  ;
  ; Em vez disso: extrai pra uma pasta TEMPORARIA separada e roda o
  ; --install a partir dela -- exatamente como o design original do
  ; RustDesk espera (o .exe portatil faz a mesma coisa, só que a partir de
  ; %LOCALAPPDATA%\rustdesk). Assim, quando get_uninstall() checa
  ; "if exist $INSTDIR", ainda nao existe nada la (rd /s /q vira no-op), e
  ; o XCOPY interno do install_me() copia tudo certinho a partir da pasta
  ; temp intacta.
  !define TEMP_SRC "$TEMP\BetaCubeRemoteInstallSrc"
  SetOutPath "${TEMP_SRC}"

  ; O payload em ..\rdpayload é a build "crua" do Flutter extraída do MSI
  ; oficial via msiexec /a (ver .github\scripts\extract-rustdesk-msi.ps1) --
  ; RustDesk.exe pequeno + DLLs ao lado + data\/drivers\/usbmmidd_v2\. Isso
  ; substitui o antigo esquema de extrair só "rustdesk.exe" (o .exe portátil
  ; do release), que era um stub autoextraível que sempre rodava a partir de
  ; %LOCALAPPDATA%\rustdesk (hardcoded) e nunca respeitava nosso APP_NAME.
  ;
  ; ${APP_EXE} agora tem espaço ("Beta Cube Remote.exe") -- a aspa tem que
  ; envolver o argumento /oname=... INTEIRO (prefixo incluso), não só o
  ; valor depois do "=": `/oname="valor"` quebra o parser do NSIS (erro de
  ; "Usage: File..."), o certo é `"/oname=valor"`.
  File "/oname=${APP_EXE}" "..\rdpayload\RustDesk.exe"
  File /r /x "RustDesk.exe" "..\rdpayload\*.*"
  File "..\hwsensor-helper.exe"

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
!if "${STORE_NAME}" != ""
  FileWrite $0 "preset-note = '${STORE_NAME}'$\n"
!endif
  FileClose $0

  ; Limpa qualquer resíduo "RustDesk" (nome genérico, NUNCA o nosso) de
  ; testes/instalações anteriores a este fix (2026-09-23) -- nosso
  ; desinstalador só sabia procurar por "${APP_NAME}", nunca pelo nome
  ; genérico puro, então um atalho/chave órfão desses ficava pra
  ; sempre, mesmo depois de reinstalar com a versão corrigida. Cobre os
  ; dois locais que o --install nativo usa (%PUBLIC%\Desktop e
  ; %ProgramData%\...\Start Menu, ver install_me() em
  ; platform/windows.rs) e os per-user (caso tenha vindo do NSIS antigo,
  ; antes do fix do atalho duplicado). Silencioso se não existir --
  ; Delete/RMDir não falham em cima de arquivo/pasta inexistente.
  Delete "$%PUBLIC%\Desktop\RustDesk.lnk"
  Delete "$%PROGRAMDATA%\Microsoft\Windows\Start Menu\Programs\RustDesk\RustDesk.lnk"
  Delete "$%PROGRAMDATA%\Microsoft\Windows\Start Menu\Programs\RustDesk\Uninstall RustDesk.lnk"
  RMDir "$%PROGRAMDATA%\Microsoft\Windows\Start Menu\Programs\RustDesk"
  Delete "$DESKTOP\RustDesk.lnk"
  Delete "$SMPROGRAMS\RustDesk\RustDesk.lnk"
  Delete "$SMPROGRAMS\RustDesk\Desinstalar RustDesk.lnk"
  RMDir "$SMPROGRAMS\RustDesk"
  ; Mesma limpeza pra chave de registro genérica que causava o bug do
  ; caminho errado ("C:\Program Files\RustDesk") -- ver get_valid_subkey()
  ; em platform/windows.rs, corrigido no mesmo commit. Some com qualquer
  ; InstallLocation órfão gravado ali por causa antiga/desconhecida.
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\{54E86BC2-6C85-41F3-A9EB-1A94AC9B1F93}_is1"
  DeleteRegKey HKLM "Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{54E86BC2-6C85-41F3-A9EB-1A94AC9B1F93}_is1"

  ; --silent-install (NÃO --install) é o auto-instalador completo do
  ; próprio RustDesk (serviço, driver de impressora, atalhos e registro
  ; de desinstalação PRÓPRIOS, independentes do NSIS -- ver
  ; src/platform/windows.rs::install_me, chamado com silent=true só por
  ; --silent-install -- ver core_main.rs). Roda a partir da pasta TEMP
  ; (ver comentário lá acima), não de $INSTDIR.
  ;
  ; BUG REAL DE CAMPO (2026-09-25, confirmado numa loja de verdade e na
  ; VM Hyper-V de teste): "--install" puro abre uma tela de confirmação
  ; Flutter ("Instalação" -- caminho, checkboxes de atalho, botões
  ; "Aceitar e Instalar"/"Executar sem instalar") e ESPERA CLIQUE. Numa
  ; instalação de loja feita por acesso remoto, ninguém sabe que precisa
  ; clicar ali depois do wizard NSIS já ter dito "Concluir" -- o app fica
  ; rodando em modo portátil (sem serviço do Windows nunca criado/
  ; iniciado), exatamente o bug "só funciona com a janela aberta, não
  ; sobrevive a reboot". "--silent-install" pula essa tela e roda
  ; install_me() direto, incluindo a criação do serviço (get_create_service
  ; em windows.rs -- sc create/start/failure).
  ;
  ; Roda ANTES dos nossos CreateShortcut/WriteRegStr/WriteUninstaller de
  ; propósito: ele grava um UninstallString apontando pra si mesmo, e os
  ; passos abaixo sobrescrevem isso de novo pro nosso uninstall.exe.
  ExecWait '"${TEMP_SRC}\${APP_EXE}" --silent-install'
  RMDir /r "${TEMP_SRC}"

  ; NÃO cria atalho de área de trabalho/menu iniciar principal aqui --
  ; bug real de teste (2026-09-21): o --install acima (RustDesk nativo,
  ; ver comentário logo acima e install_me() em platform/windows.rs) JÁ
  ; cria os dois sozinho -- atalho de área de trabalho em
  ; "%PUBLIC%\Desktop\{app_name}.lnk" (todos os usuários) e pasta de
  ; menu iniciar em "%ProgramData%\...\Start Menu\Programs\{app_name}\"
  ; -- e o Windows sobrepõe %PUBLIC%\Desktop com a área de trabalho do
  ; usuário atual na mesma tela. Criar de novo aqui (sem
  ; SetShellVarContext all, então em pastas per-user DIFERENTES das do
  ; nativo) não sobrescrevia nada -- resultava em DOIS ícones "Beta Cube
  ; Remote" idênticos. Continua criando só o atalho de "Desinstalar"
  ; (aponta pro NOSSO uninstall.exe, que roda --uninstall nativo E
  ; depois limpa o resto -- ver Section "Uninstall" abaixo -- diferente
  ; do "Uninstall {app_name}.lnk" que o nativo cria sozinho, que só faz
  ; a parte dele).
  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
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

  ; Regra de firewall pro próprio app -- pedido de teste real
  ; (2026-09-23): loja com política de firewall restritiva pode bloquear
  ; o tráfego de saída mesmo sendo o padrão do Windows liberar por conta
  ; própria (GPO/antivírus corporativo pode mudar isso). Regra por
  ; PROGRAMA (não por porta fixa) cobre heartbeat pro bridge (21114) E o
  ; protocolo do RustDesk (21115-21119) de uma vez, sem precisar listar
  ; porta por porta. "dir=in" também, pra sessão remota entrante
  ; funcionar sem prompt do Windows Defender Firewall na primeira vez.
  nsExec::Exec 'netsh advfirewall firewall add rule name="${APP_NAME}" dir=in action=allow program="$INSTDIR\${APP_EXE}" enable=yes'
  nsExec::Exec 'netsh advfirewall firewall add rule name="${APP_NAME}" dir=out action=allow program="$INSTDIR\${APP_EXE}" enable=yes'

  MessageBox MB_OK "Beta Cube Remote instalado com sucesso!$\n$\nO acesso remoto Beta Cube esta pronto.$\nAbra o app e passe o ID para a equipe."
SectionEnd

Section "Uninstall"
  ; --uninstall primeiro (para o serviço, mata o processo, remove driver de
  ; impressora/associação de arquivo -- get_before_uninstall em windows.rs),
  ; DEPOIS o NSIS limpa o que sobrar.
  ExecWait '"$INSTDIR\${APP_EXE}" --uninstall'
  Sleep 2000

  nsExec::Exec 'netsh advfirewall firewall delete rule name="${APP_NAME}"'

  ; /r (recursivo) porque o --install do RustDesk cria arquivos/pastas
  ; próprios dentro de $INSTDIR (data/, drivers/, usbmmidd_v2/, o atalho de
  ; desinstalação dele, etc.) que a gente não lista aqui -- RMDir sem /r
  ; falha silenciosamente se a pasta não estiver vazia, deixando lixo pra trás.
  RMDir /r "$INSTDIR"

  ; Atalho de área de trabalho e o "{app}.lnk" do menu iniciar nunca
  ; foram criados por AQUI (ver comentário na Section principal, acima)
  ; -- são do --install nativo, e o --uninstall nativo (ExecWait acima)
  ; já os removeu. Só o "Desinstalar" é nosso de verdade.
  Delete "$SMPROGRAMS\${APP_NAME}\Desinstalar ${APP_NAME}.lnk"
  RMDir "$SMPROGRAMS\${APP_NAME}"

  DeleteRegKey HKLM "${UNINSTALL_REG}"
SectionEnd
