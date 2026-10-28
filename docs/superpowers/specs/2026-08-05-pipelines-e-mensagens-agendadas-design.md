# Pipelines (Kanban) e Mensagens Agendadas — Design

Data: 2026-08-05 · Status: aprovado por seções · Escopo: OSS + Enterprise (gate por feature flag)

## 1. Contexto e objetivos

O Chatwoot não possui pipeline/kanban nem agendamento de mensagens: não há `Pipeline`, `PipelineStage`, `PipelineItem` ou campo `scheduled_at` em `Message` (grep limpo em `app/` e `enterprise/`); os mecanismos próximos existentes são restritos ou inadequados — campanhas `one_off` (`Campaign.scheduled_at`) são canal-restritas (Twilio SMS/Sms/Whatsapp), drafts são Redis-only sem entidade em banco, e delayed automations são regra-escopadas, não mensagem-escopadas.

O EvoCRM (`evo-ai-crm-community`) já implementa o produto completo (Pipeline/PipelineStage/PipelineItem/StageMovement e ScheduledAction com executor minuto-a-minuto). O mapeamento e a análise das telas foram aprovados; este design transpõe a UX validada para o modelo conversa-first do Chatwoot, sem copiar a entidade de card própria do EvoCRM.

**Objetivos**

1. **Pipelines**: múltiplos pipelines por conta (`account_id`), cada um com etapas ordenadas; a conversa é o card. Agentes organizam conversas arrastando cards entre colunas, com filtros por inbox, assignee, label e status.
2. **Mensagens agendadas**: enviar um texto em data/hora futura em uma conversa; editar e cancelar enquanto pendente; a execução cria uma `Message` real no momento do envio; conversa resolvida no fire-time recebe a mensagem e é reaberta.
3. **Reuso**: `Messages::MessageBuilder`, `SendReplyJob`, `Conversations::PermissionFilterService`, Sidekiq (sidekiq-cron + filas) e os padrões de `AutomationRulePendingExecution` (claim atômico, at-most-once, purge).

**Critérios de sucesso**: mover um card entre colunas (ação dedicada, §7.1) reflete em `conversation.pipeline_stage_id` e no board de todos os agentes via ActionCable; uma mensagem agendada cria **no máximo uma** `Message` real na conversa — idempotência pelo status + `message_id` commitado, um retry pós-commit encontra estado terminal e não recria — mesmo que a conversa esteja resolvida (reaberta explicitamente via `conversation.open!` dentro da mesma transação que cria a `Message`); nenhuma duplicação em execuções concorrentes do sweep; a entrega externa é at-most-once via `SendReplyJob` (retries de canal seguem o caminho existente de mensagens).

## 2. Não objetivos (MVP)

- **Sem `PipelineItem`**: não há card sem conversa (lead puro), nem reentrada pós-conclusão. O card é sempre uma `Conversation`.
- **Sem valor/ganhos/produtos/forecast/tipo**: o board e a lista de pipelines não exibem campos monetários nem `pipeline_type` (diferente do EvoCRM).
- **Sem página global de agendamentos**: agendamentos são listados e gerenciados apenas dentro da conversa.
- **Sem recorrência**, templates de mensagem, anexos/mentions em mensagens agendadas, nem ações além de texto (`execute_webhook`, `create_task`, `send_email` ficam fora).
- **Sem automações de inatividade por estágio** (ex.: `stage_automation_rules` do EvoCRM).
- **Sem reordenação manual persistida dentro da coluna** (ver §4, invariante 6).
- **Sem histórico event-sourced de movimentação** (não há tabela `StageMovement`; auditoria fica para pós-MVP).
- **Sem permissões finas por pipeline/etapa** (quem vê/move usa a hierarquia de permissão de conversa existente; ver §5).
- **Sem SLA por etapa** e sem relatórios de funil (CSV fica para pós-MVP).

## 3. Decisões e alternativas rejeitadas

