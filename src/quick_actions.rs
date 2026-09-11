// Beta Cube Remote — Fase 3: Ações Rápidas + sensores/drivers.
//
// Comandos chegam pela resposta do heartbeat (ver src/hbbs_http/sync.rs),
// enfileirados pelo técnico via o betacube-bridge (aba Equipamentos). Cada
// comando roda numa thread bloqueante própria (`spawn_blocking`) — os
// comandos daqui (sfc, DISM, chkdsk) podem levar minutos, e não podem
// travar o loop de heartbeat de 3s. O resultado é reportado de volta pro
// bridge via POST /api/command_result.
//
// Rodando dentro do serviço do Beta Cube Remote (já LocalSystem no
// Windows), então essas ações não pedem prompt de UAC.

use hbb_common::{log, tokio};
use serde::Deserialize;
use serde_json::{json, Value};

#[derive(Debug, Deserialize, Clone)]
pub struct PendingCommand {
    pub id: i64,
    pub action: String,
    #[serde(default)]
    pub params: Value,
}

/// Dispara a execução de um comando e o report do resultado, sem bloquear
/// quem chamou. `heartbeat_url` é usado só pra derivar a URL de report
/// (troca "heartbeat" por "command_result", mesmo padrão já usado pra
/// sysinfo/sysinfo_ver em sync.rs).
pub fn dispatch(cmd: PendingCommand, heartbeat_url: String) {
    tokio::task::spawn_blocking(move || {
        let (status, result) = execute(&cmd);
        let report_url = heartbeat_url.replace("heartbeat", "command_result");
        let body = json!({
            "command_id": cmd.id,
            "status": status,
            "result": result,
        })
        .to_string();
        let handle = tokio::runtime::Handle::current();
        if let Err(e) = handle.block_on(crate::post_request(report_url, body, "")) {
            log::error!(
                "Falha reportando resultado do comando {} ({}): {}",
                cmd.id,
                cmd.action,
                e
            );
        }
    });
}

#[cfg(windows)]
fn execute(cmd: &PendingCommand) -> (String, Value) {
    match cmd.action.as_str() {
        "sfc_scan" => run_capture("sfc", &["/scannow"]),
        "dism_restore_health" => run_capture(
            "DISM",
            &["/Online", "/Cleanup-Image", "/RestoreHealth"],
        ),
        "clear_temp" => clear_temp_and_prefetch(),
        "chkdsk_schedule" => chkdsk_schedule(),
        "reboot_now" => reboot_now(),
        "unstick_printer" => unstick_printer(),
        "restart_services" => restart_services_matching(cmd),
        "disable_defender" => disable_defender(),
        "disable_firewall" => disable_firewall(),
        "list_driver_issues" => list_driver_issues(),
        "list_usb_devices" => list_usb_devices(),
        "reset_printers" => reset_printers(),
        "reset_com_ports" => reset_com_ports(),
        "reinstall_usb_devices" => reinstall_usb_devices(),
        "install_driver" => install_driver(cmd),
        "scan_processos" => scan_processos(),
        "defender_full_scan" => defender_full_scan(),
        "network_http_proxy" => network_http_proxy(cmd),
        other => (
            "failed".to_owned(),
            json!({"error": format!("ação desconhecida: {other}")}),
        ),
    }
}

#[cfg(not(windows))]
fn execute(_cmd: &PendingCommand) -> (String, Value) {
    (
        "failed".to_owned(),
        json!({"error": "Ações Rápidas só implementadas no Windows por agora"}),
    )
}

#[cfg(windows)]
fn run_capture(program: &str, args: &[&str]) -> (String, Value) {
    use std::os::windows::process::CommandExt;
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    match std::process::Command::new(program)
        .args(args)
        .creation_flags(CREATE_NO_WINDOW)
        .output()
    {
        Ok(out) => {
            let stdout = decode_console_bytes(&out.stdout);
            let stderr = decode_console_bytes(&out.stderr);
            let status = if out.status.success() { "done" } else { "failed" };
            (
                status.to_owned(),
                json!({"stdout": stdout, "stderr": stderr, "exit_code": out.status.code()}),
            )
        }
        Err(e) => ("failed".to_owned(), json!({"error": e.to_string()})),
    }
}

/// Ferramentas de console nativas do Windows não são consistentes na
/// codificação da saída quando o stdout é redirecionado (nosso caso, via
/// `Command::output()`) -- três casos reais encontrados testando de
/// verdade (via GET /internal/commands no bridge):
///
/// 1. `sfc /scannow`: UTF-16LE puro, sem BOM. Decodificar como UTF-8
///    (o que a gente fazia antes) produz bytes nulos intercalados --
///    tecnicamente "lossy-válido", mas ilegível.
/// 2. `DISM`: UTF-8 real na maior parte, mas mistura com bytes na code
///    page OEM ativa em alguns trechos (barra de progresso ficava certa,
///    só as palavras acentuadas viravam "�").
/// 3. Praticamente tudo que passa por `run_powershell` já sai em UTF-8
///    direto.
///
/// Por isso tenta em cascata: heurística de UTF-16LE (bytes em posição
/// ímpar majoritariamente 0x00) primeiro; se não bater, tenta UTF-8
/// estrito; se isso falhar (tem byte que não fecha uma sequência UTF-8
/// válida -- exatamente o sintoma do DISM), decodifica via
/// `MultiByteToWideChar`/`GetOEMCP` (API nativa do Windows) usando a code
/// page OEM ATIVA da máquina, em vez de chutar um número fixo (a code
/// page OEM varia por idioma/região -- não dá pra hardcodar 850/860 e
/// funcionar em qualquer instalação).
#[cfg(windows)]
fn decode_console_bytes(bytes: &[u8]) -> String {
    if bytes.len() >= 4 && bytes.len() % 2 == 0 {
        let sample_len = bytes.len().min(64);
        let odd_zero_count = bytes[..sample_len].iter().skip(1).step_by(2).filter(|&&b| b == 0).count();
        let odd_total = sample_len / 2;
        if odd_total > 0 && odd_zero_count * 4 >= odd_total * 3 {
            let u16s: Vec<u16> = bytes.chunks_exact(2).map(|c| u16::from_le_bytes([c[0], c[1]])).collect();
            return String::from_utf16_lossy(&u16s);
        }
    }
    if let Ok(s) = std::str::from_utf8(bytes) {
        return s.to_owned();
    }
    decode_oem_codepage(bytes).unwrap_or_else(|| String::from_utf8_lossy(bytes).to_string())
}

