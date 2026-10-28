import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import { vi } from 'vitest';
import PipelineBoard from '../pages/PipelineBoard.vue';
import { BUS_EVENTS } from 'shared/constants/busEvents';

const mockPipelinesShow = vi.fn();
const mockStageConversations = vi.fn();
const mockMoveToStage = vi.fn();

vi.mock('dashboard/api/pipelines', () => ({
  default: {
    show: (...args) => mockPipelinesShow(...args),
    stageConversations: (...args) => mockStageConversations(...args),
  },
}));

const mockConversationShow = vi.fn();

vi.mock('dashboard/api/inbox/conversation', () => ({
  default: {
    moveToStage: (...args) => mockMoveToStage(...args),
    show: (...args) => mockConversationShow(...args),
  },
}));

const { mockStoreDispatch, mockStoreCommit } = vi.hoisted(() => ({
  mockStoreDispatch: vi.fn(),
  mockStoreCommit: vi.fn(),
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    state: { conversations: { allConversations: [] } },
    dispatch: mockStoreDispatch,
    commit: mockStoreCommit,
  }),
  useMapGetter: getter => {
    if (getter === 'inboxes/getInboxes') return ref([]);
    if (getter === 'agents/getAgents') return ref([]);
    if (getter === 'labels/getLabels') return ref([]);
    if (getter === 'getCurrentAccountId') return ref(1);
    if (getter === 'accounts/isFeatureEnabledonAccount')
      return ref(() => false);
    return ref(null);
  },
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

const { emitterHandlers } = vi.hoisted(() => ({ emitterHandlers: {} }));

vi.mock('shared/helpers/mitt', () => ({
  emitter: {
    on: vi.fn((event, handler) => {
      emitterHandlers[event] = handler;
    }),
    off: vi.fn(event => {
      delete emitterHandlers[event];
    }),
  },
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
        Dialog: {
          // O Dialog real é controlado por ref (open/close): o stub simula
          // para o teste validar que o board chama open() ao selecionar.
          name: 'Dialog',
          data: () => ({ isOpen: false }),
          methods: {
            open() {
              this.isOpen = true;
            },
            close() {
              this.isOpen = false;
              this.$emit('close');
            },
          },
          template:
            '<div v-if="isOpen">{{ $attrs.title }}<slot name="headerActions" /><slot /></div>',
        },
        ConversationBox: { template: '<div data-testid="conversation-box" />' },
        ContactPanel: { template: '<div data-testid="contact-panel" />' },
        CopilotContainer: {
          template: '<div data-testid="copilot-container" />',
        },
        // Listener do snooze do palete ninja-keys — headless; sem stub o
        // componente real quebra no mock de store sem getters.
        CmdBarConversationSnooze: { template: '<span />' },
        PipelineBoardColumn: {
          props: ['stage', 'conversations', 'loading', 'hasMore'],
          emits: ['drop', 'open-card', 'open-conversation', 'load-more'],
          template:
            '<div data-testid="column" :data-stage-id="stage.id" :data-conversation-ids="conversations.map(c => c.id).join(\',\')" @drop="$emit(\'drop\', { stageId: stage.id, conversationId: 100 })"><button data-testid="ctx-open" @click="$emit(\'open-conversation\', { id: 100, status: \'open\', meta: { sender: { name: \'Charlie\' } }, messages: [{ id: 1, content: \'Proposal sent\' }] })" /></div>',
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

    // ComboBox (single) emite update:modelValue quando o usuário seleciona.
    const assigneeComboBox = wrapper.findComponent({ name: 'ComboBox' });
    assigneeComboBox.vm.$emit('update:modelValue', 42);

    await flushPromises();

    // Each filter change re-fetches all columns
    expect(mockStageConversations.mock.calls.length).toBeGreaterThan(
      initialCallCount
    );
  });

  it('re-fetches conversations when a multi-select filter changes', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    const initialCallCount = mockStageConversations.mock.calls.length;

    // Filtro de status (TagMultiSelectComboBox, opções estáticas): o v-model
    // precisa receber uma referência nova para o watch do board disparar o
    // refetch (regressão: re-emitir o mesmo array mutado não atualizava).
    const statusComboBox = wrapper.findAllComponents({
      name: 'TagMultiSelectComboBox',
    })[1];
    await statusComboBox.find('div.cursor-pointer').trigger('click');
    await statusComboBox.findAll('[role="option"]')[0].trigger('click');

    await flushPromises();

    expect(mockStageConversations.mock.calls.length).toBeGreaterThan(
      initialCallCount
    );
  });

  it('opens the conversation preview dialog with the embedded conversation box', async () => {
    mockConversationShow.mockResolvedValue({
      data: { id: 100, status: 'open', meta: { sender: { name: 'Charlie' } } },
    });
    mockStoreCommit.mockClear();
    const wrapper = mountComponent();
    await flushPromises();

    await wrapper.get('[data-testid="ctx-open"]').trigger('click');
    await flushPromises();

    expect(mockConversationShow).toHaveBeenCalledWith(100);
    expect(mockStoreCommit).toHaveBeenCalledWith('SET_ALL_CONVERSATION', [
      { id: 100, status: 'open', meta: { sender: { name: 'Charlie' } } },
    ]);
    expect(mockStoreCommit).toHaveBeenCalledWith('SET_CURRENT_CHAT_WINDOW', {
      id: 100,
    });
    expect(wrapper.get('[data-testid="conversation-box"]').exists()).toBe(true);
    expect(wrapper.text()).toContain('Charlie');
  });

  it('toggles the modal-local contact panel and resets panels when the preview closes', async () => {
    mockConversationShow.mockResolvedValue({
      data: {
        id: 100,
        status: 'open',
        inbox_id: 5,
        meta: { sender: { name: 'Charlie' } },
      },
    });
    const wrapper = mountComponent();
    await flushPromises();

    await wrapper.get('[data-testid="ctx-open"]').trigger('click');
    await flushPromises();

    // Painel de contato vem ativado por padrão ao abrir o preview.
    expect(wrapper.find('[data-testid="contact-panel"]').exists()).toBe(true);

    // Fechar o preview reseta o estado local; reabrir ativa o painel de novo.
    wrapper.findComponent({ name: 'Dialog' }).vm.close();
    await flushPromises();
    expect(wrapper.find('[data-testid="contact-panel"]').exists()).toBe(false);

    await wrapper.get('[data-testid="ctx-open"]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-testid="contact-panel"]').exists()).toBe(true);
  });

  it('hides the Captain toggle when the CAPTAIN feature flag is off', async () => {
    mockConversationShow.mockResolvedValue({
      data: { id: 100, status: 'open', meta: { sender: { name: 'Charlie' } } },
    });
    const wrapper = mountComponent();
    await flushPromises();

    await wrapper.get('[data-testid="ctx-open"]').trigger('click');
    await flushPromises();

    // Mock do isFeatureEnabledonAccount devolve () => false.
    expect(
      wrapper.find('button[aria-label="CONVERSATION.SIDEBAR.COPILOT"]').exists()
    ).toBe(false);
  });

  it('inserts a live-created conversation into its stage column sorted', async () => {
    // O batch realtime (500ms) exige fake timers: o emit só enfileira, o
    // flush aplica e ordena uma única vez por coluna.
    vi.useFakeTimers();
    try {
      const wrapper = mountComponent();
      await vi.advanceTimersByTimeAsync(0);

      const initialCallCount = mockStageConversations.mock.calls.length;

      // last_activity_at mais recente que os cards existentes (que não têm o
      // campo → ordenam como 0): o card novo entra no topo da coluna.
      emitterHandlers[BUS_EVENTS.CONVERSATION_CREATED]({
        id: 300,
        status: 'open',
        inbox_id: 5,
        labels: [],
        unread_count: 1,
        pipeline_stage_id: 10,
        pipeline_stage_changed_at: new Date().toISOString(),
        last_activity_at: Math.floor(Date.now() / 1000),
        meta: { sender: { name: 'Dana', thumbnail: '' }, assignee: null },
        messages: [{ content: 'New lead' }],
      });
      // Enfileirado, ainda não aplicado.
      await vi.advanceTimersByTimeAsync(0);
      expect(
        wrapper
          .findAll('[data-testid="column"]')[0]
          .attributes('data-conversation-ids')
      ).toBe('100,101');

      await vi.advanceTimersByTimeAsync(500);
      const columns = wrapper.findAll('[data-testid="column"]');
      expect(columns[0].attributes('data-conversation-ids')).toBe(
        '300,100,101'
      );
      // Sem refetch — o card entra direto do payload do cable
      expect(mockStageConversations.mock.calls.length).toBe(initialCallCount);
    } finally {
      vi.useRealTimers();
    }
  });

  it('keeps a live-inserted card when a stage fetch is still in flight', async () => {
    // Cenário: refetch da coluna em voo quando o created chega — a resposta
    // antiga substituiria a coluna inteira e descartaria o card inserido. O
    // board invalida o request em voo (bump de seq) e agenda refetch.
    vi.useFakeTimers();
    try {
      const wrapper = mountComponent();
      await vi.advanceTimersByTimeAsync(0);

      const stage20Response = Promise.resolve({
        data: {
          data: { payload: stageConversations[20], meta: { all_count: 1 } },
        },
      });
      let resolveStale;
      const staleResponse = new Promise(resolve => {
        resolveStale = resolve;
      });
      mockStageConversations.mockImplementation((_pipelineId, stageId) =>
        stageId === 10 ? staleResponse : stage20Response
      );

      // Filter change → refetch de todas as colunas; stage 10 fica em voo.
      const assigneeComboBox = wrapper.findComponent({ name: 'ComboBox' });
      assigneeComboBox.vm.$emit('update:modelValue', 42);
      await vi.advanceTimersByTimeAsync(0);
      expect(mockStageConversations.mock.calls.length).toBe(4);

      const createdCard = {
        id: 304,
        status: 'open',
        inbox_id: 5,
        labels: [],
        unread_count: 1,
        pipeline_stage_id: 10,
        pipeline_stage_changed_at: new Date().toISOString(),
        last_activity_at: Math.floor(Date.now() / 1000),
        meta: { sender: { name: 'Dana', thumbnail: '' }, assignee: { id: 42 } },
        messages: [{ content: 'New lead' }],
      };
      emitterHandlers[BUS_EVENTS.CONVERSATION_CREATED](createdCard);
      // O emit só enfileira no batch realtime — o flush de 500ms aplica.
      await vi.advanceTimersByTimeAsync(500);

      let columns = wrapper.findAll('[data-testid="column"]');
      expect(columns[0].attributes('data-conversation-ids')).toBe(
        '304,100,101'
      );

      // A resposta antiga (sem o card) resolve: não pode sobrescrever a coluna.
      resolveStale({
        data: {
          data: { payload: stageConversations[10], meta: { all_count: 2 } },
        },
      });
      await vi.advanceTimersByTimeAsync(0);
      columns = wrapper.findAll('[data-testid="column"]');
      expect(columns[0].attributes('data-conversation-ids')).toBe(
        '304,100,101'
      );

      // Refetch debounced chega com os dados autoritativos (servidor já tem o
      // card novo) — um único fetch extra, card permanece.
      mockStageConversations.mockImplementation((_pipelineId, stageId) =>
        stageId === 10
          ? Promise.resolve({
              data: {
                data: {
                  payload: [createdCard, ...stageConversations[10]],
                  meta: { all_count: 3 },
                },
              },
            })
          : stage20Response
      );
      await vi.advanceTimersByTimeAsync(400);
      expect(mockStageConversations.mock.calls.length).toBe(5);
      columns = wrapper.findAll('[data-testid="column"]');
      expect(columns[0].attributes('data-conversation-ids')).toBe(
        '304,100,101'
      );
    } finally {
      vi.useRealTimers();
    }
  });

  it('ignores a created conversation that does not match the active filters', async () => {
    vi.useFakeTimers();
    try {
      const wrapper = mountComponent();
      await vi.advanceTimersByTimeAsync(0);

      // Filtro de status = open (mesma interação do teste de refetch de filtros)
      const statusComboBox = wrapper.findAllComponents({
        name: 'TagMultiSelectComboBox',
      })[1];
      await statusComboBox.find('div.cursor-pointer').trigger('click');
      await statusComboBox.findAll('[role="option"]')[0].trigger('click');
      await vi.advanceTimersByTimeAsync(0);

      emitterHandlers[BUS_EVENTS.CONVERSATION_CREATED]({
        id: 301,
        status: 'resolved',
        inbox_id: 5,
        labels: [],
        unread_count: 0,
        pipeline_stage_id: 10,
        pipeline_stage_changed_at: new Date().toISOString(),
        last_activity_at: Math.floor(Date.now() / 1000),
        meta: { sender: { name: 'Eve', thumbnail: '' }, assignee: null },
        messages: [],
      });
      await vi.advanceTimersByTimeAsync(500);

      const columns = wrapper.findAll('[data-testid="column"]');
      expect(columns[0].attributes('data-conversation-ids')).toBe('100,101');
    } finally {
      vi.useRealTimers();
    }
  });

  it('ignores a created conversation already present on the board', async () => {
    vi.useFakeTimers();
    try {
      const wrapper = mountComponent();
      await vi.advanceTimersByTimeAsync(0);

      // id 200 já existe na coluna do stage 20 — moves ficam com o
      // CONVERSATION_UPDATED, o created não pode duplicar o card.
      emitterHandlers[BUS_EVENTS.CONVERSATION_CREATED]({
        id: 200,
        status: 'open',
        inbox_id: 5,
        labels: [],
        unread_count: 0,
        pipeline_stage_id: 10,
        pipeline_stage_changed_at: new Date().toISOString(),
        last_activity_at: Math.floor(Date.now() / 1000),
        meta: { sender: { name: 'Charlie', thumbnail: '' }, assignee: null },
        messages: [],
      });
      await vi.advanceTimersByTimeAsync(500);

      const columns = wrapper.findAll('[data-testid="column"]');
      expect(columns[0].attributes('data-conversation-ids')).toBe('100,101');
      expect(columns[1].attributes('data-conversation-ids')).toBe('200');
    } finally {
      vi.useRealTimers();
    }
  });

  it('refetches the target stage instead of inserting when search is active', async () => {
    // O refetch do created usa o mesmo debounce do input de busca — fake
    // timers para validar o coalescing e o disparo único.
    vi.useFakeTimers();
    try {
      const wrapper = mountComponent();
      await vi.advanceTimersByTimeAsync(0);

      await wrapper
        .find('input[placeholder="PIPELINES.BOARD.FILTER.SEARCH_PLACEHOLDER"]')
        .setValue('proposal');

      const initialCallCount = mockStageConversations.mock.calls.length;

      emitterHandlers[BUS_EVENTS.CONVERSATION_CREATED]({
        id: 302,
        status: 'open',
        inbox_id: 5,
        labels: [],
        unread_count: 0,
        pipeline_stage_id: 10,
        pipeline_stage_changed_at: new Date().toISOString(),
        last_activity_at: Math.floor(Date.now() / 1000),
        meta: { sender: { name: 'Frank', thumbnail: '' }, assignee: null },
        messages: [{ content: 'proposal please' }],
      });
      emitterHandlers[BUS_EVENTS.CONVERSATION_CREATED]({
        id: 303,
        status: 'open',
        inbox_id: 5,
        labels: [],
        unread_count: 0,
        pipeline_stage_id: 10,
        pipeline_stage_changed_at: new Date().toISOString(),
        last_activity_at: Math.floor(Date.now() / 1000),
        meta: { sender: { name: 'Gina', thumbnail: '' }, assignee: null },
        messages: [{ content: 'another proposal' }],
      });

      // Burst de eventos coalesce: nenhum fetch imediato (batch realtime de
      // 500ms ainda não flusheou)
      expect(mockStageConversations.mock.calls.length).toBe(initialCallCount);

      // 400ms: debounce da busca (fetchAllColumns: 2 colunas). 500ms: flush do
      // batch (aplica os created, que com q ativo só agendam refetch).
      // 900ms: refetch coalescido único da coluna alvo.
      await vi.advanceTimersByTimeAsync(1000);

      // Debounce da busca pendente (fetchAllColumns: 2 colunas) + um único
      // refetch coalescido da coluna alvo com o q ativo — sem inserção às cegas
      expect(mockStageConversations.mock.calls.length).toBe(
        initialCallCount + 3
      );
      expect(mockStageConversations).toHaveBeenLastCalledWith(
        '1',
        10,
        expect.objectContaining({ page: 1, q: 'proposal' })
      );
      const columns = wrapper.findAll('[data-testid="column"]');
      expect(columns[0].attributes('data-conversation-ids')).toBe('100,101');
    } finally {
      vi.useRealTimers();
    }
  });

  it('inserts an updated conversation into its stage when not previously on the board', async () => {
    vi.useFakeTimers();
    try {
      const wrapper = mountComponent();
      await vi.advanceTimersByTimeAsync(0);

      const initialCallCount = mockStageConversations.mock.calls.length;

      // Cenário: conversa nova foi criada sem estágio e agora uma regra de automação
      // disparou move_to_stage (ou agente moveu via menu de contexto).
      emitterHandlers[BUS_EVENTS.CONVERSATION_UPDATED]({
        id: 305,
        status: 'open',
        inbox_id: 5,
        labels: [],
        unread_count: 1,
        pipeline_stage_id: 10,
        pipeline_stage_changed_at: new Date().toISOString(),
        last_activity_at: Math.floor(Date.now() / 1000),
        meta: { sender: { name: 'Helen', thumbnail: '' }, assignee: null },
        messages: [{ content: 'Lead from automation' }],
      });
      await vi.advanceTimersByTimeAsync(500);

      const columns = wrapper.findAll('[data-testid="column"]');
      expect(columns[0].attributes('data-conversation-ids')).toBe(
        '305,100,101'
      );
      expect(mockStageConversations.mock.calls.length).toBe(initialCallCount);
    } finally {
      vi.useRealTimers();
    }
  });

  it('removes an existing card when updated to no longer match active filters', async () => {
    vi.useFakeTimers();
    try {
      const wrapper = mountComponent();
      await vi.advanceTimersByTimeAsync(0);

      // Filtro de status = open
      const statusComboBox = wrapper.findAllComponents({
        name: 'TagMultiSelectComboBox',
      })[1];
      await statusComboBox.find('div.cursor-pointer').trigger('click');
      await statusComboBox.findAll('[role="option"]')[0].trigger('click');
      await vi.advanceTimersByTimeAsync(0);

      let columns = wrapper.findAll('[data-testid="column"]');
      expect(columns[0].attributes('data-conversation-ids')).toBe('100,101');

      // Conversa 100 é resolvida: deve sair da coluna
      emitterHandlers[BUS_EVENTS.CONVERSATION_UPDATED]({
        id: 100,
        status: 'resolved',
        inbox_id: 5,
        labels: [],
        unread_count: 0,
        pipeline_stage_id: 10,
        pipeline_stage_changed_at: new Date().toISOString(),
        last_activity_at: Math.floor(Date.now() / 1000),
        meta: { sender: { name: 'Alice', thumbnail: '' }, assignee: null },
        messages: [],
      });
      await vi.advanceTimersByTimeAsync(500);

      columns = wrapper.findAll('[data-testid="column"]');
      expect(columns[0].attributes('data-conversation-ids')).toBe('101');
    } finally {
      vi.useRealTimers();
    }
  });

  it('ignores an updated conversation whose new stage belongs to another pipeline', async () => {
    vi.useFakeTimers();
    try {
      const wrapper = mountComponent();
      await vi.advanceTimersByTimeAsync(0);

      // Conversa atualizada com stage 999 que não existe nas colunas deste board
      emitterHandlers[BUS_EVENTS.CONVERSATION_UPDATED]({
        id: 306,
        status: 'open',
        inbox_id: 5,
        labels: [],
        unread_count: 0,
        pipeline_stage_id: 999,
        pipeline_stage_changed_at: new Date().toISOString(),
        last_activity_at: Math.floor(Date.now() / 1000),
        meta: { sender: { name: 'Ian', thumbnail: '' }, assignee: null },
        messages: [],
      });
      await vi.advanceTimersByTimeAsync(500);

      const columns = wrapper.findAll('[data-testid="column"]');
      expect(columns[0].attributes('data-conversation-ids')).toBe('100,101');
      expect(columns[1].attributes('data-conversation-ids')).toBe('200');
    } finally {
      vi.useRealTimers();
    }
  });

  it('applies a mixed realtime burst in a single flush per column', async () => {
    // Rajada de 50 eventos (25 created + 25 messages em 2 colunas): nada
    // aplica antes do flush de 500ms; depois, tudo de uma vez com 1 sort por
    // coluna — preview/unread finais corretos, sem churn de re-render.
    vi.useFakeTimers();
    try {
      const wrapper = mountComponent();
      await vi.advanceTimersByTimeAsync(0);

      const base = Math.floor(Date.now() / 1000);
      for (let i = 0; i < 25; i += 1) {
        emitterHandlers[BUS_EVENTS.CONVERSATION_CREATED]({
          id: 1000 + i,
          status: 'open',
          inbox_id: 5,
          labels: [],
          unread_count: 1,
          pipeline_stage_id: 10,
          pipeline_stage_changed_at: new Date().toISOString(),
          last_activity_at: base + i,
          meta: {
            sender: { name: `Lead ${i}`, thumbnail: '' },
            assignee: null,
          },
          messages: [{ content: `hello ${i}` }],
        });
        emitterHandlers[BUS_EVENTS.MESSAGE_CREATED]({
          conversation_id: 200,
          content: `ping ${i}`,
          conversation: { unread_count: i + 1, last_activity_at: base + i },
        });
      }

      // Enfileirado: nenhum fetch e nenhuma aplicação antes do flush.
      const callsBeforeFlush = mockStageConversations.mock.calls.length;
      await vi.advanceTimersByTimeAsync(0);
      let columns = wrapper.findAll('[data-testid="column"]');
      expect(columns[0].attributes('data-conversation-ids')).toBe('100,101');
      expect(columns[1].attributes('data-conversation-ids')).toBe('200');

      await vi.advanceTimersByTimeAsync(500);
      columns = wrapper.findAll('[data-testid="column"]');
      const ids = columns[0].attributes('data-conversation-ids').split(',');
      expect(ids).toHaveLength(27);
      expect(ids.slice(0, 25)).toEqual(
        Array.from({ length: 25 }, (_, k) => String(1024 - k))
      );
      expect(ids.slice(25)).toEqual(['100', '101']);
      expect(columns[1].attributes('data-conversation-ids')).toBe('200');
      // Batch puro client-side: nenhum fetch extra de stage.
      expect(mockStageConversations.mock.calls.length).toBe(callsBeforeFlush);
    } finally {
      vi.useRealTimers();
    }
  });

  it('pauses realtime while the tab is hidden and resyncs on return', async () => {
    // Aba oculta: handlers retornam sem tocar estado e sem fetches; ao voltar,
    // resync silencioso (pages 1..N por coluna) mantém cards/ordem.
    vi.useFakeTimers();
    const hiddenDescriptor = Object.getOwnPropertyDescriptor(
      document,
      'hidden'
    );
    let hiddenValue = false;
    Object.defineProperty(document, 'hidden', {
      configurable: true,
      get: () => hiddenValue,
    });
    try {
      const wrapper = mountComponent();
      await vi.advanceTimersByTimeAsync(0);
      const callsAfterMount = mockStageConversations.mock.calls.length;

      hiddenValue = true;
      document.dispatchEvent(new Event('visibilitychange'));
      emitterHandlers[BUS_EVENTS.CONVERSATION_CREATED]({
        id: 400,
        status: 'open',
        inbox_id: 5,
        labels: [],
        unread_count: 1,
        pipeline_stage_id: 10,
        pipeline_stage_changed_at: new Date().toISOString(),
        last_activity_at: Math.floor(Date.now() / 1000),
        meta: { sender: { name: 'Ghost', thumbnail: '' }, assignee: null },
        messages: [{ content: 'while hidden' }],
      });
      await vi.advanceTimersByTimeAsync(1000);

      // Zero mutações no período: sem card novo e sem GETs de stage.
      let columns = wrapper.findAll('[data-testid="column"]');
      expect(columns[0].attributes('data-conversation-ids')).toBe('100,101');
      expect(mockStageConversations.mock.calls.length).toBe(callsAfterMount);

      // Ao voltar: resync dispara (pages 1..N por coluna) e mantém a ordem.
      // (>=: boards de testes anteriores ainda montados também resyncam no
      // evento global; o que importa é que este board dispara o dele.)
      hiddenValue = false;
      document.dispatchEvent(new Event('visibilitychange'));
      await vi.advanceTimersByTimeAsync(0);
      expect(mockStageConversations.mock.calls.length).toBeGreaterThan(
        callsAfterMount
      );
      expect(mockStageConversations).toHaveBeenCalledWith(
        '1',
        10,
        expect.objectContaining({ page: 1 })
      );
      columns = wrapper.findAll('[data-testid="column"]');
      expect(columns[0].attributes('data-conversation-ids')).toBe('100,101');
      expect(columns[1].attributes('data-conversation-ids')).toBe('200');
      wrapper.unmount();
    } finally {
      if (hiddenDescriptor) {
        Object.defineProperty(document, 'hidden', hiddenDescriptor);
      }
      vi.useRealTimers();
    }
  });
});