| # | Decisão | Alternativas rejeitadas e motivo |
|---|---------|----------------------------------|
| D1 | **Card é `Conversation`**; o pipeline é organizador de conversas, não de leads. | Card próprio (`PipelineItem` do EvoCRM com `conversation_id` XOR `contact_id`): exige migrar o conceito de lead/deal e duplicar permissões, atividade e eventos que `Conversation` já tem. |
| D2 | **`conversation.pipeline_stage_id` (FK nullable) + `conversation.pipeline_stage_changed_at`**: cada conversa pertence a no máximo uma `PipelineStage` por vez. | (a) `custom_attributes` jsonb: sem FK, sem índice, sem validação de cross-account; (b) tabela de membership 1:N: desnecessária, a invariante é 1 etapa por conversa. |
| D3 | **Pipeline derivado da etapa**: não há `conversation.pipeline_id`; o pipeline de uma conversa é `pipeline_stage.pipeline`. | Coluna `pipeline_id` redundante na conversa: fonte de divergência (etapa e pipeline inconsistentes). |
| D4 | **Modelos próprios `Pipeline` e `PipelineStage`** (tabelas novas, account-scoped). | Colunas = labels ou saved views (`CustomFilter`): labels não têm ordem própria nem cores e misturam semântica de organização com tagging; saved views são por usuário, não estrutura da conta. |
| D5 | **Status, labels, inbox e assignee independentes da etapa**: mover de etapa não altera `status`, labels, inbox nem assignee; resolver a conversa não a remove da etapa. | Atrelar etapa a `status` (`resolved` = Finalizado): quebra o fluxo de atendimento (resolve/reopen diários) e o SLA/auto-resolve. |
| D6 | **Quatro etapas padrão editáveis por pipeline novo**: Pendente, Follow-up, Proposta, Finalizado (criadas na transação de criação; renomeáveis, reordenáveis, excluíveis, adicionáveis). | Etapas fixas não editáveis: inviável para contas com fluxo próprio. |
| D7 | **`ScheduledMessage` separado** (tabela nova), texto somente, com lifecycle próprio; **execução cria `Message` real na hora** via `Messages::MessageBuilder` + `SendReplyJob`. | (a) `scheduled_at` em `Message`: mensagem agendada não é uma mensagem real (não foi enviada); exigiria estados e edição/cancelamento na tabela de mensagens, poluindo `Message` e o feed; (b) campanhas `one_off`: canal-restritas e em lote; (c) drafts Redis: sem garantia de execução. |
| D8 | **Editar/cancelar apenas enquanto `pending`**; cancelamento via `DELETE` (equivalente ao `cancel!` do EvoCRM). | Cancelar/editar em `processing`/`executing`: corrida com o worker; o sweep pode já estar agindo. |
| D9 | **Conversa resolvida no fire-time: envia e reabre** (status → `open` via `conversation.open!` explícito no domínio, dentro da mesma transação que cria a `Message` — rollback também desfaz a reabertura), preservando o restante. | Pular o envio se resolvida (descartar/`skipped`): perde o propósito de follow-up agendado; o EvoCRM re-resolve no pós-MVP, o MVP decide reabrir. |
| D10 | **Reuso integral do padrão de `AutomationRulePendingExecution`**: status com `claim!` atômico, `processing` reclaimável, `executing` transacional com a criação da `Message` (commit → terminal; rollback → reclaim), retries limitados antes da criação, purge de terminais, sweep em cron dedicado minuto-a-minuto. | Execução ad-hoc por conversa no request: sem garantia de entrega única nem visibilidade de falha. |
| D11 | **Feature flags `pipeline` e `scheduled_messages`** em `config/features.yml` (coluna bitmask `feature_flags_ext_1`, padrão `delayed_automations`), habilitáveis por conta. | Recurso sempre-ligado: quebra instalações grandes sem necessidade. |
| D12 | **Sem página global de agendamentos**; endpoints de `scheduled_messages` aninhados por conversa. | Endpoint global + página própria: escopo extra sem requisito aprovado. |

## 4. Modelos e invariantes

### 4.1 `Pipeline`

Tabela `pipelines` (nova):

- `account_id` (FK `accounts`, not null, indexado)
- `name` (string, not null)
- `description` (text, nullable)
- `archived_at` (datetime, nullable)
- `created_at`/`updated_at`

Comportamento: criar pipeline cria as 4 etapas padrão (D6) na mesma transação. Arquivar (`archived_at`) esconde da lista e do seletor, mas **não** desassocia conversas (a conversa mantém `pipeline_stage_id`; o board continua acessível por link direto). Não existe exclusão física de pipeline com conversas — o fluxo é arquivar. `Pipeline` é sempre `account_id`-scoped em toda query.

### 4.2 `PipelineStage`

Tabela `pipeline_stages` (nova):

- `pipeline_id` (FK `pipelines`, not null, indexado)
- `name` (string, not null)
- `position` (integer, not null; único por `pipeline_id`)
- `color` (string hex, not null; default por posição: Pendente azul, Follow-up âmbar, Proposta roxo, Finalizado verde)
- `created_at`/`updated_at`

O `account_id` vem de `pipeline.account` (sem coluna redundante; joins baratos, consultas sempre partem de `Pipeline.where(account_id: …)`). Excluir etapa com conversas associadas é **bloqueado** (API retorna 409 com a contagem); o agente deve mover as conversas antes. Etapas padrão são editáveis: renomear, reordenar (`position`), excluir, adicionar.

### 4.3 `Conversation` (alterações)

- `pipeline_stage_id` (bigint, FK `pipeline_stages`, nullable, indexado)
- `pipeline_stage_changed_at` (datetime, nullable)

Invariantes:

1. `pipeline_stage_id` não nulo ⇒ `pipeline_stage.pipeline.account_id == conversation.account_id` (validação de cross-account na escrita; violação de setup deve falhar alto).
2. No máximo uma etapa por conversa — garantida pela própria coluna.
3. `pipeline_stage_changed_at` é atualizado em toda mudança de `pipeline_stage_id` (setado junto com o update; base do "dias no estágio" e da ordenação da coluna).
4. `pipeline_stage_id` entra em `list_of_keys` (`app/models/conversation.rb`) para o `CONVERSATION_UPDATED` disparar (board em tempo real via ActionCable). O espelho enterprise (`enterprise/app/models/enterprise/conversation.rb`, que hoje soma `sla_policy_id`) deve receber a mesma chave via `prepend_mod_with`, conforme AGENTS.md.
5. Mover de etapa **não** altera `status`, labels, inbox, assignee nem `snoozed_until` (D5).
6. **Ordenação dentro da coluna**: `pipeline_stage_changed_at ASC` (FIFO — mais antigo no topo). Não há `position` por conversa no MVP; DnD dentro da mesma coluna não persiste reordenação (sem efeito, apenas visual momentâneo).

### 4.4 `ScheduledMessage`

Tabela `scheduled_messages` (nova):

- `account_id` (FK `accounts`, not null, indexado)
- `conversation_id` (FK `conversations`, not null, indexado)
- `content` (text, not null) — texto somente
- `scheduled_at` (datetime, not null; armazenado em UTC)
- `internal_note` (text, nullable, máx. 500 chars)
- `status` (integer enum, not null, default `pending`)
- `retry_count` (integer, not null, default 0) — tentativas já feitas antes da criação da `Message`
- `max_retries` (integer, not null, default 3) — teto de retries limitados antes de `failed`
- `message_id` (FK `messages`, nullable) — a `Message` real criada no fire-time
- `created_by_id` (FK `users`, not null)
- `sent_at` (datetime, nullable)
- `error` (text, nullable)
- `created_at`/`updated_at`

