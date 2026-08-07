import { test, expect, type Page } from '@playwright/test';
import { Login, PipelineBoard } from '@components/ui';

const TEST_EMAIL = process.env.TEST_USER_EMAIL || 'admin@chatwoot.com';
const TEST_PASSWORD = process.env.TEST_USER_PASSWORD || 'Password123@#';
const TEST_PIPELINE_NAME = process.env.TEST_PIPELINE_NAME || 'Vendas E2E';

/**
 * Prerequisite: the test account must have the `pipeline` feature flag enabled
 * (otherwise the pipelines sidebar entry is hidden and every API call returns
 * 401 Pundit). Enable with:
 *
 *   bundle exec rails runner \
 *     "a = Account.find_by(name: '<account>'); a.enable_features!('pipeline'); a.save!"
 *
 * This spec follows the convention from inbox-creation-flow.spec.ts:
 * - login as the admin test user
 * - drive the UI through the PipelineBoard page object
 * - hit the JSON API via `window.axios` for assertions and setup
 */
test.describe('Pipelines Board - E2E', () => {
  let loginComponent: Login;
  let pipelineBoard: PipelineBoard;
  let accountId: number;

  test.beforeEach(async ({ page }) => {
    loginComponent = new Login(page);
    pipelineBoard = new PipelineBoard(page);

    await loginComponent.navigate();
    await loginComponent.login(TEST_EMAIL, TEST_PASSWORD);
    await page.waitForURL(/\/app\/accounts\/\d+\/dashboard/);

    accountId = Number(
      page.url().match(/\/app\/accounts\/(\d+)\//)![1]
    );

    // Sanity check: the pipeline feature must be on, otherwise nothing in this
    // spec will work. This is the user-visible guardrail for the prerequisite
    // documented at the top of the file.
    await assertPipelineFeatureEnabled(page, accountId);
  });

  test('pipelines list page renders the table', async () => {
    await pipelineBoard.navigateToList(accountId);
    await expect(pipelineBoard.getPipelinesTable()).toBeVisible();
  });

  test('creates a pipeline "Vendas" via the modal and shows it in the table', async ({
    page,
  }) => {
    await pipelineBoard.navigateToList(accountId);

    await cleanPipelineByName(page, accountId, TEST_PIPELINE_NAME);
    await expect(pipelineBoard.getPipelineRow(TEST_PIPELINE_NAME)).toHaveCount(0);

    await pipelineBoard.createPipelineViaModal(TEST_PIPELINE_NAME);

    const createdId = await findPipelineByName(
      page,
      accountId,
      TEST_PIPELINE_NAME
    );
    expect(createdId).not.toBeNull();
  });

  test('board renders the four default stages as accessible columns', async ({
    page,
  }) => {
    const id = await ensurePipeline(page, accountId, TEST_PIPELINE_NAME);

    await pipelineBoard.navigateToBoard(accountId, id);
    for (const stageName of ['Pendente', 'Follow-up', 'Proposta', 'Finalizado']) {
      await expect(
        page.getByRole('list', { name: stageName })
      ).toBeVisible();
    }
  });

  test('dragging a card from Pendente to Follow-up persists the move', async ({
    page,
  }) => {
    const id = await ensurePipeline(page, accountId, TEST_PIPELINE_NAME);

    const stages = await fetchStages(page, accountId, id);
    const pendente = stages.find(s => s.name === 'Pendente')!;
    const followUp = stages.find(s => s.name === 'Follow-up')!;
    expect(pendente).toBeDefined();
    expect(followUp).toBeDefined();

    const conversationId = await createConversationInStage(
      page,
      accountId,
      pendente.id
    );

    await pipelineBoard.navigateToBoard(accountId, id);

    const card = pipelineBoard.getCard('Pendente', /.+/);
    await expect(card).toBeVisible();

    const contactName =
      (await card.getAttribute('aria-label'))?.split(',')[0] ?? '';
    expect(contactName.length).toBeGreaterThan(0);

    await pipelineBoard.dragCardToStage({
      fromStage: 'Pendente',
      toStage: 'Follow-up',
      contactName,
      conversationId,
    });

    await expect
      .poll(
        async () => fetchConversationStageId(page, accountId, conversationId),
        { timeout: 10_000, message: 'pipeline_stage_id never updated to Follow-up' }
      )
      .toBe(followUp.id);

    await expect(
      pipelineBoard.getCard('Follow-up', contactName)
    ).toBeVisible();
    await expect(
      pipelineBoard.getCard('Pendente', contactName)
    ).toHaveCount(0);
  });
});

// ---------- helpers ----------

type DashboardApi = {
  get: (url: string) => Promise<unknown>;
  post: (url: string, data?: unknown) => Promise<unknown>;
  patch: (url: string, data?: unknown) => Promise<unknown>;
  delete: (url: string) => Promise<unknown>;
};

type StagePayload = { id: number; name: string; position: number };
type PipelinePayload = {
  id: number;
  name: string;
  stages: StagePayload[];
};

async function assertPipelineFeatureEnabled(page: Page, accountId: number) {
  const status = await page.evaluate(async (id: number) => {
    const api = (window as typeof window & { axios: DashboardApi }).axios;
    try {
      const res = (await api.get(`/api/v1/accounts/${id}/pipelines`)) as {
        status: number;
      };
      return res.status;
    } catch (err) {
      return (err as { response?: { status?: number } }).response?.status ?? 0;
    }
  }, accountId);

  if (status !== 200) {
    throw new Error(
      `Pipeline feature flag not enabled for account ${accountId} (pipelines endpoint returned ${status}). ` +
        'Enable with: bundle exec rails runner "Account.find(' +
        accountId +
        ').enable_features!(\'pipeline\').save!"'
    );
  }
}

async function findPipelineByName(
  page: Page,
  accountId: number,
  name: string
): Promise<number | null> {
  return page.evaluate(
    async ({ id, pipelineName }) => {
      const api = (window as typeof window & { axios: DashboardApi }).axios;
      const res = (await api.get(`/api/v1/accounts/${id}/pipelines`)) as {
        data: PipelinePayload[];
      };
      const match = res.data.find(p => p.name === pipelineName);
      return match?.id ?? null;
    },
    { id: accountId, pipelineName: name }
  );
}

async function cleanPipelineByName(
  page: Page,
  accountId: number,
  name: string
) {
  const existing = await findPipelineByName(page, accountId, name);
  if (existing === null) return;
  await archivePipeline(page, accountId, existing);
}

async function archivePipeline(page: Page, accountId: number, pipelineId: number) {
  await page.evaluate(
    async ({ id, pipelineId: pid }) => {
      const api = (window as typeof window & { axios: DashboardApi }).axios;
      await api.delete(`/api/v1/accounts/${id}/pipelines/${pid}`);
    },
    { id: accountId, pipelineId }
  );
}

async function ensurePipeline(
  page: Page,
  accountId: number,
  name: string
): Promise<number> {
  const existing = await findPipelineByName(page, accountId, name);
  if (existing !== null) return existing;

  return page.evaluate(
    async ({ id, pipelineName }) => {
      const api = (window as typeof window & { axios: DashboardApi }).axios;
      const res = (await api.post(`/api/v1/accounts/${id}/pipelines`, {
        pipeline: { name: pipelineName },
      })) as { data: PipelinePayload };
      return res.data.id;
    },
    { id: accountId, pipelineName: name }
  );
}

async function fetchStages(
  page: Page,
  accountId: number,
  pipelineId: number
): Promise<StagePayload[]> {
  return page.evaluate(
    async ({ id, pipelineId: pid }) => {
      const api = (window as typeof window & { axios: DashboardApi }).axios;
      const res = (await api.get(
        `/api/v1/accounts/${id}/pipelines/${pid}`
      )) as { data: PipelinePayload };
      return res.data.stages;
    },
    { id: accountId, pipelineId }
  );
}

async function createConversationInStage(
  page: Page,
  accountId: number,
  pipelineStageId: number
): Promise<number> {
  return page.evaluate(
    async ({ id, pipelineStageId: stageId }) => {
      const api = (window as typeof window & { axios: DashboardApi }).axios;
      const inboxesRes = (await api.get(
        `/api/v1/accounts/${id}/inboxes`
      )) as { data: { payload: Array<{ id: number }> } };
      const inbox = inboxesRes.data.payload?.[0];
      if (!inbox) throw new Error('No inbox available in the test account');

      const contactRes = (await api.post(
        `/api/v1/accounts/${id}/contacts`,
        { name: `PipelineE2E ${Date.now()}` }
      )) as { data: { id: number } };

      const convRes = (await api.post(
        `/api/v1/accounts/${id}/conversations`,
        {
          inbox_id: inbox.id,
          contact_id: contactRes.data.id,
        }
      )) as { data: { id: number } };

      await api.post(
        `/api/v1/accounts/${id}/conversations/${convRes.data.id}/pipeline_stage`,
        { pipeline_stage_id: stageId }
      );

      return convRes.data.id;
    },
    { id: accountId, pipelineStageId }
  );
}

async function fetchConversationStageId(
  page: Page,
  accountId: number,
  conversationId: number
): Promise<number | null> {
  return page.evaluate(
    async ({ id, conversationId: cid }) => {
      const api = (window as typeof window & { axios: DashboardApi }).axios;
      try {
        const res = (await api.get(
          `/api/v1/accounts/${id}/conversations/${cid}`
        )) as { data: { pipeline_stage_id: number | null } };
        return res.data.pipeline_stage_id ?? null;
      } catch {
        return null;
      }
    },
    { id: accountId, conversationId }
  );
}
