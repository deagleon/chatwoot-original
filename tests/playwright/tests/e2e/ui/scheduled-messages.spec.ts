import { test, expect, type Page } from '@playwright/test';
import { Login } from '@components/ui';

const TEST_EMAIL = process.env.TEST_USER_EMAIL || 'admin@chatwoot.com';
const TEST_PASSWORD = process.env.TEST_USER_PASSWORD || 'Password123@#';

type DashboardApi = {
  get: (url: string) => Promise<{
    data: {
      payload?: Array<Record<string, unknown>>;
      features?: Record<string, boolean>;
      status?: string;
    } & Record<string, unknown>;
  }>;
  post: (
    url: string,
    data?: unknown
  ) => Promise<{
    data: { id: number; payload?: { contact?: { id: number } } };
  }>;
};

type ScheduledMessagePayload = {
  id: number;
  content: string;
  scheduled_at: string;
  status: string;
};

/**
 * Prerequisite: the test account must have the `scheduled_messages` feature
 * flag enabled (otherwise the composer "Agendar" button is hidden and every
 * scheduled-messages API call returns 404). Enable with:
 *
 *   bundle exec rails runner \
 *     "a = Account.find_by(name: '<account>'); a.enable_features!('scheduled_messages'); a.save!"
 *
 * This spec follows the convention from pipelines-board.spec.ts:
 * - login as the admin test user
 * - drive the UI through data-testid selectors
 * - hit the JSON API via `window.axios` for assertions and setup
 *
 * The delivery test depends on the minute cron sweep (`TriggerDueJob`) being
 * scheduled in the running sidekiq process (config/schedule.yml).
 */