Índices: `(status, scheduled_at)` (sweep, padrão `idx_scheduled_actions_status_time`/`(status, due_at)` de `AutomationRulePendingExecution`) e `(conversation_id)`.

Estados (espelho do padrão de `AutomationRulePendingExecution`, adaptado):

| Estado | Significado | Transições |
|--------|-------------|------------|
| `pending` | criado, aguardando o fire-time | → `processing` (claim) · → `cancelled` (usuário) |
| `processing` | claimado pelo worker, ainda não agiu; reclaimável se `updated_at` ultrapassar `STALE_PROCESSING_TIMEOUT` | → `executing` · reclaim do sweep renova `updated_at` (permanece `processing`) |
| `executing` | criação da `Message` em andamento, **sempre dentro da transação** que commita `sent`; nunca persiste órfã (rollback → volta a `processing`, reclaimável por stale) | → `sent` (commit) · rollback → `processing` |
| `sent` | `Message` criada e `SendReplyJob` enfileirado pelo callback real; `message_id`/`sent_at` preenchidos; **terminal — um retry pós-commit encontra este estado e não recria** | terminal (purge após 30 dias) |
| `failed` | falha terminal — após esgotar `max_retries` (ex.: `prevent_message_flooding` persistente) ou direta (conversa inexistente → `error` `conversation_gone`, sem retry); `error` preenchido; retry manual disponível | → `pending` (retry manual re-enfileira execução imediata e zera `retry_count`) |
| `cancelled` | cancelado pelo usuário antes da execução | terminal (purge após 30 dias) |

Invariantes:

1. `scheduled_at` deve ser futuro na criação e na edição (validação server-side em UTC — autoritativa; client-side no fuso da conta).
2. Editar (`PATCH`) e cancelar (`DELETE`) apenas enquanto `pending`; fora disso a API responde 409 com o estado atual.
3. O fire-time cria **no máximo uma** `Message` por `ScheduledMessage`: a transação liga `message_id` e commita como `sent` (terminal), então um retry pós-commit encontra o estado terminal e não recria (ver §9).
4. A `Message` criada é `outgoing`, sender = `created_by`, com `content_attributes['scheduled_message_id'] = scheduled_message.id`.
5. Mensagens de agendamento seguem a semântica normal de outgoing criado por User: `Message#human_response?` permanece **inalterado** — a mensagem agendada é `outgoing` com sender = `created_by` (User), logo conta como resposta humana (limpa `waiting_since`, dispara `REPLY_CREATED` e os eventos/SLA normalmente). Não adicionar exclusão por `scheduled_message_id` no MVP.
6. Purge de terminais (`sent`, `cancelled`, `failed` antigos > 30 dias) em lotes, no padrão `AutomationRulePendingExecution.purge_terminal!`.

## 5. Permissões, multitenancy e Enterprise

- **Multitenancy**: toda query nova parte de `account_id` (pipelines, pipeline_stages via pipeline, scheduled_messages). O parâmetro de rota é `:account_id`; o controller resolve o recurso dentro da conta e falha com 404 se o id pertencer a outra conta (padrão atual de scoping por `Current.account`/`@current_account`).
- **Gestão de pipeline/etapas** (criar, renomear, reordenar, excluir etapa, arquivar pipeline): usuário com role `admin` da conta.
- **Mover card e agendar mensagem**: qualquer agente com acesso à conversa. A listagem de conversas por etapa usa `Conversations::FilterService` (`app/services/conversations/filter_service.rb`), que já aplica `Conversations::PermissionFilterService` — no OSS sem restrição adicional; no Enterprise a hierarquia `conversation_manage > conversation_unassigned_manage > conversation_participating_manage` (`enterprise/app/services/enterprise/conversations/permission_filter_service.rb`) vale automaticamente: quem não pode ver a conversa não a vê na coluna nem consegue movê-la (a ação dedicada de movimento, §7.1, passa pelos mesmos guards do controller atual de conversas).
- **Feature flags**: `pipeline` e `scheduled_messages` em `config/features.yml` (coluna `feature_flags_ext_1`, padrão `delayed_automations`), verificadas via `account.feature_enabled?` (`app/models/concerns/featurable.rb`). Os controllers/serviços de pipeline e agendamento checam a flag da conta antes de qualquer ação; instalação sem a flag não expõe rotas funcionais (404/403 consistente com o gate de outras features).
- **Enterprise**: nenhuma feature exclusiva no MVP — os dois recursos são OSS com flag por conta (mesmo modelo de `delayed_automations`). Os pontos de acoplamento enterprise previstos: `enterprise/app/models/enterprise/conversation.rb` (adição de `pipeline_stage_id` ao `list_of_keys`) e o PermissionFilterService (já aplicado por reuso). Conforme AGENTS.md, qualquer extensão enterprise futura (custom roles para pipeline) deve ser módulo `prepend_mod_with`, nunca edição direta de OSS.

## 6. UX

Referência visual: análise de telas aprovada (lista, board com 4 colunas, modal de agendamento). Texto em pt-BR via i18n (`en.yml`/`en.json`), sem strings soltas (AGENTS.md); usar `replaceInstallationName` onde couber branding.

### 6.1 Lista de pipelines

- Item de sidebar **"Pipelines"** entre "Conversas" e "Contatos" (mesmo nível hierárquico), sem badge numérico no MVP.
- Tela: header com título e botão "Novo pipeline"; busca por nome; tabela com colunas **Nome, Conversas (total nas etapas), Etapas, Status, Ações** — sem colunas de valor/ganhos (fora de escopo).
- Ações de linha (menu ⋯): Editar, Reordenar etapas, Arquivar. Sem "Excluir" (arquivamento substitui exclusão).
- Estados: vazio (empty state + CTA "Criar primeiro pipeline"), carregando (skeleton), erro (banner + "Tentar novamente"), busca sem resultados, arquivados (toggle "Mostrar arquivados").
- Criar pipeline abre modal (**nome + descrição opcional**) e redireciona para o board (etapas padrão já criadas).