#[cfg(windows)]
fn decode_oem_codepage(bytes: &[u8]) -> Option<String> {
    use winapi::um::stringapiset::MultiByteToWideChar;
    use winapi::um::winnls::GetOEMCP;
    if bytes.is_empty() {
        return Some(String::new());
    }
    unsafe {
        let cp = GetOEMCP();
        let wide_len = MultiByteToWideChar(
            cp,
            0,
            bytes.as_ptr() as *const i8,
            bytes.len() as i32,
            std::ptr::null_mut(),
            0,
        );
        if wide_len <= 0 {
            return None;
        }
        let mut wide: Vec<u16> = vec![0; wide_len as usize];
        let written = MultiByteToWideChar(
            cp,
            0,
            bytes.as_ptr() as *const i8,
            bytes.len() as i32,
            wide.as_mut_ptr(),
            wide_len,
        );
        if written <= 0 {
            return None;
        }
        Some(String::from_utf16_lossy(&wide))
    }
}

#[cfg(windows)]
fn run_powershell(script: &str) -> (String, Value) {
    run_capture("powershell", &["-NoProfile", "-NonInteractive", "-Command", script])
}

#[cfg(windows)]
fn clear_temp_and_prefetch() -> (String, Value) {
    let mut freed_errors = Vec::new();
    let temp = std::env::var("TEMP").unwrap_or_else(|_| "C:\\Windows\\Temp".to_owned());
    for dir in [temp.as_str(), "C:\\Windows\\Prefetch"] {
        if let Ok(entries) = std::fs::read_dir(dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                let res = if path.is_dir() {
                    std::fs::remove_dir_all(&path)
                } else {
                    std::fs::remove_file(&path)
                };
                if let Err(e) = res {
                    // Muitos arquivos temp ficam em uso por outros processos —
                    // isso é esperado, não é uma falha da ação em si.
                    freed_errors.push(format!("{}: {}", path.display(), e));
                }
            }
        }
    }
    (
        "done".to_owned(),
        json!({"skipped_in_use": freed_errors.len(), "details": freed_errors}),
    )
}

#[cfg(windows)]
fn chkdsk_schedule() -> (String, Value) {
    // chkdsk no disco de sistema nunca roda "ao vivo" — sempre agenda pro
    // próximo boot (dirty bit) quando o volume está em uso. "echo Y |" só
    // confirma o prompt de agendamento que o chkdsk faria interativamente.
    use std::os::windows::process::CommandExt;
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    match std::process::Command::new("cmd")
        .args(&["/C", "echo Y| chkdsk C: /r /f /b /x"])
        .creation_flags(CREATE_NO_WINDOW)
        .output()
    {
        Ok(out) => {
            let stdout = String::from_utf8_lossy(&out.stdout).to_string();
            (
                "scheduled".to_owned(),
                json!({"stdout": stdout, "note": "chkdsk agendado pro próximo boot; reinicie a máquina pra rodar"}),
            )
        }
        Err(e) => ("failed".to_owned(), json!({"error": e.to_string()})),
    }
}

#[cfg(windows)]
fn reboot_now() -> (String, Value) {
    run_capture("shutdown", &["/r", "/t", "30", "/c", "Beta Cube Remote: reinicio solicitado pelo suporte"])
}

#[cfg(windows)]
fn unstick_printer() -> (String, Value) {
    // Versão leve: só parar o Spooler, limpar a fila de jobs travados,
    // reiniciar o serviço -- pro caso comum de "um job travou a fila".
    // Pra corrupção de driver de verdade, ver reset_printers() (mais
    // agressivo, remove filas e drivers pra reinstalar do zero).
    let (stop_status, stop_result) = run_capture("net", &["stop", "spooler"]);
    let spool_dir = "C:\\Windows\\System32\\spool\\PRINTERS";
    let mut cleared = 0;
    let mut errors = Vec::new();
    if let Ok(entries) = std::fs::read_dir(spool_dir) {
        for entry in entries.flatten() {
            match std::fs::remove_file(entry.path()) {
                Ok(_) => cleared += 1,
                Err(e) => errors.push(e.to_string()),
            }
        }
    }
    let (start_status, start_result) = run_capture("net", &["start", "spooler"]);
    let status = if start_status == "done" { "done" } else { "failed" };
    (
        status.to_owned(),
        json!({
            "stop": stop_result,
            "cleared_jobs": cleared,
            "clear_errors": errors,
            "start": start_result,
        }),
    )
}

/// "Resetar impressoras" -- não tem driver fixo por loja (Epson TM-T20/
/// T20X/T20X II na maioria dos caixas, mas também Daruma/Bematech
/// dependendo do local), então em vez de tentar adivinhar/escolher qual
/// driver limpar, apaga TUDO (spooler, filas, drivers instalados,
/// inclusive do driver store) e deixa o Windows/o Plug and Play
/// reinstalar do zero na próxima detecção -- mesmo padrão do
/// reset_com_ports() pra porta COM fantasma: agressivo de propósito,
/// funciona pra qualquer marca/modelo.
#[cfg(windows)]
fn reset_printers() -> (String, Value) {
    let (stop_status, stop_result) = run_capture("net", &["stop", "spooler"]);
    let spool_dir = "C:\\Windows\\System32\\spool\\PRINTERS";
    let mut cleared = 0;
    let mut errors = Vec::new();
    if let Ok(entries) = std::fs::read_dir(spool_dir) {
        for entry in entries.flatten() {
            match std::fs::remove_file(entry.path()) {
                Ok(_) => cleared += 1,
                Err(e) => errors.push(e.to_string()),
            }
        }
    }
    let (_, remove_result) = run_powershell(
        "Get-Printer -ErrorAction SilentlyContinue | Remove-Printer -ErrorAction SilentlyContinue; \
         Get-PrinterDriver -ErrorAction SilentlyContinue | Remove-PrinterDriver -ErrorAction SilentlyContinue -RemoveFromDriverStore; \
         'ok' | ConvertTo-Json -Compress",
    );
    let (start_status, start_result) = run_capture("net", &["start", "spooler"]);
    let status = if start_status == "done" { "done" } else { "failed" };
    (
        status.to_owned(),
        json!({
            "stop": stop_result,
            "cleared_jobs": cleared,
            "clear_errors": errors,
            "printers_and_drivers_removed": remove_result,
            "start": start_result,
            "note": "filas e drivers de impressora removidos -- reinstale via Plug and Play ou instalador do fabricante",
        }),
    )
}

