import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import { vi } from 'vitest';
import PipelineBoard from '../pages/PipelineBoard.vue';

const mockPipelinesShow = vi.fn();
const mockStageConversations = vi.fn();
const mockMoveToStage = vi.fn();

vi.mock('dashboard/api/pipelines', () => ({
  default: {
    show: (...args) => mockPipelinesShow(...args),
    stageConversations: (...args) => mockStageConversations(...args),
  },
}));

vi.mock('dashboard/api/inbox/conversation', () => ({
  default: {
    moveToStage: (...args) => mockMoveToStage(...args),
  },
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: getter => {
    if (getter === 'inboxes/getInboxes') return ref([]);
    if (getter === 'agents/getAgents') return ref([]);
    if (getter === 'labels/getLabels') return ref([]);
    return ref(null);
  },
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('shared/helpers/mitt', () => ({
  emitter: { on: vi.fn(), off: vi.fn() },
}));

const mockRoute = ref({
  params: { accountId: '1', pipelineId: '1' },
});

vi.mock('vue-router', () => ({
  useRoute: () => mockRoute.value,
  useRouter: () => ({ push: vi.fn() }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const pipelineData = {
  id: 1,
  name: 'Sales Pipeline',
  stages: [
    {
      id: 10,
      name: 'Pendente',
      color: '#6B7280',
      position: 1,
      conversations_count: 2,
    },
    {
      id: 20,
      name: 'Follow-up',
      color: '#3B82F6',
      position: 2,
      conversations_count: 1,
    },
  ],
};

const stageConversations = {
  10: [
    {
      id: 100,
      status: 'open',
      pipeline_stage_id: 10,
      pipeline_stage_changed_at: new Date().toISOString(),
      meta: { sender: { name: 'Alice', thumbnail: '' } },
      messages: [{ content: 'Hello there' }],
    },
    {
      id: 101,
      status: 'pending',
      pipeline_stage_id: 10,
      pipeline_stage_changed_at: new Date().toISOString(),
      meta: { sender: { name: 'Bob', thumbnail: '' } },
      messages: [{ content: 'Need follow-up' }],
    },
  ],
  20: [
    {
      id: 200,
      status: 'open',
      pipeline_stage_id: 20,
      pipeline_stage_changed_at: new Date().toISOString(),
      meta: { sender: { name: 'Charlie', thumbnail: '' } },
      messages: [{ content: 'Proposal sent' }],
    },
  ],
};

const mountComponent = () =>
  mount(PipelineBoard, {
    global: {
      stubs: {
        Icon: { template: '<span />' },
        SidePanel: { template: '<div />' },
        PipelineBoardColumn: {
          props: ['stage', 'conversations', 'loading', 'hasMore'],
          emits: ['drop', 'open-card', 'load-more'],
          template:
            '<div data-testid="column" :data-stage-id="stage.id" @drop="$emit(\'drop\', { stageId: stage.id, conversationId: 100 })" />',
        },
      },
    },
  });

describe('PipelineBoard', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockPipelinesShow.mockResolvedValue({ data: pipelineData });
    // Espelha o shape real do endpoint (json.data { meta, payload }).
    mockStageConversations.mockImplementation((_pipelineId, stageId) =>
      Promise.resolve({
        data: {
          data: {
            payload: stageConversations[stageId] ?? [],
            meta: { all_count: stageConversations[stageId]?.length ?? 0 },
          },
        },
      })
    );
    mockMoveToStage.mockResolvedValue({});
  });

  it('renders one column per stage with correct stage data', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    const columns = wrapper.findAll('[data-testid="column"]');
    expect(columns).toHaveLength(2);
    expect(columns[0].attributes('data-stage-id')).toBe('10');
    expect(columns[1].attributes('data-stage-id')).toBe('20');
  });

  it('fetches conversations for each stage on mount', async () => {
    mountComponent();
    await flushPromises();

    expect(mockStageConversations).toHaveBeenCalledWith(
      '1',
      10,
      expect.objectContaining({ page: 1 })
    );
    expect(mockStageConversations).toHaveBeenCalledWith(
      '1',
      20,
      expect.objectContaining({ page: 1 })
    );
  });

  it('calls moveToStage with correct args when a card is dropped', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    // Drop on the second column (stage 20) — conversation 100 lives in stage 10
    const columns = wrapper.findAll('[data-testid="column"]');
    await columns[1].trigger('drop');

    await flushPromises();

    expect(mockMoveToStage).toHaveBeenCalledWith({
      conversationId: 100,
      pipelineStageId: 20,
    });
  });

  it('re-fetches conversations when filters change', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    const initialCallCount = mockStageConversations.mock.calls.length;

    const assigneeSelect = wrapper.find(
      'select[aria-label="PIPELINES.BOARD.FILTER.ASSIGNEE"]'
    );
    await assigneeSelect.setValue('42');

    await flushPromises();

    // Each filter change re-fetches all columns
    expect(mockStageConversations.mock.calls.length).toBeGreaterThan(
      initialCallCount
    );
  });
});