### 6.2 Board

- URL compartilhável: `GET /accounts/:id/pipelines/:pipeline_id`; deep link de coluna `…/stages/:stage_id`.
- Colunas de largura fixa 280px; header com cor, nome editável inline, contador, `+` (adicionar conversa via seletor buscável) e `⋯` (Renomear/Adicionar etapa após esta/Excluir etapa). Coluna placeholder "+ Adicionar etapa" à direita quando houver espaço.
- **Card = Conversation**: avatar, nome do contato, snippet da última mensagem não-automação (2 linhas, ellipsis), timestamp relativo, badge de status (Aberto/Resolvido/Pendente/Snoozed via `Conversation#status`), dias no estágio ("5d", de `pipeline_stage_changed_at`), ícone de sino quando há `ScheduledMessage` pendente nesta conversa.
- Clique no card abre drawer lateral (480px) com a conversa, mantendo o board visível (padrão split-view do Chatwoot).
- **Drag & drop**: DnD HTML5 nativo (padrão `PipelineKanban.tsx` do EvoCRM: `dragstart/over/drop` + refs de estado, sem biblioteca). Entre colunas → `POST /conversations/:conversation_id/pipeline_stage` com `{ pipeline_stage_id }` (ação dedicada, §7.1); mesma coluna → sem persistência (invariante 6). Suporte a teclado obrigatório (foco no card → Enter/Space "modo mover" → setas → Enter confirma), com anúncio `aria-live` ("Movido Rafaela de Pendente para Follow-up"). `prefers-reduced-motion` desabilita animações.
- **Filtros** (server-side via `Conversations::FilterService`): Inbox (multi), Assignee (multi, com "Não atribuído"), Label (multi, via índice GIN de `label_list`), Status (multi). Seleção propagada via URL params; botão "Filtros" com pills removíveis. Busca por texto (nome/telefone/email/snippet) com debounce.
- Paginação por coluna: ≤ 200 cards por coluna com "Carregar mais".
- Estados: vazio por coluna ("Nenhuma conversa nesta etapa" + "Adicionar conversa"), board vazio sem etapas (CTA "Criar primeira etapa"), carregando (skeleton por coluna), erro (banner + "Recarregar"), busca sem resultados.

### 6.3 Composer e mensagem agendada

- Botão **"Agendar"** no `ReplyBox.vue` (composer), habilitado apenas com texto no composer; com anexo presente, bloquear com aviso ("Anexos não são suportados em mensagens agendadas").
- Modal "Agendar mensagem": campo Mensagem read-only (vem do composer), campo "Data e hora" (`datetime-local` nativo, fuso da conta — `account.timezone`, fallback `America/Sao_Paulo` — sempre exibido no preview: "Será enviada em ter., 5 de ago. de 2026 às 14:30 (BRT)"), campo Observação interna (opcional, 500 chars). Validações bloqueantes: mensagem vazia, data no passado no fuso da conta ("A data precisa ser no futuro"), inbox offline (modal de erro com link "Configurar canal").
- Estados do modal: salvando (botão "Agendando…", modal não fechável — previne double-submit), sucesso (toast "Mensagem agendada para …" + item de timeline + card acima do composer), falha (toast de erro, modal mantido com dados). `Cmd/Ctrl+Enter` submete, `Esc` fecha.
- **Card acima do composer** (subscription ActionCable): "Próxima mensagem agendada: 5 de ago., 14:30 — 'Bom dia, …'" com countdown ao vivo e ações **Editar** / **Cancelar**. Cancelamento com confirmação inline ("Tem certeza? Ela não será enviada."). Edição reabre o mesmo modal pré-preenchido com "Salvar alterações" (bloqueada se status ≠ `pending`).
- Item de timeline: "📅 [Agente] agendou uma mensagem para … — '…'" (versão truncada); estado enviado/falhou/cancelado visível na conversa. Mensagem agendada **falhou** mostra "Tentar novamente" (retry manual).
- Sem página global de agendamentos: nada além da conversa.
- Atalhos de navegação: `g p` (Pipelines), `g l` (Conversas); no board: `n` nova conversa na coluna focada, `/` foca busca, `esc` limpa.

## 7. APIs

Todas sob `/api/v1/accounts/:account_id`, JSON, autenticação e scoping atuais do Chatwoot. Gate: flag `pipeline` (§7.1) e flag `scheduled_messages` (§7.2).

### 7.1 Pipelines

| Método | Rota | Ação |
|--------|------|------|
| GET | `/pipelines` | Lista pipelines ativos da conta (sem conversas; stages com contagem) |
| POST | `/pipelines` | Cria pipeline (nome + descrição opcional) + 4 etapas padrão (transação) |
| GET | `/pipelines/:pipeline_id` | Board: pipeline + stages ordenados (sem cards) |
| PATCH | `/pipelines/:pipeline_id` | Renomeia / atualiza descrição / arquiva (`archived_at`) |
| DELETE | `/pipelines/:pipeline_id` | Arquivamento (soft); nunca exclusão física com conversas |
| POST | `/pipelines/:pipeline_id/stages` | Cria etapa (position = última + 1) |
| PATCH | `/pipelines/:pipeline_id/stages/:stage_id` | Renomeia / reordena (`position`) |
| DELETE | `/pipelines/:pipeline_id/stages/:stage_id` | Exclui (409 se houver conversas na etapa) |
| GET | `/pipelines/:pipeline_id/stages/:stage_id/conversations` | Conversas da etapa, paginadas, com filtros `inbox_ids`, `assignee_id`, `label`, `status` e `q` (busca) — via `Conversations::FilterService` |