/// Porta COM "fantasma" -- comum depois de troca de equipamento USB
/// serial ao longo do tempo (leitora, balança, pinpad, etc.): o Windows
/// mantém reservada a porta COM de um dispositivo que já não está mais
/// conectado, e o novo aparelho acaba numa porta diferente da esperada.
/// Genérico, não depende de saber marca/modelo:
/// 1) Remove os dispositivos da classe "Ports (COM & LPT)" que não estão
///    mais presentes (`pnputil /enum-devices /disconnected`, nativo
///    desde Windows 10 1809 -- sem precisar de devcon.exe).
/// 2) Desabilita e reabilita os dispositivos seriais ATUALMENTE
///    conectados -- equivalente remoto de desconectar/reconectar o
///    cabo, força o Windows a realocar a porta COM do zero.
#[cfg(windows)]
fn reset_com_ports() -> (String, Value) {
    run_powershell(
        "$ghost_out = pnputil /enum-devices /class Ports /disconnected; \
         $ghost_ids = $ghost_out | Select-String 'Instance ID:\\s*(\\S+)' | ForEach-Object { $_.Matches[0].Groups[1].Value }; \
         $removed = foreach ($id in $ghost_ids) { $r = pnputil /remove-device $id 2>&1; @{id=$id; output=($r -join ' ')} }; \
         $present_ids = @(Get-PnpDevice -Class Ports -PresentOnly -ErrorAction SilentlyContinue | Select-Object -ExpandProperty InstanceId); \
         foreach ($id in $present_ids) { Disable-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction SilentlyContinue }; \
         Start-Sleep -Seconds 2; \
         foreach ($id in $present_ids) { Enable-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction SilentlyContinue }; \
         @{ghost_removed=$removed; reconnected=$present_ids} | ConvertTo-Json -Compress -Depth 4",
    )
}

/// Desinstala o driver de todo dispositivo USB atualmente presente
/// (mesma classe usada por `list_usb_devices`) e força o Windows a
/// redetectar e reinstalar -- problema recorrente nas lojas com
/// periféricos USB (leitor, pinpad, etc.) que "somem"/param sem um
/// motivo aparente e voltam depois de um uninstall+rescan manual.
/// Separado do `reset_com_ports`: ali é porta serial fantasma, aqui é o
/// dispositivo USB em si, presente ou não.
#[cfg(windows)]
fn reinstall_usb_devices() -> (String, Value) {
    run_powershell(
        "$present_ids = @(Get-PnpDevice -Class USB -PresentOnly -ErrorAction SilentlyContinue | Select-Object -ExpandProperty InstanceId); \
         $removed = foreach ($id in $present_ids) { $r = pnputil /remove-device $id 2>&1; @{id=$id; output=($r -join ' ')} }; \
         Start-Sleep -Seconds 2; \
         $rescan = pnputil /scan-devices 2>&1; \
         @{removed=$removed; rescan=($rescan -join ' ')} | ConvertTo-Json -Compress -Depth 4",
    )
}

