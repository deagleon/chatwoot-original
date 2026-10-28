import { Page, expect } from '@playwright/test';

const DEFAULT_STAGE_NAMES = ['Pendente', 'Follow-up', 'Proposta', 'Finalizado'];

/**
 * Page object for the Pipeline list page (`/app/accounts/:accountId/pipelines`)
 * and the Kanban board (`/app/accounts/:accountId/pipelines/:pipelineId`).
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
      `/app/accounts/${accountId}/pipelines/${pipelineId}`
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
    // O header e o empty state têm o mesmo botão "New pipeline" — .first()
    // evita strict mode violation quando a lista está vazia.
    return this.page.getByRole('button', { name: /new pipeline/i }).first();
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
    // dragend ANTES do drop: o drop move o card otimisticamente para a coluna
    // alvo, e o dispatch no card de origem falharia com o elemento removido.
    await card.dispatchEvent('dragend', { dataTransfer: transfer });
    await target.dispatchEvent('drop', { dataTransfer: transfer });

    // Sanity check that the JS-side dispatch carried the payload the
    // PipelineBoardColumn handler expects (conversation id as text/plain).
    const carriedId = await transfer.evaluate(
      (dt: DataTransfer) => dt.getData('text/plain')
    );
    expect(carriedId).toBe(String(conversationId));
  }
}