**Mover card — ação dedicada**: `POST /conversations/:conversation_id/pipeline_stage` com body `{ pipeline_stage_id }` (rota account-scoped, ação própria do controller de conversas — **não** estender `PATCH /conversations/:conversation_id`). Valida `pipeline_stage_id` pertencer à mesma conta (404 cross-account), atualiza `pipeline_stage_changed_at`, persiste `pipeline_stage_id` e dispara `CONVERSATION_UPDATED` via `list_of_keys`. Como o pipeline é derivado da etapa (D3), mover para uma etapa de outro pipeline da mesma conta também troca o pipeline da conversa.

Serializers: `PipelineSerializer` (inclui `description`), `PipelineStageSerializer` (com `conversations_count`), `ConversationSerializer` expõe `pipeline_stage_id` e `pipeline_stage_changed_at`.

### 7.2 Mensagens agendadas (aninhadas por conversa)

| Método | Rota | Ação |
|--------|------|------|
| GET | `/conversations/:conversation_id/scheduled_messages` | Lista da conversa (pendentes + recentes, mais novas primeiro) |
| POST | `/conversations/:conversation_id/scheduled_messages` | Cria (`content`, `scheduled_at`, `internal_note` opcional) → `pending` |
| PATCH | `/conversations/:conversation_id/scheduled_messages/:id` | Edita `content`/`scheduled_at`/`internal_note` (só `pending`; 409 caso contrário) |
| DELETE | `/conversations/:conversation_id/scheduled_messages/:id` | Cancela (só `pending` → `cancelled`; 409 caso contrário) |
| POST | `/conversations/:conversation_id/scheduled_messages/:id/retry` | Retry manual de `failed`: status → `pending`, zera `retry_count` e enfileira execução imediata (não espera o sweep) |

Não existe rota global de `scheduled_messages`. `ScheduledMessageSerializer` expõe `content`, `scheduled_at` (ISO-8601 com offset do fuso da conta, ex.: `2026-08-05T14:30:00-03:00`), `status`, `internal_note`, `created_by`, `message_id`, `sent_at`, `error`. A API aceita `scheduled_at` em ISO-8601 com offset e persiste em UTC; nunca no fuso do agente/ambiente.

## 8. Fluxos de dados

### 8.1 Board e movimentação

```
GET /pipelines/:id → stages (contagens)
GET /pipelines/:id/stages/:stage_id/conversations?filtros → cards da coluna (FilterService + permission filtering)
DnD → POST /conversations/:id/pipeline_stage { pipeline_stage_id } → valida cross-account → update + pipeline_stage_changed_at
     → list_of_keys → CONVERSATION_UPDATED → EventDispatcherJob → ActionCableBroadcastJob → board de todos os agentes
```

### 8.2 Agendamento e fire-time

```
Composer → POST /conversations/:id/scheduled_messages → validações → ScheduledMessage(pending)
  → evento scheduled_message.created → listener → ActionCable (card de countdown na conversa)

Sweep: cron dedicado minuto-a-minuto em `config/schedule.yml` (`'*/1 * * * *'`, classe `ScheduledMessages::TriggerDueJob`, padrão do `trigger_imap_email_inboxes_job`) → TriggerDueJob
  → rows due: status=pending, scheduled_at <= now, conta com flag e ativa, cap 1000
  → por row: ScheduledMessages::ProcessScheduledMessageJob.perform_later(id)
  (o `TriggerScheduledItemsJob`, cron `*/5`, não muda e não é responsável por mensagens agendadas)

ProcessScheduledMessageJob:
  1. claim! (with_lock): pending → processing (renew updated_at);
     se o claim falhou (estado mudou entre sweep e worker) → encerra sem ação; row em `processing` stale fica para o reclaim do próximo sweep
  2. re-check após o claim: se a conversa não existir mais → falha terminal **direta** (sem retry): status → `failed` +
     error `conversation_gone` (sem envio). Conversa inexistente não é condição transitória — não incrementa
     `retry_count` nem volta a `pending`
  3. transação única (with_lock na row):
     a. status → executing
     b. se a conversa estiver `resolved` → `conversation.open!` (no domínio, dentro da mesma transação, **antes** de
        criar a Message; rollback da criação também desfaz a reabertura). Não chamar controller nem `toggle_status`
     c. Messages::MessageBuilder.new(created_by, conversation, content, message_type: :outgoing,
          content_attributes: { scheduled_message_id: id }).perform  # cria e salva a Message
     d. scheduled_message.message_id = message.id; status → sent; sent_at = Time.current
     → commit: os callbacks reais de `Message#after_create_commit` rodam — apenas eventos e o **único**
       `send_reply` → SendReplyJob (queue high) → serviço do canal (CHANNEL_SERVICES). A reabertura NÃO vem do
       callback (`Message#reopen_conversation` só age em mensagens `incoming`); por isso o passo b é explícito.
       NUNCA chamar `message.send_reply` nem `toggle_status` manualmente: seria dupla enqueue / duplo toggle
  4. falha **antes** da criação da Message (validação/flooding do MessageBuilder, rollback da transação — nenhuma Message persiste)
     → retry limitado: `retry_count += 1`; se `retry_count < max_retries` → status → pending (próximo sweep);
     senão → status → failed + error + ChatwootExceptionTracker (captura, sem re-raise de replay)