/// Reinicia serviço(s) Windows encontrados por nome, porta ouvida, ou
/// substring da linha de comando do processo — os 3 critérios são
/// combináveis, um "match" em qualquer um já entra na lista.
///
/// "restart_tomcat"/"restart_sitef" usam `name_contains` (nome sabido).
/// "restart_tcserver" (Gertec, roda como java.exe — nome de processo não
/// identifica nada) usa `port` e/ou `cmdline_contains`, já que múltiplas
/// JVMs podem estar rodando na máquina e só uma é o TC Server.
///
/// Escopo estritamente "tá rodando? religa se não" — sem tocar em config
/// de conexão com banco/tabela de preço (isso é território do Datamax,
/// fora do nosso escopo).
#[cfg(windows)]
fn restart_services_matching(cmd: &PendingCommand) -> (String, Value) {
    let name_patterns: Vec<String> = cmd
        .params
        .get("name_contains")
        .and_then(|v| v.as_array())
        .map(|arr| arr.iter().filter_map(|v| v.as_str().map(|s| s.to_lowercase())).collect())
        .unwrap_or_default();
    let port = cmd.params.get("port").and_then(|v| v.as_i64());
    let cmdline_pattern = cmd
        .params
        .get("cmdline_contains")
        .and_then(|v| v.as_str())
        .map(|s| s.to_lowercase());

    if name_patterns.is_empty() && port.is_none() && cmdline_pattern.is_none() {
        return (
            "failed".to_owned(),
            json!({"error": "nenhum critério informado (name_contains/port/cmdline_contains)"}),
        );
    }

    // Some services are only ever known by their Display Name in
    // services.msc (e.g. SITEF's "WNB Monitor" / "WNB TLS Client") --
    // the internal `Name` can be something entirely different and
    // unguessable from the outside. Fetch both and match against either,
    // so a button built from what a technician actually sees on screen
    // still works even if nobody's confirmed the real Name.
    let (status, dump) = run_powershell(
        "$services = Get-CimInstance Win32_Service | Where-Object { $_.ProcessId -ne 0 } | Select-Object Name,DisplayName,ProcessId; \
         $processes = Get-CimInstance Win32_Process | Select-Object ProcessId,CommandLine; \
         $listening = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Select-Object LocalPort,OwningProcess; \
         @{services=$services; processes=$processes; listening=$listening} | ConvertTo-Json -Depth 4 -Compress",
    );
    if status != "done" {
        return (status, dump);
    }
    let parsed: Value = match dump
        .get("stdout")
        .and_then(|s| s.as_str())
        .and_then(|s| serde_json::from_str(s).ok())
    {
        Some(v) => v,
        None => return ("failed".to_owned(), json!({"error": "falha ao interpretar saída do PowerShell"})),
    };
    let as_vec = |key: &str| -> Vec<Value> {
        match parsed.get(key) {
            Some(Value::Array(arr)) => arr.clone(),
            Some(other) => vec![other.clone()],
            None => Vec::new(),
        }
    };
    let services = as_vec("services");
    let processes = as_vec("processes");
    let listening = as_vec("listening");

    let mut matched_pids: std::collections::HashSet<i64> = std::collections::HashSet::new();
    if let Some(port) = port {
        for l in &listening {
            if l.get("LocalPort").and_then(|v| v.as_i64()) == Some(port) {
                if let Some(pid) = l.get("OwningProcess").and_then(|v| v.as_i64()) {
                    matched_pids.insert(pid);
                }
            }
        }
    }
    if let Some(pattern) = &cmdline_pattern {
        for p in &processes {
            let cmdline_match = p
                .get("CommandLine")
                .and_then(|v| v.as_str())
                .map(|cl| cl.to_lowercase().contains(pattern.as_str()))
                .unwrap_or(false);
            if cmdline_match {
                if let Some(pid) = p.get("ProcessId").and_then(|v| v.as_i64()) {
                    matched_pids.insert(pid);
                }
            }
        }
    }

    let matched: Vec<String> = services
        .iter()
        .filter_map(|s| {
            let name = s.get("Name").and_then(|v| v.as_str())?;
            let display_name = s.get("DisplayName").and_then(|v| v.as_str()).unwrap_or("");
            let pid = s.get("ProcessId").and_then(|v| v.as_i64());
            let name_lower = name.to_lowercase();
            let display_lower = display_name.to_lowercase();
            let name_match = !name_patterns.is_empty()
                && name_patterns
                    .iter()
                    .any(|p| name_lower.contains(p) || display_lower.contains(p));
            let pid_match = pid.map_or(false, |pid| matched_pids.contains(&pid));
            (name_match || pid_match).then(|| name.to_owned())
        })
        .collect();

    if matched.is_empty() {
        let note = if matched_pids.is_empty() {
            "nenhum serviço ou processo encontrado (checado por Name, DisplayName, porta e linha de comando) — parece parado; sem nome confirmado, não dá pra iniciar automaticamente"
        } else {
            "processo encontrado (por porta/linha de comando) mas não é um serviço Windows registrado — não dá pra reiniciar sem saber o comando de inicialização"
        };
        return (
            "failed".to_owned(),
            json!({"error": note, "name_contains": name_patterns, "port": port}),
        );
    }

    let mut per_service = Vec::new();
    for name in &matched {
        let (_, restart_out) = run_powershell(&format!("Restart-Service -Name '{name}' -Force"));
        per_service.push(json!({"service": name, "result": restart_out}));
    }
    ("done".to_owned(), json!({"matched": matched, "results": per_service}))
}

#[cfg(windows)]
fn disable_defender() -> (String, Value) {
    // A confirmação explícita já acontece no Flutter antes de enfileirar
    // esse comando — aqui só executa.
    run_powershell("Set-MpPreference -DisableRealtimeMonitoring $true")
}

#[cfg(windows)]
fn disable_firewall() -> (String, Value) {
    run_capture(
        "netsh",
        &["advfirewall", "set", "allprofiles", "state", "off"],
    )
}

#[cfg(windows)]
fn list_driver_issues() -> (String, Value) {
    run_powershell(
        "Get-PnpDevice -Status Error | Select-Object FriendlyName,InstanceId,ConfigManagerErrorCode | ConvertTo-Json",
    )
}

#[cfg(windows)]
fn list_usb_devices() -> (String, Value) {
    run_powershell(
        "Get-PnpDevice -Class USB -PresentOnly | Select-Object FriendlyName,InstanceId,Status | ConvertTo-Json",
    )
}

/// Baixa um driver do "pacote" hospedado no próprio betacube-bridge
/// (estático, em `{api-server}/drivers/{filename}` -- ver
/// GET /internal/drivers no bridge pra listar o que tem disponível) e
/// abre o instalador. NÃO tenta instalar silenciosamente: instaladores de
/// driver variam demais entre fabricantes pra ter uma flag silenciosa
/// confiável e universal, e o técnico já está olhando a tela remota via
/// RustDesk nesse exato momento -- é mais simples e confiável deixar ele
/// clicar o wizard normalmente.
///
/// O serviço roda como LocalSystem (Session 0) -- lançar o instalador
/// direto de lá o deixaria invisível (ninguém tem uma área de trabalho na
/// sessão 0). Por isso usa `run_exe_in_session` pra abrir na sessão do
/// console ATIVO (a do usuário logado / compartilhada por RDP, mesmo
/// critério que o próprio RustDesk usa pra decidir onde lançar sua UI).
#[cfg(windows)]
fn install_driver(cmd: &PendingCommand) -> (String, Value) {
    let filename = match cmd.params.get("filename").and_then(|v| v.as_str()) {
        Some(f) if !f.is_empty() => f,
        _ => {
            return (
                "failed".to_owned(),
                json!({"error": "filename é obrigatório"}),
            )
        }
    };
    let base = crate::common::get_api_server(
        hbb_common::config::Config::get_option("api-server"),
        hbb_common::config::Config::get_option("custom-rendezvous-server"),
    );
    if base.is_empty() {
        return (
            "failed".to_owned(),
            json!({"error": "api-server não configurado"}),
        );
    }

    let url = format!("{}/drivers/{}", base, filename);
    let dest = std::env::temp_dir().join(filename);
    let dest_str = dest.to_string_lossy().to_string();
    let (dl_status, dl_result) = run_powershell(&format!(
        "Invoke-WebRequest -Uri '{}' -OutFile '{}' -UseBasicParsing",
        url.replace('\'', "''"),
        dest_str.replace('\'', "''"),
    ));
    if dl_status != "done" || !dest.exists() {
        return (
            "failed".to_owned(),
            json!({"error": "falha no download", "url": url, "detail": dl_result}),
        );
    }

    let session_id = crate::platform::windows::get_current_session_id(
        crate::platform::windows::is_share_rdp(),
    );
    match crate::platform::windows::run_exe_in_session(&dest_str, vec![], session_id, true) {
        Ok(_) => (
            "done".to_owned(),
            json!({"downloaded_to": dest_str, "launched_in_session": session_id}),
        ),
        Err(e) => (
            "failed".to_owned(),
            json!({"downloaded_to": dest_str, "launch_error": e.to_string()}),
        ),
    }
}

