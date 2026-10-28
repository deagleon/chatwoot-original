# Smoke test — Pipelines e Mensagens Agendadas

Roteiro manual de validação de ponta a ponta das trilhas A (pipeline) e B (mensagens
agendadas), conforme §11 da spec aprovada
`docs/superpowers/specs/2026-08-05-pipelines-e-mensagens-agendadas-design.md`.

Pré-requisitos: ambiente dev rodando (`overmind start -f Procfile.dev`), banco com
dados de teste (`bundle exec rails db:seed`) e as flags habilitadas na conta de teste
(passo 1).

## 1. Habilitar as flags na conta de teste

```bash
bundle exec rails runner "a = Account.find_by(name: 'Acme Inc'); a.enable_features!(:pipeline, :scheduled_messages); puts [a.feature_pipeline?, a.feature_scheduled_messages?].inspect"
```

Esperado: `[true, true]`.

Gate negativo (conta **sem** as flags — ex.: `Acme Org`):

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  -H "access-token: <token>" -H "client: <client>" -H "uid: <uid>" \
  http://localhost:3000/api/v1/accounts/<account_sem_flag>/pipelines
# 404

curl -s -o /dev/null -w '%{http_code}\n' \
  -X POST -H "access-token: <token>" -H "client: <client>" -H "uid: <uid>" \
  -H "Content-Type: application/json" \
  http://localhost:3000/api/v1/accounts/<account_sem_flag>/conversations/1/scheduled_messages \
  -d '{"content":"x","scheduled_at":"<futuro>"}'
# 404
```

## 2. Criar pipeline e conferir as 4 etapas padrão

1. Sidebar → **Pipelines** → "Create pipeline" → nome "Vendas E2E" → salvar.
2. Abrir o board: conferir as colunas **Pendente, Follow-up, Proposta, Finalizado**,
   na ordem, com cores distintas.

Esperado: pipeline listado com 4 etapas; board renderiza as colunas acessíveis
(`role="list"`, `aria-label` com o nome da etapa).

## 3. Mover conversa de etapa e confirmar em outro agente (ActionCable)

1. Abrir uma conversa; no board, arrastar o card de **Pendente** para **Proposta**
   (ou usar o menu "Mover para" via teclado).
2. Conferir via API: `GET /api/v1/accounts/:id/conversations/:conversation_id` →
   `pipeline_stage_id` aponta para a etapa Proposta.
3. Em **outro agente** (outro navegador/logado), com o board aberto: o card muda de
   coluna **sem refresh** (evento `conversation.updated` via ActionCable).

Esperado: movimento persistido, `pipeline_stage_changed_at` atualizado e board do
segundo agente sincronizado em tempo real.

## 4. Agendar mensagem em conversa resolvida (+2 min)

1. Resolver uma conversa.
2. No composer, digitar o texto e clicar em **Agendar**; escolher data/hora
   **+2 minutos**; confirmar.
3. Toast "Mensagem agendada para …"; card **"Próxima mensagem agendada"** com
   countdown acima do composer; item de timeline visível.
4. Aguardar o fire-time (sweep minuto-a-minuto — `ScheduledMessages::TriggerDueJob`).

Esperado:
- A mensagem é **enviada** (aparece no feed);
- A conversa volta a **open** (reaberta na mesma transação);
- O card de countdown **some**;
- O status da row via API: `GET /conversations/:id/scheduled_messages` → `sent`.
- Em outro agente: card/timeline atualizam via realtime (`scheduled_message.updated`).

## 5. Cancelar uma pendente

1. Agendar uma mensagem para +30 min (sem resolver a conversa).
2. No card, clicar em **Cancelar** → confirmar inline ("Tem certeza? Ela não será enviada.").
3. Esperado: card some; via API o status é `cancelled`; a mensagem **não** é enviada
   mesmo após o fire-time.

## 6. Falha de canal e "Tentar novamente"

1. Com um canal indisponível (ex.: credencial de WhatsApp inválida ou canal
   removido), agendar uma mensagem e aguardar o fire-time.
2. Esperado: a mensagem entra em `failed` (via API); no item de timeline aparece o
   estado **Falhou** com o botão **"Tentar novamente"**.
3. Corrigir o canal e clicar em "Tentar novamente".
4. Esperado: a row volta a `pending` com `retry_count` zerado, é re-enfileirada e
   enviada no próximo ciclo do sweep.

## 7. Purge de terminais (30 dias)

```bash
bundle exec rails runner "
  before = ScheduledMessage.expired_terminal.count
  ScheduledMessage.purge_terminal!
  puts \"expired_terminal: #{before} -> #{ScheduledMessage.expired_terminal.count}\"
"
```

Esperado: rows terminais (`sent`/`failed`/`cancelled`) com `updated_at` há mais de
30 dias são removidas. Para simular sem esperar:

```bash
bundle exec rails runner "
  ScheduledMessage.where(status: :sent).update_all(updated_at: 31.days.ago)
  ScheduledMessage.purge_terminal!
"
```

## Validação automatizada equivalente

- RSpec: `spec/models/pipeline_spec.rb`, `spec/models/pipeline_stage_spec.rb`,
  `spec/models/conversation_spec.rb`, `spec/models/scheduled_message_spec.rb`,
  `spec/jobs/scheduled_messages`, `spec/controllers/api/v1/accounts/pipelines_controller_spec.rb`,
  `spec/controllers/api/v1/accounts/conversations/scheduled_messages_controller_spec.rb`,
  `spec/services/conversations/stage_filter_service_spec.rb`, `spec/configs/schedule_spec.rb`,
  `spec/enterprise`.
- Vitest: `app/javascript/dashboard/routes/dashboard/pipelines` e
  `app/javascript/dashboard/components/widgets/conversation/scheduled_messages`.
- Playwright: `tests/playwright/tests/e2e/ui/pipelines-board.spec.ts` e
  `scheduled-messages.spec.ts` (fluxo completo + entrega com reabertura).
