Antes de qualquer tarefa, leia o PEDIDOS.md inteiro. Ao terminar algo, marque o item como [x] com data e commit. Nunca remova nem simplifique um pedido sem minha aprovação.

DECISÃO DEFINITIVA (Fernando, 2026-10-15) — detalhes no topo do PEDIDOS.md:
- Beta Cube Remote = nosso fork CONGELADO (congelado em `9cb56871e`, tag `remote-freeze`; os 4 commits de 06/10 entram se passarem na bateria da VM). PROIBIDO sincronizar/mergear com o RustDesk oficial e adicionar qualquer função nova no código do Remote. Permitido só: branding (nome, ícones, cores, textos) e correção de bug crítico, sempre testada na VM.
- Nada de "RustDesk" pode aparecer para o cliente (executável, janela, bandeja, instalador, textos, ícones, serviço do Windows).
- Funções Beta Cube vivem em 2 programas separados: Beta Cube Agent (serviço Windows invisível, base `C:\projetos\Beta Cube Monitor`) e Beta Cube Painel (app nativo Windows + Android, nunca navegador). O que já está no Remote (quick_actions.rs etc.) é portado para eles; só se remove do Remote depois que a versão nova estiver testada.

AGENTS.md