// --- Fase 2 do roadmap: antivírus em camadas -----------------------------
//
// Processos rodando são hasheados (SHA-256) AQUI no cliente -- a chave do
// VirusTotal NUNCA fica no binário distribuído (extraível via strings),
// então quem bate nas APIs externas (CIRCL/MalwareBazaar/VirusTotal) é o
// bridge, com a chave só em .env (mesmo padrão do TELEGRAM_BOT_TOKEN).
// Este arquivo só coleta hash + nome + caminho e reporta -- nunca decide
// sozinho apagar/quarentenar nada (só alerta).

/// Processos e pastas do sistema Windows -- nunca faz sentido hashear
/// (portado de PROCESSOS_SISTEMA/PASTAS_SISTEMA em
/// C:\projetos\Beta Cube Monitor\security_scanner.py).
#[cfg(windows)]
const PROCESSOS_SISTEMA: &[&str] = &[
    "System", "Registry", "smss.exe", "csrss.exe", "wininit.exe",
    "winlogon.exe", "services.exe", "lsass.exe", "fontdrvhost.exe",
    "dwm.exe", "conhost.exe", "svchost.exe", "spoolsv.exe",
    "taskhostw.exe", "sihost.exe", "RuntimeBroker.exe", "SearchHost.exe",
    "StartMenuExperienceHost.exe", "TextInputHost.exe", "ShellExperienceHost.exe",
    "explorer.exe", "ctfmon.exe", "dllhost.exe", "WmiPrvSE.exe",
    "MsMpEng.exe", "NisSrv.exe", "SecurityHealthService.exe",
    "audiodg.exe", "wlanext.exe", "dasHost.exe", "LSM.exe",
];

#[cfg(windows)]
const PASTAS_SISTEMA: &[&str] = &[
    "c:\\windows\\system32",
    "c:\\windows\\syswow64",
    "c:\\windows\\winsxs",
    "c:\\program files\\windows defender",
    "c:\\program files\\microsoft",
    "c:\\program files (x86)\\microsoft",
];

#[cfg(windows)]
fn eh_pasta_sistema(caminho: &str) -> bool {
    let lower = caminho.to_lowercase();
    PASTAS_SISTEMA.iter().any(|p| lower.starts_with(p))
}

#[cfg(windows)]
fn sha256_arquivo(caminho: &str) -> Option<String> {
    use sha2::{Digest, Sha256};
    let bytes = std::fs::read(caminho).ok()?;
    let mut hasher = Sha256::new();
    hasher.update(&bytes);
    Some(format!("{:x}", hasher.finalize()))
}

/// Lista processos rodando (via `Get-CimInstance Win32_Process`, mesmo
/// padrão já usado em `restart_services_matching`), pula processo/pasta
/// de sistema, hasheia o executável de cada um que sobrar.
#[cfg(windows)]
fn scan_processos_hashes() -> Option<Vec<Value>> {
    let (status, out) = run_powershell(
        "Get-CimInstance Win32_Process | Select-Object Name,ExecutablePath | ConvertTo-Json -Compress",
    );
    if status != "done" {
        return None;
    }
    let parsed: Value = out
        .get("stdout")
        .and_then(|s| s.as_str())
        .and_then(|s| serde_json::from_str(s).ok())?;
    let items: Vec<Value> = match parsed {
        Value::Array(arr) => arr,
        other => vec![other],
    };
    let mut result = Vec::new();
    let mut vistos = std::collections::HashSet::new();
    for item in items {
        let name = item.get("Name").and_then(|v| v.as_str()).unwrap_or("");
        let path = match item.get("ExecutablePath").and_then(|v| v.as_str()) {
            Some(p) if !p.is_empty() => p,
            _ => continue,
        };
        if PROCESSOS_SISTEMA.iter().any(|s| s.eq_ignore_ascii_case(name)) {
            continue;
        }
        if eh_pasta_sistema(path) {
            continue;
        }
        // O mesmo executável costuma aparecer em várias instâncias
        // (múltiplos processos do mesmo programa) -- hasheia só uma vez.
        if !vistos.insert(path.to_lowercase()) {
            continue;
        }
        if let Some(hash) = sha256_arquivo(path) {
            result.push(json!({"sha256": hash, "nome": name, "caminho": path}));
        }
    }
    Some(result)
}

/// Ação Rápida manual: mesma coleta do loop, mas dispara na hora e
/// reporta pro bridge (`POST /api/check_hashes`) de dentro da própria
/// ação -- mesmo padrão de `handle.block_on(...)` já usado em
/// `dispatch()` pra reportar resultado de comando.
#[cfg(windows)]
fn scan_processos() -> (String, Value) {
    let hashes = match scan_processos_hashes() {
        Some(h) => h,
        None => return ("failed".to_owned(), json!({"error": "falha ao listar processos"})),
    };
    if hashes.is_empty() {
        return (
            "done".to_owned(),
            json!({"checked": 0, "note": "nenhum processo fora da lista de confiança encontrado"}),
        );
    }
    let base = crate::common::get_api_server(
        hbb_common::config::Config::get_option("api-server"),
        hbb_common::config::Config::get_option("custom-rendezvous-server"),
    );
    if base.is_empty() {
        return (
            "failed".to_owned(),
            json!({"error": "api-server não configurado"}),
        );
    }
    let id = hbb_common::config::Config::get_id();
    let checked = hashes.len();
    let body = json!({"id": id, "files": hashes}).to_string();
    let url = format!("{}/api/check_hashes", base);
    let handle = tokio::runtime::Handle::current();
    match handle.block_on(crate::post_request(url, body, "")) {
        Ok(resp) => ("done".to_owned(), json!({"checked": checked, "bridge_response": resp})),
        Err(e) => ("failed".to_owned(), json!({"error": e.to_string()})),
    }
}

