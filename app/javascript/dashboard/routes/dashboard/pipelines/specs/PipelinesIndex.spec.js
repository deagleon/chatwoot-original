import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import PipelinesIndex from '../pages/PipelinesIndex.vue';

const mockPipelines = ref([]);
const mockUIFlags = ref({
  isFetching: false,
  isCreating: false,
  isUpdating: false,
  isDeleting: false,
});

const mockDispatch = vi.fn();

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: mockDispatch }),
  useMapGetter: getter => {
    if (getter === 'pipelines/getPipelines') return mockPipelines;
    if (getter === 'pipelines/getUIFlags') return mockUIFlags;
    return ref(null);
  },
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('vue-router', () => ({
  useRouter: () => ({ push: vi.fn() }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const mountComponent = () =>
  mount(PipelinesIndex, {
    global: {
      stubs: {
        Button: {
          props: [
            'label',
            'icon',
            'size',
            'variant',
            'color',
            'isLoading',
            'disabled',
          ],
          emits: ['click'],
          template:
            '<button @click="$emit(\'click\')"><slot />{{ label }}</button>',
        },
        Spinner: { template: '<div class="spinner" />' },
        Dialog: {
          props: [
            'type',
            'title',
            'description',
            'confirmButtonLabel',
            'isLoading',
            'disableConfirmButton',
          ],
          emits: ['confirm', 'close'],
          template: '<div class="dialog-stub" />',
        },
        PipelineFormModal: {
          props: [],
          emits: ['close'],
          methods: { open: vi.fn() },
          template: '<div class="form-modal-stub" />',
        },
      },
    },
  });

describe('PipelinesIndex', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockPipelines.value = [];
    mockUIFlags.value = {
      isFetching: false,
      isCreating: false,
      isUpdating: false,
      isDeleting: false,
    };
  });

  it('dispatches pipelines/get on mount', async () => {
    mountComponent();
    await flushPromises();

    expect(mockDispatch).toHaveBeenCalledWith('pipelines/get');
  });

  it('renders the empty state when there are no pipelines', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.find('[data-testid="pipelines-empty-state"]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-testid="pipelines-table"]').exists()).toBe(
      false
    );
  });

  it('renders the table when pipelines exist', async () => {
    mockPipelines.value = [
      {
        id: 1,
        name: 'Sales Pipeline',
        archived_at: null,
        stages: [
          { id: 1, name: 'Pendente', conversations_count: 3 },
          { id: 2, name: 'Follow-up', conversations_count: 1 },
        ],
      },
    ];

    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.find('[data-testid="pipelines-empty-state"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-testid="pipelines-table"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="pipeline-row"]').exists()).toBe(true);
    expect(wrapper.text()).toContain('Sales Pipeline');
  });

  it('shows the spinner while fetching and no pipelines exist', async () => {
    mockUIFlags.value.isFetching = true;

    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.find('.spinner').exists()).toBe(true);
    expect(wrapper.find('[data-testid="pipelines-table"]').exists()).toBe(
      false
    );
  });

  it('renders multiple pipeline rows', async () => {
    mockPipelines.value = [
      {
        id: 1,
        name: 'Sales',
        archived_at: null,
        stages: [{ id: 1, name: 'New', conversations_count: 0 }],
      },
      {
        id: 2,
        name: 'Support',
        archived_at: null,
        stages: [
          { id: 2, name: 'Open', conversations_count: 5 },
          { id: 3, name: 'Closed', conversations_count: 10 },
        ],
      },
    ];

    const wrapper = mountComponent();
    await flushPromises();

    const rows = wrapper.findAll('[data-testid="pipeline-row"]');
    expect(rows).toHaveLength(2);
    expect(wrapper.text()).toContain('Sales');
    expect(wrapper.text()).toContain('Support');
  });

  it('filters pipelines by search query', async () => {
    mockPipelines.value = [
      {
        id: 1,
        name: 'Sales Pipeline',
        archived_at: null,
        stages: [],
      },
      {
        id: 2,
        name: 'Support Pipeline',
        archived_at: null,
        stages: [],
      },
    ];

    const wrapper = mountComponent();
    await flushPromises();

    const searchInput = wrapper.find('input[type="text"]');
    await searchInput.setValue('Sales');

    const rows = wrapper.findAll('[data-testid="pipeline-row"]');
    expect(rows).toHaveLength(1);
    expect(wrapper.text()).toContain('Sales Pipeline');
    expect(wrapper.text()).not.toContain('Support Pipeline');
  });

  it('shows archived pipelines when toggle is enabled', async () => {
    mockPipelines.value = [
      {
        id: 1,
        name: 'Active Pipeline',
        archived_at: null,
        stages: [],
      },
      {
        id: 2,
        name: 'Archived Pipeline',
        archived_at: '2026-01-01T00:00:00Z',
        stages: [],
      },
    ];

    const wrapper = mountComponent();
    await flushPromises();

    // Only active pipeline visible by default
    let rows = wrapper.findAll('[data-testid="pipeline-row"]');
    expect(rows).toHaveLength(1);
    expect(wrapper.text()).toContain('Active Pipeline');

    // Toggle show archived
    const buttons = wrapper.findAll('button');
    const showArchivedBtn = buttons.find(b =>
      b.text().includes('PIPELINES.SHOW_ARCHIVED')
    );
    await showArchivedBtn.trigger('click');

    rows = wrapper.findAll('[data-testid="pipeline-row"]');
    expect(rows).toHaveLength(2);
    expect(wrapper.text()).toContain('Archived Pipeline');
  });
});
