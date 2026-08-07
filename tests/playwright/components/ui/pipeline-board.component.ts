import { Page, expect } from '@playwright/test';

type DashboardApi = {
  get: (url: string) => Promise<{
    data: {
      payload: Array<{
        id: number;
        pipeline_stage_id: number | null;
        meta?: { sender?: { name?: string } };
      }>;
    };
  }>;
  post: (url: string, data?: unknown) => Promise<unknown>;
  patch: (url: string, data?: unknown) => Promise<unknown>;
};

type PipelinePayload = {
  id: number;
  name: string;
  stages: Array<{ id: number; name: string; position: number }>;
};

const DEFAULT_STAGE_NAMES = ['Pendente', 'Follow-up', 'Proposta', 'Finalizado'];

/**
 * Page object for the Pipeline list page (`/app/accounts/:accountId/pipelines`)
 * and the Kanban board (`/app/accounts/:accountId/pipelines/:pipelineId/board`).
 *
 * Selectors rely on the existing `role`/`aria-label` attributes already shipped
 * on PipelineBoardColumn (`role="list"`, `aria-label="<stage name>"`) and
 * PipelineBoardCard (`role="button"`, `aria-label="<contact>, <stage>, <status>"`),
 * plus the `data-testid` attributes on PipelinesIndex.
 */
export class PipelineBoard {
  constructor(private page: Page) {}

  // ---------- Navigation ----------

  async navigateToList(accountId: number) {
    await this.page.goto(`/app/accounts/${accountId}/pipelines`);
  }

  async navigateToBoard(accountId: number, pipelineId: number) {
    await this.page.goto(
      `/app/accounts/${accountId}/pipelines/${pipelineId}/board`
    );
  }

  // ---------- Pipelines list ----------

  getPipelinesTable() {
    return this.page.getByTestId('pipelines-table');
  }

  getEmptyState() {
    return this.page.getByTestId('pipelines-empty-state');
  }

  getPipelineRow(name: string) {
    return this.page
      .getByTestId('pipeline-row')
      .filter({ hasText: name });
  }

  getCreatePipelineButton() {
    return this.page.getByRole('button', { name: /create pipeline/i });
  }

  async openCreatePipelineModal() {
    await this.getCreatePipelineButton().click();
  }

  // ---------- Form modal (PipelineFormModal) ----------

  getCreatePipelineDialog() {
    return this.page.getByRole('dialog', { name: 'Create pipeline' });
  }

  getPipelineNameInput() {
    return this.getCreatePipelineDialog().getByLabel('Name');
  }

  getCreatePipelineSubmitButton() {
    return this.getCreatePipelineDialog().getByRole('button', {
      name: 'Create',
    });
  }

  async createPipelineViaModal(name: string) {
    await this.openCreatePipelineModal();
    await this.getPipelineNameInput().fill(name);
    await this.getCreatePipelineSubmitButton().click();
    await expect(this.getPipelineRow(name)).toBeVisible();
  }

  // ---------- Board columns & cards ----------

  getColumn(stageName: string) {
    return this.page.getByRole('list', { name: stageName });
  }

  getAllDefaultStageColumns() {
    return DEFAULT_STAGE_NAMES.map(name => this.getColumn(name));
  }

  getCard(stageName: string, contactName: string) {
    return this.getColumn(stageName).getByRole('button', {
      name: new RegExp(contactName),
    });
  }

  async expectDefaultStagesVisible() {
    for (const name of DEFAULT_STAGE_NAMES) {
      await expect(this.getColumn(name)).toBeVisible();
    }
  }

  // ---------- Drag & drop ----------
  //
  // PipelineBoardCard uses native HTML5 DnD: `draggable="true"` and writes the
  // conversation id into `dataTransfer.setData('text/plain', String(id))`.
  // Playwright's `dragTo` is unreliable with HTML5 DnD, so we dispatch the
  // matching events directly on the source/target with a shared DataTransfer
  // payload.

  async dragCardToStage(opts: {
    fromStage: string;
    toStage: string;
    contactName: string;
    conversationId: number;
  }) {
    const { fromStage, toStage, contactName, conversationId } = opts;

    const card = this.getCard(fromStage, contactName);
    const target = this.getColumn(toStage);

    await card.scrollIntoViewIfNeeded();
    await target.scrollIntoViewIfNeeded();

    const transfer = await this.page.evaluateHandle(
      () => new DataTransfer()
    );

    await card.dispatchEvent('dragstart', { dataTransfer: transfer });
    await target.dispatchEvent('dragover', { dataTransfer: transfer });
    await target.dispatchEvent('drop', { dataTransfer: transfer });
    await card.dispatchEvent('dragend', { dataTransfer: transfer });

    // Sanity check that the JS-side dispatch carried the payload the
    // PipelineBoardColumn handler expects (conversation id as text/plain).
    const carriedId = await transfer.evaluate(
      (dt: DataTransfer) => dt.getData('text/plain')
    );
    expect(carriedId).toBe(String(conversationId));
  }

  // ---------- API helpers (via window.axios) ----------

  async fetchPipelines(accountId: number): Promise<PipelinePayload[]> {
    return this.page.evaluate(async (id: number) => {
      const api = (window as typeof window & { axios: DashboardApi }).axios;
      const res = await api.get(`/api/v1/accounts/${id}/pipelines`);
      return (res as { data: PipelinePayload[] }).data;
    }, accountId);
  }

  async createPipelineViaApi(accountId: number, name: string): Promise<number> {
    return this.page.evaluate(
      async ({ id, pipelineName }) => {
        const api = (window as typeof window & { axios: DashboardApi }).axios;
        const res = (await api.post(`/api/v1/accounts/${id}/pipelines`, {
          pipeline: { name: pipelineName },
        })) as { data: { id: number } };
        return res.data.id;
      },
      { id: accountId, pipelineName: name }
    );
  }

  async fetchBoardPipelines(accountId: number): Promise<PipelinePayload[]> {
    const pipelines = await this.fetchPipelines(accountId);
    return pipelines;
  }
}