/// Camada 0 (grátis) do antivírus em camadas: scan completo do próprio
/// Windows Defender, usando o motor da Microsoft já instalado -- sem
/// custo, sem limite de chamada, sem subir arquivo pra lugar nenhum.
/// Diferente de scan_processos (que só REPORTA), aqui o Defender faz a
/// remediação normal dele (decide sozinho o que quarentenar) -- é
/// antivírus de verdade, não é nosso código decidindo apagar algo.
/// Portado de windows_defender_scan.py.
#[cfg(windows)]
fn localizar_mpcmdrun() -> Option<String> {
    let base = r"C:\ProgramData\Microsoft\Windows Defender\Platform";
    let mut versoes: Vec<String> = std::fs::read_dir(base)
        .ok()?
        .filter_map(|e| e.ok())
        .filter(|e| e.path().is_dir())
        .map(|e| e.file_name().to_string_lossy().to_string())
        .collect();
    versoes.sort();
    if let Some(ultima) = versoes.last() {
        let candidato = format!("{}\\{}\\MpCmdRun.exe", base, ultima);
        if std::path::Path::new(&candidato).exists() {
            return Some(candidato);
        }
    }
    let fallback = r"C:\Program Files\Windows Defender\MpCmdRun.exe";
    if std::path::Path::new(fallback).exists() {
        return Some(fallback.to_owned());
    }
    None
}

#[cfg(windows)]
fn defender_full_scan() -> (String, Value) {
    let Some(mpcmdrun) = localizar_mpcmdrun() else {
        return (
            "failed".to_owned(),
            json!({"error": "MpCmdRun.exe não encontrado -- Windows Defender pode estar desativado ou substituído por outro antivírus"}),
        );
    };
    // Scan completo pode levar horas num disco grande -- roda do mesmo
    // jeito que sfc/DISM (bloqueia dentro do spawn_blocking já usado por
    // dispatch(), sem timeout artificial nosso).
    run_capture(&mpcmdrun, &["-Scan", "-ScanType", "2"])
}

/// Fase 6 (rede): "proxy burro" pro bridge. Controladores UniFi/Omada/
/// roteadores Mikrotik das lojas ficam na LAN local -- o bridge, hospedado
/// na internet, não os alcança sem VPN/port-forward por loja (ver decisão
/// de arquitetura no plano da Fase 6). Em vez disso, o bridge monta a
/// chamada HTTP inteira (URL, headers, autenticação de cada fabricante) e
/// manda pra cá; este agente só executa, na mesma LAN do equipamento, e
/// devolve status/headers/body sem interpretar nada. Nenhuma credencial de
/// rede é conhecida ou fica guardada neste processo.
#[cfg(windows)]
fn network_http_proxy(cmd: &PendingCommand) -> (String, Value) {
    let method = cmd
        .params
        .get("method")
        .and_then(|v| v.as_str())
        .unwrap_or("GET")
        .to_uppercase();
    let method = match reqwest::Method::from_bytes(method.as_bytes()) {
        Ok(m) => m,
        Err(_) => return ("failed".to_owned(), json!({"error": format!("método HTTP inválido: {method}")})),
    };
    let url = match cmd.params.get("url").and_then(|v| v.as_str()) {
        Some(u) if !u.is_empty() => u.to_owned(),
        _ => return ("failed".to_owned(), json!({"error": "url é obrigatória"})),
    };
    let headers: Vec<(String, String)> = cmd
        .params
        .get("headers")
        .and_then(|v| v.as_object())
        .map(|m| {
            m.iter()
                .filter_map(|(k, v)| v.as_str().map(|s| (k.clone(), s.to_owned())))
                .collect()
        })
        .unwrap_or_default();
    let body = cmd
        .params
        .get("body")
        .and_then(|v| v.as_str())
        .map(|s| s.to_owned());
    // Controladores/roteadores de loja costumam ter certificado
    // auto-assinado (ver plano da Fase 6, seção Mikrotik) -- não dá pra
    // validar CA de verdade numa frota assim, e a conexão real já passa
    // pela LAN da própria loja, não pela internet exposta.
    let insecure_tls = cmd
        .params
        .get("insecure_tls")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    let handle = tokio::runtime::Handle::current();
    let result: Result<(u16, serde_json::Map<String, Value>, String), String> = handle.block_on(async move {
        let client = crate::hbbs_http::create_http_client_async(
            hbb_common::tls::TlsType::Rustls,
            insecure_tls,
        );
        let mut req = client.request(method, url.as_str());
        for (k, v) in &headers {
            req = req.header(k, v);
        }
        if let Some(b) = body {
            req = req.body(b);
        }
        let resp = req
            .timeout(std::time::Duration::from_secs(20))
            .send()
            .await
            .map_err(|e| e.to_string())?;
        let status = resp.status().as_u16();
        let resp_headers: serde_json::Map<String, Value> = resp
            .headers()
            .iter()
            .filter_map(|(k, v)| v.to_str().ok().map(|s| (k.to_string(), json!(s))))
            .collect();
        let resp_body = resp.text().await.unwrap_or_default();
        Ok((status, resp_headers, resp_body))
    });

    match result {
        Ok((status, headers, body)) => (
            "done".to_owned(),
            json!({"status": status, "headers": headers, "body": body}),
        ),
        Err(e) => ("failed".to_owned(), json!({"error": e})),
    }
}

// --- Loop periódico de sensores/drivers (relatado pro bridge, não vem de comando) ---

const SENSOR_REPORT_INTERVAL: std::time::Duration = std::time::Duration::from_secs(60);

// disk_health/power_health/windows_health (Fase C -- portado do BetaCube
// Monitor, ver disk_health.py/power_health.py/windows_health.py) usam
// Get-WinEvent/Get-Service, mais pesados que ler sensor de hardware e sem
// necessidade da mesma cadência (nenhum desses muda em segundos) -- roda
// só a cada N ciclos do loop rápido de 60s, não em todo tick.
const EXTENDED_CHECK_EVERY_N_TICKS: u64 = 5; // ~5 min

#[cfg(windows)]
pub fn start_sensor_loop() {
    std::thread::spawn(sensor_loop_async);
}

#[cfg(not(windows))]
pub fn start_sensor_loop() {}