test.describe('Scheduled messages - E2E', () => {
  let loginComponent: Login;
  let accountId: number;

  test.beforeEach(async ({ page }) => {
    loginComponent = new Login(page);

    await loginComponent.navigate();
    await loginComponent.login(TEST_EMAIL, TEST_PASSWORD);
    await page.waitForURL(/\/app\/accounts\/\d+\/dashboard/);

    accountId = Number(page.url().match(/\/app\/accounts\/(\d+)\//)![1]);

    // Sanity check: the scheduled_messages feature must be on, otherwise nothing
    // in this spec will work. User-visible guardrail for the prerequisite above.
    await assertScheduledMessagesFeatureEnabled(page, accountId);
  });

  test('agenda, vê o card de countdown, edita e cancela', async ({ page }) => {
    test.setTimeout(120_000);
    const conversationId = await createConversation(page, accountId);

    await page.goto(`/app/accounts/${accountId}/conversations/${conversationId}`);
    const editor = page.locator('.reply-box .ProseMirror');
    await editor.waitFor({ state: 'visible' });
    await editor.click();
    await page.keyboard.type('Bom dia, teste agendado!');

    // O botão "Agendar" só aparece com texto no composer.
    const scheduleButton = page.getByTestId('scheduled-open-modal');
    await expect(scheduleButton).toBeVisible();
    await scheduleButton.click();

    // Agenda para daqui a 2 minutos.
    const datetimeInput = page.getByTestId('scheduled-datetime');
    await expect(datetimeInput).toBeVisible();
    await datetimeInput.fill(toLocalInputValue(new Date(Date.now() + 2 * 60 * 1000)));
    await page.getByTestId('scheduled-submit').click();

    // Toast de sucesso, card de countdown e item de timeline visíveis.
    await expect(page.getByText(/Mensagem agendada para/).first()).toBeVisible();
    await expect(page.getByTestId('scheduled-card')).toBeVisible();
    await expect(page.getByTestId('scheduled-timeline-item').first()).toBeVisible();

    const scheduledId = await fetchPendingScheduledMessageId(page, accountId, conversationId);
    expect(scheduledId).not.toBeNull();

    // Edita: muda a data para daqui a 30 minutos.
    await page.getByTestId('scheduled-card-edit').click();
    await expect(datetimeInput).toBeVisible();
    const editedAt = new Date(Date.now() + 30 * 60 * 1000);
    await datetimeInput.fill(toLocalInputValue(editedAt));
    await page.getByTestId('scheduled-submit').click();
    await expect(page.getByText(/Mensagem agendada atualizada/).first()).toBeVisible();

    const updated = await fetchScheduledMessage(page, accountId, conversationId, scheduledId!);
    expect(Math.abs(new Date(updated.scheduled_at).getTime() - editedAt.getTime())).toBeLessThan(
      60 * 1000
    );

    // Cancela: card some e o status vira cancelled na API.
    await page.getByTestId('scheduled-card-cancel').click();
    await expect(page.getByTestId('scheduled-card-confirm-cancel')).toBeVisible();
    await page.getByTestId('scheduled-card-confirm-cancel').click();
    await expect(page.getByTestId('scheduled-card')).toHaveCount(0);

    const after = await fetchScheduledMessage(page, accountId, conversationId, scheduledId!);
    expect(after.status).toBe('cancelled');
  });

  test('mensagem agendada em conversa resolvida é enviada e reabre a conversa', async ({
    page,
  }) => {
    // O sweep minuto-a-minuto pode demorar quase 2 minutos para pegar a row.
    test.setTimeout(300_000);
    const conversationId = await createConversation(page, accountId);
    await setConversationStatus(page, accountId, conversationId, 'resolved');

    const scheduledId = await createScheduledMessageViaApi(page, accountId, conversationId, {
      content: 'Follow-up agendado',
      scheduled_at: new Date(Date.now() + 2 * 60 * 1000).toISOString(),
    });

    // Espera o fire-time: a conversa reabre e a mensagem é enviada (D9).
    await expect
      .poll(
        async () => fetchConversationStatus(page, accountId, conversationId),
        { timeout: 180_000, message: 'conversation never reopened after scheduled message fired' }
      )
      .toBe('open');

    const after = await fetchScheduledMessage(page, accountId, conversationId, scheduledId);
    expect(after.status).toBe('sent');

    // A mensagem enviada aparece no feed.
    await page.goto(`/app/accounts/${accountId}/conversations/${conversationId}`);
    await expect(page.getByText('Follow-up agendado').first()).toBeVisible();
  });
});

// ---------- helpers ----------

async function assertScheduledMessagesFeatureEnabled(page: Page, accountId: number) {
  const features = await page.evaluate(async (id: number) => {
    const api = (window as typeof window & { axios: DashboardApi }).axios;
    try {
      const res = await api.get(`/api/v1/accounts/${id}`);
      return res.data.features ?? {};
    } catch {
      return {} as Record<string, boolean>;
    }
  }, accountId);

  if (!features['scheduled_messages']) {
    throw new Error(
      `scheduled_messages feature flag not enabled for account ${accountId}. ` +
        'Enable with: bundle exec rails runner "a = Account.find(' +
        accountId +
        '); a.enable_features!(\'scheduled_messages\'); a.save!"'
    );
  }
}

async function createConversation(page: Page, accountId: number): Promise<number> {
  return page.evaluate(
    async ({ id }) => {
      const api = (window as typeof window & { axios: DashboardApi }).axios;
      const inboxesRes = await api.get(`/api/v1/accounts/${id}/inboxes`);
      const inbox = (inboxesRes.data.payload ?? [])[0] as { id: number } | undefined;
      if (!inbox) throw new Error('No inbox available in the test account');

      const contactRes = await api.post(`/api/v1/accounts/${id}/contacts`, {
        name: `ScheduledE2E ${Date.now()}`,
      });
      const contactId = contactRes.data.payload?.contact?.id;
      if (!contactId) throw new Error('contact create did not return an id');
      const convRes = await api.post(`/api/v1/accounts/${id}/conversations`, {
        inbox_id: inbox.id,
        contact_id: contactId,
      });
      return convRes.data.id as number; // display_id, que é o que as rotas aninhadas usam
    },
    { id: accountId }
  );
}

async function createScheduledMessageViaApi(
  page: Page,
  accountId: number,
  conversationId: number,
  data: { content: string; scheduled_at: string }
): Promise<number> {
  return page.evaluate(
    async ({ id, conversationId: cid, ...payload }) => {
      const api = (window as typeof window & { axios: DashboardApi }).axios;
      const res = await api.post(
        `/api/v1/accounts/${id}/conversations/${cid}/scheduled_messages`,
        payload
      );
      return res.data.id as number;
    },
    { id: accountId, conversationId, ...data }
  );
}

async function fetchScheduledMessages(
  page: Page,
  accountId: number,
  conversationId: number
): Promise<ScheduledMessagePayload[]> {
  return page.evaluate(
    async ({ id, conversationId: cid }) => {
      const api = (window as typeof window & { axios: DashboardApi }).axios;
      const res = await api.get(
        `/api/v1/accounts/${id}/conversations/${cid}/scheduled_messages`
      );
      return (res.data.payload ?? []) as ScheduledMessagePayload[];
    },
    { id: accountId, conversationId }
  );
}

async function fetchPendingScheduledMessageId(
  page: Page,
  accountId: number,
  conversationId: number
): Promise<number | null> {
  const messages = await fetchScheduledMessages(page, accountId, conversationId);
  return messages.find(m => m.status === 'pending')?.id ?? null;
}

async function fetchScheduledMessage(
  page: Page,
  accountId: number,
  conversationId: number,
  scheduledId: number
): Promise<ScheduledMessagePayload> {
  const messages = await fetchScheduledMessages(page, accountId, conversationId);
  const match = messages.find(m => m.id === scheduledId);
  if (!match) throw new Error(`scheduled message ${scheduledId} not found`);
  return match;
}

async function setConversationStatus(
  page: Page,
  accountId: number,
  conversationId: number,
  status: 'open' | 'resolved'
) {
  await page.evaluate(
    async ({ id, conversationId: cid, status: newStatus }) => {
      const api = (window as typeof window & { axios: DashboardApi }).axios;
      await api.post(
        `/api/v1/accounts/${id}/conversations/${cid}/toggle_status`,
        { status: newStatus }
      );
    },
    { id: accountId, conversationId, status }
  );
}

async function fetchConversationStatus(
  page: Page,
  accountId: number,
  conversationId: number
): Promise<string | null> {
  return page.evaluate(
    async ({ id, conversationId: cid }) => {
      const api = (window as typeof window & { axios: DashboardApi }).axios;
      try {
        const res = await api.get(`/api/v1/accounts/${id}/conversations/${cid}`);
        return (res.data.status as string | undefined) ?? null;
      } catch {
        return null;
      }
    },
    { id: accountId, conversationId }
  );
}

function toLocalInputValue(date: Date): string {
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(
    date.getHours()
  )}:${pad(date.getMinutes())}`;
}
