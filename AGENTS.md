# RustDesk Guide

## Backlog

* `PEDIDOS.md` (raiz do projeto) é a fonte única de verdade dos pedidos
  pendentes do usuário — toda sessão nova começa lendo ele.
* Todo pedido novo do usuário entra em `PEDIDOS.md` na hora (descrição,
  data, status), mesmo que a implementação comece depois.
* Nenhum item vira "Feito" sem evidência de teste real anexada — código
  commitado/buildado não é evidência suficiente por si só.
* Atualizar o status do item (`[ ]`/`[~]`/`[x]`, com data e commit) no `PEDIDOS.md` sempre que terminar\
  uma etapa, e sempre antes de qualquer `/compact`. (O `BACKLOG.md` virou só um ponteiro para o `PEDIDOS.md`.)

## Checklist obrigatório de release (regra fixa, 2026-10-06)

**NADA de versão nova vai pra loja sem passar nos 7 passos abaixo, na
VM E no PC do usuário, com prova de cada um.** O usuário não testa em
loja — ele só recebe o caminho do instalador depois de todos passarem:

1. Instalar por cima de uma versão antiga já existente (não instalação
   limpa).
2. 1 atalho só (sem duplicado).
3. Serviço criado e rodando (`sc.exe query`, nunca `sc` sem `.exe` no
   PowerShell — é alias de `Set-Content`).
4. Janela abre normal, com ID e senha visíveis (não branca).
5. Registro confirmado no hbbs.
6. Conexão remota funcionando com a janela do app fechada.
7. Reinício do PC — tudo volta sozinho (serviço + registro) sem
   intervenção.

## Project Layout

### Directory Structure
* `src/` Rust app
* `src/server/` audio / clipboard / input / video / network
* `src/platform/` platform-specific code
* `src/ui/` legacy Sciter UI (deprecated)
* `flutter/` current UI
* `libs/hbb_common/` config / proto / shared utils
* `libs/scrap/` screen capture
* `libs/enigo/` input control
* `libs/clipboard/` clipboard
* `libs/hbb_common/src/config.rs` all options

### Key Components
- **Remote Desktop Protocol**: Custom protocol implemented in `src/rendezvous_mediator.rs` for communicating with rustdesk-server
- **Screen Capture**: Platform-specific screen capture in `libs/scrap/`
- **Input Handling**: Cross-platform input simulation in `libs/enigo/`
- **Audio/Video Services**: Real-time audio/video streaming in `src/server/`
- **File Transfer**: Secure file transfer implementation in `libs/hbb_common/`

### UI Architecture
- **Legacy UI**: Sciter-based (deprecated) - files in `src/ui/`
- **Modern UI**: Flutter-based - files in `flutter/`
  - Desktop: `flutter/lib/desktop/`
  - Mobile: `flutter/lib/mobile/`
  - Shared: `flutter/lib/common/` and `flutter/lib/models/`

## Rust Rules

* Avoid `unwrap()` / `expect()` in production code.
* Exceptions:

  * tests;
  * lock acquisition where failure means poisoning, not normal control flow.
* Otherwise prefer `Result` + `?` or explicit handling.
* Do not ignore errors silently.
* Avoid unnecessary `.clone()`.
* Prefer borrowing when practical.
* Do not add dependencies unless needed.
* Keep code simple and idiomatic.

## Tokio Rules

* Assume a Tokio runtime already exists.
* Never create nested runtimes.
* Never call `Runtime::block_on()` inside Tokio / async code.
* Do not hide runtime creation inside helpers or libraries.
* Do not hold locks across `.await`.
* Prefer `.await`, `tokio::spawn`, channels.
* Use `spawn_blocking` or dedicated threads for blocking work.
* Do not use `std::thread::sleep()` in async code.

## Editing Hygiene

* Change only what is required.
* Prefer the smallest valid diff.
* Do not refactor unrelated code.
* Do not make formatting-only changes.
* Keep naming/style consistent with nearby code.

## Localization (`src/lang/*.rs`)

Each file is a `HashMap<key, translation>`. Layout:

* `template.rs` is the master list of every key. **Never edit it** as part of translation work.
* `en.rs` holds only the keys whose English display text differs from the key itself.
* Every other file (`de.rs`, `fr.rs`, …) carries the full key set; an untranslated entry has an empty value: `("key", "")`.

### Finding the English source for a key

When filling an empty entry, determine the source English text with this rule:

* If `key` exists in `en.rs` **with a non-empty value**, that value is the source text (look it up in `en.rs`).
* Otherwise the **key string itself is the source text** (the key is already plain English).

Then translate that source into the file's target language (infer the language from the file's existing non-empty entries / filename).

### Translation hygiene

* Only fill empty values. Never change keys, and never touch existing non-empty translations.
* Preserve placeholders (`{}`) and escape sequences (`\n`, `\"`) exactly as in the source.
* Do not translate brand or technical tokens: `RustDesk`, `Socks5`, `TLS`, `UAC`, `Wayland`, `X11`, `TCP`, `UDP`, `2FA`, `RDP`, `D3D`, etc.
* Copy URL values (e.g. `doc_*` keys) verbatim from `en.rs`.