#[cfg(windows)]
struct CollectedSignals {
    sensors: Option<Value>,
    driver_issues: Option<Value>,
    disk_health: Option<Value>,
    power_health: Option<Value>,
    windows_health: Option<Value>,
    // Fase 2 (antivírus) -- só coletado no tick estendido, mesmo motivo
    // de disk/power/windows_health (hashear todo processo a cada 60s
    // seria custo/ruído desnecessário).
    process_hashes: Option<Vec<Value>>,
    // Fase 5 (tela de informações estilo AIDA64) -- mesmo motivo, tick
    // estendido só.
    system_info: Option<Value>,
}

#[cfg(windows)]
#[tokio::main(flavor = "current_thread")]
async fn sensor_loop_async() {
    let mut interval = tokio::time::interval(SENSOR_REPORT_INTERVAL);
    let mut tick: u64 = 0;
    loop {
        interval.tick().await;
        let url = crate::common::get_api_server(
            hbb_common::config::Config::get_option("api-server"),
            hbb_common::config::Config::get_option("custom-rendezvous-server"),
        );
        if url.is_empty() || crate::is_public(&url) {
            continue;
        }
        let id = hbb_common::config::Config::get_id();
        let uuid = crate::encode64(hbb_common::get_uuid());
        let run_extended = tick % EXTENDED_CHECK_EVERY_N_TICKS == 0;
        tick = tick.wrapping_add(1);

        let signals = match tokio::task::spawn_blocking(move || collect_all_signals(run_extended)).await {
            Ok(x) => x,
            Err(_) => CollectedSignals {
                sensors: None,
                driver_issues: None,
                disk_health: None,
                power_health: None,
                windows_health: None,
                process_hashes: None,
                system_info: None,
            },
        };
        // Item 3 (teste real nas lojas 2026-09-11): "Online" no Equipment
        // hoje só significa "esse POST chegou" -- não diz nada sobre se o
        // servidor de ID/rendezvous do RustDesk considera esta máquina
        // alcançável pra sessão remota (o que decide se o botão Conectar
        // funciona). São dois sinais de fato diferentes; manda os dois.
        let last_register_ok_ms = crate::rendezvous_mediator::last_register_ok_ms();
        let now_ms = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis() as i64)
            .unwrap_or(0);
        // Folga generosa sobre o intervalo de re-registro (15s) pra não
        // marcar "não alcançável" por jitter normal de rede.
        let rendezvous_reachable =
            last_register_ok_ms > 0 && (now_ms - last_register_ok_ms) < 45_000;

        let body = json!({
            "id": id,
            "uuid": uuid,
            "sensors": signals.sensors,
            "driver_issues": signals.driver_issues,
            "disk_health": signals.disk_health,
            "power_health": signals.power_health,
            "windows_health": signals.windows_health,
            "rendezvous_reachable": rendezvous_reachable,
            "system_info": signals.system_info,
        })
        .to_string();
        let sensors_url = format!("{}/api/sensors", url);
        if let Err(e) = crate::post_request(sensors_url, body, "").await {
            log::error!("Falha reportando sensores: {}", e);
        }

        if let Some(hashes) = signals.process_hashes {
            if !hashes.is_empty() {
                let hashes_body = json!({"id": id, "files": hashes}).to_string();
                let hashes_url = format!("{}/api/check_hashes", url);
                if let Err(e) = crate::post_request(hashes_url, hashes_body, "").await {
                    log::error!("Falha reportando hashes de processo: {}", e);
                }
            }
        }
    }
}

#[cfg(windows)]
fn collect_all_signals(run_extended: bool) -> CollectedSignals {
    let sensors = read_hw_sensors();
    let (status, result) = list_driver_issues();
    let driver_issues = if status == "done" {
        result
            .get("stdout")
            .and_then(|s| s.as_str())
            .filter(|s| !s.trim().is_empty())
            .and_then(|s| serde_json::from_str::<Value>(s).ok())
    } else {
        None
    };
    if !run_extended {
        return CollectedSignals {
            sensors,
            driver_issues,
            disk_health: None,
            power_health: None,
            windows_health: None,
            process_hashes: None,
            system_info: None,
        };
    }
    CollectedSignals {
        sensors,
        driver_issues,
        disk_health: collect_disk_health(),
        power_health: collect_power_health(),
        windows_health: collect_windows_health(),
        process_hashes: scan_processos_hashes(),
        system_info: collect_system_info(),
    }
}

/// Saúde nativa de disco via Windows Storage (sem smartctl/terceiros) --
/// portado de disk_health.py. HealthStatus já reflete o que o firmware do
/// disco reporta via SMART; Wear/ReadErrorsUncorrected/WriteErrorsUncorrected
/// vêm de Get-StorageReliabilityCounter (nativo desde Windows 8/Server 2012).
#[cfg(windows)]
fn collect_disk_health() -> Option<Value> {
    let (status, out) = run_powershell(
        "$discos = Get-PhysicalDisk | Select-Object DeviceId,FriendlyName,HealthStatus,OperationalStatus,MediaType,Size; \
         $contadores = Get-PhysicalDisk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue | \
         Select-Object DeviceId,Wear,ReadErrorsUncorrected,WriteErrorsUncorrected,Temperature,PowerOnHours; \
         @{discos=$discos; contadores=$contadores} | ConvertTo-Json -Compress -Depth 4",
    );
    if status != "done" {
        return None;
    }
    let parsed: Value = out
        .get("stdout")
        .and_then(|s| s.as_str())
        .and_then(|s| serde_json::from_str(s).ok())?;
    let as_vec = |key: &str| -> Vec<Value> {
        match parsed.get(key) {
            Some(Value::Array(arr)) => arr.clone(),
            Some(other) => vec![other.clone()],
            None => Vec::new(),
        }
    };
    let discos = as_vec("discos");
    let contadores = as_vec("contadores");
    let find_counter = |device_id: &Value| -> Option<&Value> {
        contadores
            .iter()
            .find(|c| c.get("DeviceId").map(|v| v.to_string()) == Some(device_id.to_string()))
    };

    let merged: Vec<Value> = discos
        .iter()
        .map(|d| {
            let empty = json!({});
            let c = d
                .get("DeviceId")
                .and_then(|id| find_counter(id))
                .unwrap_or(&empty);
            json!({
                "name": d.get("FriendlyName"),
                "health": d.get("HealthStatus"),
                "operational_status": d.get("OperationalStatus"),
                "media_type": d.get("MediaType"),
                "size_gb": d.get("Size").and_then(|v| v.as_f64()).map(|b| (b / 1e9 * 10.0).round() / 10.0),
                "wear_pct": c.get("Wear"),
                "read_errors_uncorrected": c.get("ReadErrorsUncorrected"),
                "write_errors_uncorrected": c.get("WriteErrorsUncorrected"),
                "temperature": c.get("Temperature"),
                "power_on_hours": c.get("PowerOnHours"),
            })
        })
        .collect();
    Some(Value::Array(merged))
}

