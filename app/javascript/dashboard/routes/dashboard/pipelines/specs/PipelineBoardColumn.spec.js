import { mount } from '@vue/test-utils';
import { describe, expect, it, vi, beforeAll } from 'vitest';
import { withFullI18n } from 'test-i18n';
import PipelineBoardColumn from '../components/PipelineBoardColumn.vue';

withFullI18n();

beforeAll(() => {
  global.ResizeObserver = vi.fn().mockImplementation(() => ({
    observe: vi.fn(),
    unobserve: vi.fn(),
    disconnect: vi.fn(),
  }));
});

vi.mock('virtua/vue', () => ({
  Virtualizer: {
    name: 'Virtualizer',
    props: ['data'],
    template:
      '<div><slot v-for="item in data" :key="item.id" :item="item" /></div>',
  },
}));

const stage = {
  id: 10,
  name: 'Pendente',
  color: '#6B7280',
  position: 1,
};

const conversations = [
  {
    id: 101,
    status: 'open',
    pipeline_stage_id: 10,
    meta: { sender: { name: 'Alice' } },
    messages: [],
  },
  {
    id: 102,
    status: 'pending',
    pipeline_stage_id: 10,
    meta: { sender: { name: 'Bob' } },
    messages: [],
  },
];

const mountColumn = (props = {}) =>
  mount(PipelineBoardColumn, {
    props: {
      stage,
      conversations: [],
      loading: false,
      hasMore: false,
      ...props,
    },
    global: {
      stubs: {
        Icon: { template: '<span data-testid="icon" />' },
        PipelineBoardCard: {
          props: ['conversation', 'stage'],
          template:
            '<div data-testid="board-card">{{ conversation.meta.sender.name }}</div>',
        },
      },
    },
  });

describe('PipelineBoardColumn', () => {
  it('renders stage header, color and conversation count', () => {
    const wrapper = mountColumn({ conversations });

    expect(wrapper.text()).toContain('Pendente');
    expect(wrapper.text()).toContain('2');
  });

  it('shows empty state when there are no conversations and not loading', () => {
    const wrapper = mountColumn({ conversations: [] });

    expect(wrapper.text()).toContain('No conversations');
  });

  it('shows loader when loading with zero conversations', () => {
    const wrapper = mountColumn({ conversations: [], loading: true });

    expect(wrapper.find('[data-testid="icon"]').exists()).toBe(true);
  });

  it('renders virtualized cards when conversations are provided', () => {
    const wrapper = mountColumn({ conversations });

    const cards = wrapper.findAll('[data-testid="board-card"]');
    expect(cards).toHaveLength(2);
    expect(cards[0].text()).toContain('Alice');
    expect(cards[1].text()).toContain('Bob');
  });

  it('emits load-more with stage.id when clicking Load More', async () => {
    const wrapper = mountColumn({ conversations, hasMore: true });

    const button = wrapper.find('button');
    expect(button.exists()).toBe(true);
    await button.trigger('click');

    expect(wrapper.emitted('load-more')).toHaveLength(1);
    expect(wrapper.emitted('load-more')[0]).toEqual([10]);
  });

  it('emits drop event with stageId and conversationId on drop', async () => {
    const wrapper = mountColumn({ conversations });

    const dropEvent = {
      preventDefault: vi.fn(),
      dataTransfer: {
        getData: vi.fn().mockReturnValue('101'),
      },
    };

    await wrapper.find('[role="list"]').trigger('drop', dropEvent);

    expect(wrapper.emitted('drop')).toHaveLength(1);
    expect(wrapper.emitted('drop')[0][0]).toEqual({
      stageId: 10,
      conversationId: 101,
    });
  });

  it('handles dragover event with preventDefault', async () => {
    const wrapper = mountColumn({ conversations });

    const dragOverEvent = {
      preventDefault: vi.fn(),
      dataTransfer: { dropEffect: '' },
    };

    await wrapper.find('[role="list"]').trigger('dragover', dragOverEvent);

    expect(dragOverEvent.dataTransfer.dropEffect).toBe('move');
  });

  it('emits load-more when the sentinel intersects near the end', async () => {
    // Scroll infinito: o sentinel observa com rootMargin 400px e dispara o
    // `load-more` existente; o botão continua como fallback.
    const callbacks = [];
    const observe = vi.fn();
    const disconnect = vi.fn();
    vi.stubGlobal(
      'IntersectionObserver',
      vi.fn(cb => {
        callbacks.push(cb);
        return { observe, disconnect };
      })
    );
    try {
      const wrapper = mountColumn({ conversations, hasMore: true });
      expect(observe).toHaveBeenCalledTimes(1);

      callbacks[0]([{ isIntersecting: true }]);
      expect(wrapper.emitted('load-more')).toHaveLength(1);
      expect(wrapper.emitted('load-more')[0]).toEqual([10]);

      wrapper.unmount();
      expect(disconnect).toHaveBeenCalled();
    } finally {
      vi.unstubAllGlobals();
    }
  });

  it('does not emit load-more from the sentinel while loading or without more pages', async () => {
    const callbacks = [];
    const observe = vi.fn();
    vi.stubGlobal(
      'IntersectionObserver',
      vi.fn(cb => {
        callbacks.push(cb);
        return { observe, disconnect: vi.fn() };
      })
    );
    try {
      const loadingWrapper = mountColumn({
        conversations,
        hasMore: true,
        loading: true,
      });
      callbacks[callbacks.length - 1]([{ isIntersecting: true }]);
      expect(loadingWrapper.emitted('load-more')).toBeUndefined();

      const doneWrapper = mountColumn({ conversations, hasMore: false });
      callbacks[callbacks.length - 1]([{ isIntersecting: true }]);
      expect(doneWrapper.emitted('load-more')).toBeUndefined();
    } finally {
      vi.unstubAllGlobals();
    }
  });
});