```

Cancelar/editar: `DELETE`/`PATCH` com `with_lock` na row (corrida com o sweep: quem ganhar o lock decide; o perdedor recebe 409). Retry manual (`POST retry`) seta `pending`, zera `retry_count` e enfileira o `ProcessScheduledMessageJob` direto.

Purge: job do sweep (ou o próprio `TriggerDueJob`) apaga terminais (`sent`/`cancelled`/`failed`) com `updated_at` anterior a 30 dias, `in_batches(of: 1000)`.

## 9. Concorrência, idempotência, retries, timezone e falhas

- **At-most-once e idempotência**: copiar a semântica de `AutomationRulePendingExecution` — o claim! (`with_lock`, transição `pending → processing`) é atômico; apenas um worker por row. `executing` **só existe dentro da mesma transação** que cria a `Message` e commita `sent`: commit → estado terminal; rollback (crash no meio) → a row volta a `processing` (stale, reclaimável após `STALE_PROCESSING_TIMEOUT`). Não existe row órfã em `executing` — sem `abandoned`: a ação customer-facing só ocorre após o commit — a reabertura (`conversation.open!`) é transacional com a criação da `Message` (rollback a desfaz junto) e o `SendReplyJob` é enfileirado pelo callback `after_create_commit` da `Message`, depois de a transação ser terminal. O retry automático do Sidekiq (ou um worker re-enfileirado) após o commit encontra `sent`/`failed` e não recria a `Message` — idempotência garantida pelo status + vínculo `message_id` commitado na mesma transação.
- **Retries limitados (antes da criação)**: falhas transitórias **antes** da criação efetiva da `Message` (validação do `MessageBuilder` — ex.: `prevent_message_flooding` — ou erro transiente de criação) fazem rollback e incrementam `retry_count`; enquanto `retry_count < max_retries` a row volta a `pending` e executa no próximo sweep; ao esgotar, vai a `failed` + `error`. Claim perdido **não** conta retry (o worker apenas encerra sem ação, passo 1) e conversa inexistente é falha terminal **direta** (`failed` + `conversation_gone`, passo 2). Retry manual (`POST retry`) volta a `pending`, zera `retry_count` e enfileira execução imediata. Não há retry automático de delivery externo: a entrega do canal é at-most-once via `SendReplyJob`.
- **Duplo envio**: impossível pelo claim — apenas um worker por row; e o `SendReplyJob` é enfileirado **uma única vez**, pelo callback real da `Message` (`after_create_commit → send_reply`), nunca pelo worker.
- **`prevent_message_flooding`** (`Message`, 1 msg/min/conversa): se o `MessageBuilder` rejeitar (mensagem de agente recente na mesma conversa), a transação faz rollback **sem criar** `Message` e entra no caminho de retries limitados; persistindo após `max_retries`, vira `failed` com o erro capturado; retry manual disponível. Não contornar a proteção.
- **Falha de canal**: o `SendReplyJob` enfileirado (pelo callback da `Message`) é a entrega; a falha do serviço do canal segue o caminho existente de mensagens (`messages#retry`/`StatusUpdateService`), sem nova lógica no `ScheduledMessage` (já `sent`). Falha de **criação** da `Message` (validação/flooding) é o caso de retries limitados → `failed`.
- **Idempotência de criação**: o `POST` cria uma nova `ScheduledMessage` por chamada (UI bloqueia double-submit com estado "Agendando…"). Não há dedupe por `source_id` (padrão de bridge do `MessageBuilder` não se aplica a agendamentos).
- **Timezone**: `scheduled_at` é sempre UTC no banco (convenção Rails). A UI captura e exibe no fuso da **conta** (`account.timezone`; fallback `America/Sao_Paulo`) — nunca no fuso do agente nem do ambiente. A API recebe e devolve `scheduled_at` em ISO-8601 com offset (ex.: `2026-08-05T14:30:00-03:00`); o servidor converte para UTC ao persistir e serializa de volta com o offset da conta. Validação de "não pode ser passado": client-side no fuso da conta e server-side (`scheduled_at > Time.current`, em UTC) — a do servidor é a autoritativa.
- **Concorrência de edição/cancelamento vs. sweep**: ambas as operações usam `with_lock` na row; o vencedor decide, o perdedor responde 409. Não é necessário `MutexApplicationJob` no MVP porque a row é o ponto de exclusão mútua.
- **Falhas do sweep**: `TriggerDueJob` enfileira workers; falha de um worker não afeta os demais. `reschedule_paused` (análogo ao de pending executions) não se aplica: `ScheduledMessage` não pausa.
- **Downtime longo**: rows com `scheduled_at` vencido há muito tempo são processadas no próximo sweep (o fire-time não é "perder o horário"); sem janela de expiração no MVP — a decisão de expirar fica para pós-MVP.

## 10. Rollout

1. **Migrations** (uma única migration por tabela, padrões de nomenclatura do repo):
   - criar `pipelines`; criar `pipeline_stages`; `add_reference :conversations, :pipeline_stage, null: true, foreign_key: true` + `add_column :conversations, :pipeline_stage_changed_at, :datetime`; criar `scheduled_messages`.
   - Sem backfill: colunas nullable, recurso novo.
2. **Flags**: registrar `pipeline` e `scheduled_messages` em `config/features.yml` (coluna `feature_flags_ext_1`, disabled por padrão). Habilitar por conta via admin.
3. **Código**: modelos → serviços/jobs → controllers/serializers → frontend (lista → board → composer), conforme §12.
4. **Sidekiq**: registrar entrada **dedicada** `scheduled_messages_trigger_due_job` em `config/schedule.yml` com cron minuto-a-minuto (`'*/1 * * * *'`, classe `ScheduledMessages::TriggerDueJob`, queue `scheduled_jobs` — mesmo padrão do `trigger_imap_email_inboxes_job`). O `TriggerScheduledItemsJob` (cron `*/5`) não muda e não cobre mensagens agendadas. A spec de schedule (`spec/configs/schedule_spec.rb`) valida o arquivo.
5. **Enterprise**: verificar overrides após cada fase (AGENTS.md): `enterprise/app/models/enterprise/conversation.rb` (list_of_keys) e ausência de conflito com SLA/roteamento; specs enterprise espelhando o layout OSS.
6. **Observabilidade**: falhas de fire-time via `ChatwootExceptionTracker` + status `failed` visível na UI; sem métricas novas no MVP.