/// Sinais de problema elétrico -- portado de power_health.py. Event ID 41
/// (Kernel-Power) é gravado quando o Windows liga de novo depois de ter
/// sido desligado sem receber o sinal normal de shutdown (queda de energia
/// ou travamento duro). Win32_Battery cobre nobreak/UPS reconhecido via USB
/// (BatteryStatus 1 = rodando na bateria agora, ou seja, sem energia da
/// rede neste momento).
#[cfg(windows)]
fn collect_power_health() -> Option<Value> {
    let (status, out) = run_powershell(
        "$eventos = Get-WinEvent -FilterHashtable @{LogName='System'; Id=41; StartTime=(Get-Date).AddDays(-1)} -ErrorAction SilentlyContinue | \
         Select-Object TimeCreated; \
         $baterias = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | \
         Select-Object Name,BatteryStatus,EstimatedChargeRemaining,EstimatedRunTime; \
         @{eventos=$eventos; baterias=$baterias} | ConvertTo-Json -Compress -Depth 4",
    );
    if status != "done" {
        return None;
    }
    out.get("stdout")
        .and_then(|s| s.as_str())
        .and_then(|s| serde_json::from_str(s).ok())
}

/// Saúde geral do Windows -- portado de windows_health.py. Fica de fora,
/// de propósito, a checagem de updates pendentes via
/// Microsoft.Update.Session (o método real, usado no BetaCube Monitor):
/// ela bate no serviço de Windows Update e pode levar mais de um minuto,
/// pesado demais pra rodar a cada ciclo. `reboot_pending` é um proxy bem
/// mais barato (só lê 2 chaves de registro) que cobre o caso mais comum
/// (reinicialização pendente por update já instalado).
#[cfg(windows)]
fn collect_windows_health() -> Option<Value> {
    let (status, out) = run_powershell(
        "$erros = (Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=(Get-Date).AddHours(-24)} -ErrorAction SilentlyContinue | Measure-Object).Count; \
         $servicos = @('wuauserv','WinDefend','Dnscache','BITS','EventLog','RpcSs') | ForEach-Object { \
             $s = Get-Service -Name $_ -ErrorAction SilentlyContinue; \
             if ($s -and $s.Status -ne 'Running') { $s.Name } \
         }; \
         $discos_criticos = Get-PSDrive -PSProvider FileSystem | Where-Object { ($_.Used + $_.Free) -gt 0 -and ($_.Free / ($_.Used + $_.Free)) -lt 0.10 } | \
             ForEach-Object { @{drive=$_.Name; free_gb=[math]::Round($_.Free/1e9,1); pct_used=[math]::Round(100*$_.Used/($_.Used+$_.Free),1)} }; \
         $reboot_pending = (Test-Path 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Component Based Servicing\\RebootPending') -or \
             (Test-Path 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\WindowsUpdate\\Auto Update\\RebootRequired'); \
         @{critical_events_24h=$erros; stopped_services=@($servicos); disks_low_space=@($discos_criticos); reboot_pending=$reboot_pending} | ConvertTo-Json -Compress -Depth 4",
    );
    if status != "done" {
        return None;
    }
    out.get("stdout")
        .and_then(|s| s.as_str())
        .and_then(|s| serde_json::from_str(s).ok())
}

/// Tela de informações do sistema estilo AIDA64 (Fase 5) -- não dá pra
/// embutir o AIDA64 real (pago, fechado), então completa via WMI o que já
/// não vem do `sysinfo`/`hwsensor-helper` (CPU/RAM/nomes de GPU e disco):
/// placa-mãe, monitor(es), dispositivo(s) de áudio e adaptador(es) de rede.
/// Roda só no tick estendido (mesmo motivo de disk/power/windows_health):
/// nada disso muda em segundos.
#[cfg(windows)]
fn collect_system_info() -> Option<Value> {
    let (status, out) = run_powershell(
        "$placa_mae = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue | \
             Select-Object Manufacturer,Product,SerialNumber; \
         $monitores = Get-CimInstance Win32_DesktopMonitor -ErrorAction SilentlyContinue | \
             Select-Object Name,ScreenWidth,ScreenHeight; \
         $audio = Get-CimInstance Win32_SoundDevice -ErrorAction SilentlyContinue | \
             Select-Object Name,Manufacturer,Status; \
         $rede = Get-CimInstance Win32_NetworkAdapter -Filter 'PhysicalAdapter=True' -ErrorAction SilentlyContinue | \
             Select-Object Name,MACAddress,NetConnectionStatus,Speed; \
         @{placa_mae=$placa_mae; monitores=$monitores; audio=$audio; rede=$rede} | ConvertTo-Json -Compress -Depth 4",
    );
    if status != "done" {
        return None;
    }
    out.get("stdout")
        .and_then(|s| s.as_str())
        .and_then(|s| serde_json::from_str(s).ok())
}

/// Roda o `hwsensor-helper.exe` (empacotado do lado do exe principal, ver
/// native/hwsensor-helper/) e devolve só o array de sensores — o helper
/// nunca falha "alto", ausência de sensor (ex: sem elevação, hardware sem
/// suporte) só resulta em None/lista vazia.
#[cfg(windows)]
fn read_hw_sensors() -> Option<Value> {
    let exe_path = std::env::current_exe().ok()?;
    let helper_path = exe_path.parent()?.join("hwsensor-helper.exe");
    if !helper_path.exists() {
        return None;
    }
    use std::os::windows::process::CommandExt;
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    let out = std::process::Command::new(helper_path)
        .creation_flags(CREATE_NO_WINDOW)
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let parsed: Value = serde_json::from_slice(&out.stdout).ok()?;
    parsed.get("sensors").cloned()
}
