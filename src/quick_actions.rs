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
            let stdout = String::from_utf8_lossy(&out.stdout).to_string();
            let stderr = String::from_utf8_lossy(&out.stderr).to_string();
            let status = if out.status.success() { "done" } else { "failed" };
            (
                status.to_owned(),
                json!({"stdout": stdout, "stderr": stderr, "exit_code": out.status.code()}),
            )
        }
        Err(e) => ("failed".to_owned(), json!({"error": e.to_string()})),
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
    // Só a parte segura: parar o Spooler, limpar a fila de jobs travados,
    // reiniciar o serviço. NÃO limpa HKLM\SYSTEM\CurrentControlSet\Control\Print
    // (registro de drivers) aqui — apagar a chave errada remove o registro
    // de TODOS os drivers de impressora instalados, não só o travado.
    // Deixado de fora até confirmar com o usuário qual sub-chave exata
    // precisa ser limpa pro cenário específico dele.
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
            "note": "limpeza de chave de registro de driver NÃO incluída (risco de afetar outras impressoras) — ver plano",
        }),
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

    let (status, dump) = run_powershell(
        "$services = Get-CimInstance Win32_Service | Where-Object { $_.ProcessId -ne 0 } | Select-Object Name,ProcessId; \
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
            let pid = s.get("ProcessId").and_then(|v| v.as_i64());
            let name_match = !name_patterns.is_empty() && name_patterns.iter().any(|p| name.to_lowercase().contains(p));
            let pid_match = pid.map_or(false, |pid| matched_pids.contains(&pid));
            (name_match || pid_match).then(|| name.to_owned())
        })
        .collect();

    if matched.is_empty() {
        let note = if matched_pids.is_empty() {
            "nenhum serviço ou processo encontrado — parece parado; sem nome de serviço confirmado, não dá pra iniciar automaticamente"
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

// --- Loop periódico de sensores/drivers (relatado pro bridge, não vem de comando) ---

const SENSOR_REPORT_INTERVAL: std::time::Duration = std::time::Duration::from_secs(60);

#[cfg(windows)]
pub fn start_sensor_loop() {
    std::thread::spawn(sensor_loop_async);
}

#[cfg(not(windows))]
pub fn start_sensor_loop() {}

#[cfg(windows)]
#[tokio::main(flavor = "current_thread")]
async fn sensor_loop_async() {
    let mut interval = tokio::time::interval(SENSOR_REPORT_INTERVAL);
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
        let (sensors, driver_issues) = match tokio::task::spawn_blocking(collect_sensors_and_drivers).await {
            Ok(x) => x,
            Err(_) => (None, None),
        };
        let body = json!({
            "id": id,
            "uuid": uuid,
            "sensors": sensors,
            "driver_issues": driver_issues,
        })
        .to_string();
        let sensors_url = format!("{}/api/sensors", url);
        if let Err(e) = crate::post_request(sensors_url, body, "").await {
            log::error!("Falha reportando sensores: {}", e);
        }
    }
}

#[cfg(windows)]
fn collect_sensors_and_drivers() -> (Option<Value>, Option<Value>) {
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
    (sensors, driver_issues)
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
