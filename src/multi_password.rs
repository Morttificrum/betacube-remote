// Multiple password slots with per-slot permission profiles, AnyDesk-style:
// whichever slot password a client presents at login determines which
// permission profile applies to that session. Lives entirely in src/
// (never touches the libs/hbb_common submodule) and rides on the existing
// generic Config option store, so it is automatically kept in sync between
// the UI process and the daemon process the same way every other option is
// (see ipc.rs's `Data::Config` handling) -- no new IPC plumbing needed.
//
// Only a SHA-256 digest (h1, the same construction RustDesk's own primary
// password storage uses) is ever persisted. Plaintext slot passwords exist
// only transiently while computing h1 and are discarded immediately.
//
// Security note: h1 is computed with the SAME salt as the primary password
// (`Config::get_effective_permanent_password_salt()`), because that's the
// one `Connection` actually challenges against (`self.hash.salt`). If the
// primary password is ever changed in a way that rotates this salt, slots
// created under the old salt stop matching and must be re-entered -- an
// accepted tradeoff (confirmed with the user) in exchange for never storing
// plaintext.

use hbb_common::config::{compute_permanent_password_h1, Config};
use hbb_common::log;
use serde_derive::{Deserialize, Serialize};

pub const MAX_SLOTS: usize = 5;
const OPTION_KEY: &str = "multi-password-slots";

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct PermissionProfile {
    #[serde(default)]
    pub keyboard: bool,
    #[serde(default)]
    pub clipboard: bool,
    #[serde(default)]
    pub audio: bool,
    #[serde(default)]
    pub file: bool,
    #[serde(default)]
    pub restart: bool,
    #[serde(default)]
    pub recording: bool,
    #[serde(default)]
    pub block_input: bool,
    #[serde(default)]
    pub privacy_mode: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct PasswordSlot {
    label: String,
    // Hex-encoded SHA-256 h1 (32 bytes -> 64 hex chars). Never the plaintext.
    h1_hex: String,
    #[serde(default)]
    profile: PermissionProfile,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
struct MultiPasswordConfig {
    #[serde(default)]
    slots: Vec<PasswordSlot>,
}

// Request payload sent from the UI process to the daemon over `Data::Config`
// ("multi-password-upsert"). Built by the Flutter side as plain JSON.
#[derive(Debug, Deserialize)]
pub struct UpsertRequest {
    pub label: String,
    pub password: String,
    #[serde(default)]
    pub profile: PermissionProfile,
}

fn to_hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{:02x}", b)).collect()
}

fn from_hex(s: &str) -> Option<[u8; 32]> {
    if s.len() != 64 || !s.is_ascii() {
        return None;
    }
    let mut out = [0u8; 32];
    for i in 0..32 {
        out[i] = u8::from_str_radix(s.get(i * 2..i * 2 + 2)?, 16).ok()?;
    }
    Some(out)
}

fn load() -> MultiPasswordConfig {
    let raw = Config::get_option(OPTION_KEY);
    if raw.is_empty() {
        return MultiPasswordConfig::default();
    }
    serde_json::from_str(&raw).unwrap_or_default()
}

fn save(cfg: &MultiPasswordConfig) {
    let raw = serde_json::to_string(cfg).unwrap_or_default();
    Config::set_option(OPTION_KEY.to_owned(), raw);
}

/// Add a new slot or replace the one with the same label. Returns an error
/// message (meant to be shown to the user) instead of a bare `false` so the
/// UI can explain exactly why, e.g. hitting `MAX_SLOTS`.
pub fn upsert_slot(req: UpsertRequest) -> Result<(), String> {
    if req.label.trim().is_empty() {
        return Err("Nome do perfil não pode ser vazio".to_owned());
    }
    if req.password.is_empty() {
        return Err("Senha não pode ser vazia".to_owned());
    }
    let salt = Config::get_effective_permanent_password_salt();
    let h1 = compute_permanent_password_h1(&req.password, &salt);
    let h1_hex = to_hex(&h1);

    let mut cfg = load();
    if let Some(existing) = cfg.slots.iter_mut().find(|s| s.label == req.label) {
        existing.h1_hex = h1_hex;
        existing.profile = req.profile;
    } else {
        if cfg.slots.len() >= MAX_SLOTS {
            return Err(format!("Máximo de {} perfis de acesso", MAX_SLOTS));
        }
        cfg.slots.push(PasswordSlot {
            label: req.label,
            h1_hex,
            profile: req.profile,
        });
    }
    save(&cfg);
    Ok(())
}

pub fn remove_slot(label: &str) {
    let mut cfg = load();
    let before = cfg.slots.len();
    cfg.slots.retain(|s| s.label != label);
    if cfg.slots.len() != before {
        save(&cfg);
    }
}

/// For display in the settings UI: labels and their profiles, never h1.
pub fn list_labels_and_profiles() -> Vec<(String, PermissionProfile)> {
    load()
        .slots
        .into_iter()
        .map(|s| (s.label, s.profile))
        .collect()
}

/// Checks every configured slot's h1 with `verify`, returning the profile of
/// the first slot that matches (if any). `verify` is expected to be
/// `Connection::verify_h1`, which hashes the slot's h1 together with the
/// per-connection challenge and compares against what the client sent.
pub fn find_matching_profile(verify: impl Fn(&[u8]) -> bool) -> Option<PermissionProfile> {
    for slot in load().slots {
        match from_hex(&slot.h1_hex) {
            Some(h1) if verify(&h1) => return Some(slot.profile),
            Some(_) => {}
            None => {
                log::warn!("Ignoring multi-password slot '{}': corrupt h1", slot.label);
            }
        }
    }
    None
}