## 11. Testes e smoke test

Convenções do repo: RSpec com `let` diretos (sem helpers de setup custom), `with_modified_env` para ENV, comparar `error.class.name` em specs paralelas; frontend com Vitest/Playwright.

**RSpec**
- `spec/models/pipeline_spec.rb`: criação com nome + descrição opcional e 4 etapas padrão; arquivamento não desassocia conversas; exclusão bloqueada com conversas.
- `spec/models/pipeline_stage_spec.rb`: `position` único por pipeline; exclusão com conversas → erro; rename/reorder.
- `spec/models/conversation_spec.rb`: invariantes de cross-account (etapa de outra conta → inválido); `pipeline_stage_changed_at` atualizado em mudança de etapa; `list_of_keys` inclui `pipeline_stage_id`; mover etapa não altera status/labels/assignee.
- `spec/models/scheduled_message_spec.rb`: `scheduled_at` futuro na criação/edição (UTC server-side); editar/cancelar só `pending`; lifecycle `pending → processing → executing → sent` e retries limitados → `failed`; `retry_count`/`max_retries`; `human_response?` permanece inalterado — mensagem agendada (`outgoing` de User) conta como resposta humana.
- `spec/jobs/scheduled_messages/process_scheduled_message_job_spec.rb`: claim atômico (dois workers concorrentes → um só executa); conversa resolvida recebe a mensagem e é reaberta via `conversation.open!` na mesma transação (rollback da criação também desfaz a reabertura; `SendReplyJob` enfileirado uma única vez pelo callback `after_create_commit`, sem chamada manual de `send_reply`/`toggle_status`); conversa inexistente → `failed` direto, sem retry; falha de criação transitória → retries limitados e depois `failed` + `error`; retry manual re-enfileira e zera `retry_count`; stale `processing` reclaimável; retry pós-commit encontra `sent` e **não recria** a `Message`; crash no meio da transação → rollback → `processing` stale, sem duplicação.
- `spec/jobs/scheduled_messages/trigger_due_job_spec.rb`: seleciona `pending` e `scheduled_at <= now` da conta ativa com flag; cap; purge de terminais.
- `spec/controllers/api/v1/accounts/pipelines_controller_spec.rb` e `scheduled_messages_controller_spec.rb`: scoping por conta (404 cross-account), permissões (admin para gestão; agente para mover/agendar), gates de feature flag, 409 nas transições inválidas; mover via ação dedicada `POST /conversations/:id/pipeline_stage` (stage de outra conta → 404; `pipeline_stage_changed_at` atualizado; `CONVERSATION_UPDATED` disparado).
- Enterprise: `spec/enterprise/...` espelhando os pontos de list_of_keys/permissions.

**Playwright (feature)**: criar pipeline → 4 etapas visíveis → arrastar card entre colunas (assert `pipeline_stage_id` via API e atualização do board) → agendar mensagem no composer → card de countdown aparece → editar → cancelar → toast.

**Smoke test manual** (pós-implementação, com `bundle exec rails db:seed` para dados de teste):
1. Habilitar flags na conta de teste.
2. Criar pipeline; confirmar etapas Pendente/Follow-up/Proposta/Finalizado.
3. Mover conversa para "Proposta" e confirmar no board de outro agente (ActionCable).
4. Agendar mensagem para +2 min em conversa resolvida; confirmar envio, reabertura (`open`) e card sumindo.
5. Cancelar uma pendente; confirmar que não é enviada.
6. Forçar falha (canal offline) e usar "Tentar novamente".

## 12. Fases sugeridas

Cada fase termina com entrega testável e commit; a ordem respeita dependências.

1. **Fase 1 — Modelos e migrações**: `Pipeline`, `PipelineStage`, colunas em `Conversation`, `ScheduledMessage`, índices, validações e invariantes (§4) + specs de modelo.
2. **Fase 2 — Motor de agendamento**: `ScheduledMessages::TriggerDueJob` + `ProcessScheduledMessageJob` (claim, retries limitados, idempotência pós-commit, purge) com entrada própria em `config/schedule.yml` (cron minuto-a-minuto, sem tocar no `TriggerScheduledItemsJob`) + specs de jobs.
3. **Fase 3 — APIs de pipeline**: controllers/serializers/rotas (§7.1), ação dedicada `POST /conversations/:conversation_id/pipeline_stage`, gates de flag, permissões + specs de controller.
4. **Fase 4 — APIs de agendamento**: rotas aninhadas (§7.2), validações, retry + specs de controller.
5. **Fase 5 — Frontend: lista e board**: sidebar, lista de pipelines, board com DnD nativo, filtros, paginação, estados, eventos ActionCable + Playwright.
6. **Fase 6 — Frontend: composer**: botão "Agendar", modal, card de countdown, editar/cancelar, timeline, retry + Playwright.
7. **Fase 7 — Rollout e hardening**: flags em produção, verificação enterprise, smoke test manual (§11), remoção de código morto.

## 13. Referências — símbolos mapeados

Símbolos Chatwoot (repo atual) verificados:

| Símbolo | Caminho | Papel no design |
|---------|---------|-----------------|
| `Conversation` (`status`, `priority`, `list_of_keys`, `display_id`, `cached_label_list`) | `app/models/conversation.rb` | Card do pipeline; alvo das colunas novas |
| `Message` (`message_type`, `prevent_message_flooding`, `send_reply`, `human_response?`, `after_create_commit`) | `app/models/message.rb` | Mensagem real criada no fire-time; `after_create_commit` roda os callbacks reais — eventos e o **único** `send_reply` → `SendReplyJob` (a reabertura de conversa resolvida é `conversation.open!` explícita no worker, §8.2); proteção anti-flood |
| `AutomationRulePendingExecution` (`claim!`, `episode_key`, `stale_processing?`, `purge_terminal!`, `reschedule_paused`) | `app/models/automation_rule_pending_execution.rb` | Padrão de lifecycle/at-most-once copiado |
| `AutomationRule.execution_delay` / flag `delayed_automations` | `app/models/automation_rule.rb`, `config/features.yml` | Padrão de flag por conta (bitmask `feature_flags_ext_1`) |
| `TriggerScheduledItemsJob` (cron `*/5`) | `app/jobs/trigger_scheduled_items_job.rb`, `config/schedule.yml` | Sweep de delayed automations — **não** cobre mensagens agendadas (cron dedicado minuto-a-minuto para `ScheduledMessages::TriggerDueJob`) |
| `AutomationRules::TriggerPendingExecutionsJob` / `ProcessPendingExecutionJob` | `app/jobs/automation_rules/` | Padrão de sweep cap + worker por row |
| `SendReplyJob` (`CHANNEL_SERVICES`, queue `high`) | `app/jobs/send_reply_job.rb` | Perna final de entrega |
| `Messages::MessageBuilder` | `app/builders/messages/message_builder.rb` | Criação única de mensagem no fire-time |
| `Messages::StatusUpdateService` | `app/services/messages/status_update_service.rb` | Retry de entrega de mensagens (caminho existente) |
| `Conversations::PermissionFilterService` | `app/services/conversations/permission_filter_service.rb` (+ `enterprise/app/services/enterprise/conversations/permission_filter_service.rb`) | Hierarquia de acesso a conversas aplicada a colunas/agendamento |
| `Conversations::FilterService` | `app/services/conversations/filter_service.rb` | Listagem por coluna com filtros e permissões |
| `ConversationsController#update` / `#toggle_status` | `app/controllers/api/v1/accounts/conversations_controller.rb` | Referência de guards/permissões de conversa; o movimento usa a ação dedicada (§7.1); a reabertura no fire-time é `conversation.open!` explícito no domínio, dentro da transação do worker (sem controller nem `toggle_status`) |
| `MessagesController#create` / `#retry` | `app/controllers/api/v1/accounts/conversations/messages_controller.rb` | Referência de criação/retry de mensagem |
| `ChatwootApp.enterprise?` | `lib/chatwoot_app.rb` | Gate enterprise global |
| `Featurable#feature_enabled?` | `app/models/concerns/featurable.rb` | Gate por flag de conta |
| `ChatwootExceptionTracker` | `lib/chatwoot_exception_tracker.rb` | Captura de falhas de fire-time |
| `lib/events/types.rb` / dispatcher + listeners | `lib/events/types.rb`, `app/listeners/automation_rule_listener.rb` | Eventos novos `scheduled_message.*` e broadcast ActionCable |
| `Enterprise::Conversation` (`sla_policy_id` em `list_of_keys`) | `enterprise/app/models/enterprise/conversation.rb` | Ponto de acoplamento enterprise do `list_of_keys` |
| `ReplyBox.vue`, `ConversationView.vue`, `Sidebar.vue` | `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue`, `app/javascript/dashboard/routes/dashboard/conversation/ConversationView.vue`, `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` | Pontos de inserção do composer, board e navegação |

Símbolos EvoCRM (referência de UX/estado, não copiados):

| Símbolo | Caminho | O que foi aproveitado |
|---------|---------|------------------------|
| `PipelineItem` (card com `conversation_id` XOR `contact_id`, índices únicos parciais, `move_to_stage`) | `evo-crm-community/evo-ai-crm-community/app/models/pipeline_item.rb` | Rejeitado como entidade (D1); o `move_to_stage` inspirou a atualização atômica de etapa |
| `Pipeline` / `PipelineStage` (`position` único, `color`) | `evo-crm-community/evo-ai-crm-community/app/models/pipeline.rb`, `pipeline_stage.rb` | Modelo de etapas ordenadas com cor (D4/D6) |
| `StageMovement` | `evo-crm-community/evo-ai-crm-community/app/models/stage_movement.rb` | Rejeitado no MVP (sem histórico) |
| `ScheduledAction` (status `scheduled/executing/completed/failed/cancelled`, `scheduled_for` UTC, índice `(status,scheduled_for)`, `create_next_occurrence`) | `evo-crm-community/evo-ai-crm-community/app/models/scheduled_action.rb` | Inspirou `ScheduledMessage` (D7); recorrência rejeitada |
| `ScheduledActionsProcessorJob` + `ExecutorService` (claim `mark_as_executing!`, backoff, notificação) | `evo-crm-community/evo-ai-crm-community/app/jobs/scheduled_actions_processor_job.rb`, `app/services/scheduled_actions/executor_service.rb` | Inspirou o sweep; backoff/recorrência rejeitados no MVP |
| `PipelineKanban.tsx` (DnD HTML5 nativo, filtros client-side via `useSearchParams`) | `evo-crm-community/evo-ai-frontend-community/src/pages/Customer/Pipelines/PipelineKanban.tsx` | DnD nativo; filtros movidos para server-side no Chatwoot (reuso do FilterService) |
| Telas: lista de pipelines, board 4 colunas, modal "Agendar mensagem" | análise de telas aprovada (capturas) | UX de lista/board/composer (§6) |
