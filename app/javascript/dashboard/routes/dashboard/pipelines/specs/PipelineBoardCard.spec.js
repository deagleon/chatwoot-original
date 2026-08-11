import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { describe, expect, it, vi, beforeEach } from 'vitest';
import { nextTick } from 'vue';
import { withFullI18n } from 'test-i18n';

import PipelineBoardCard from '../components/PipelineBoardCard.vue';

withFullI18n();

const conversation = {
  id: 100,
  display_id: 100,
  status: 'open',
  priority: null,
  unread_count: 2,
  inbox_id: 1,
  labels: ['support'],
  pipeline_stage_changed_at: new Date().toISOString(),
  meta: { sender: { name: 'Jane Doe' } },
  messages: [],
};

const mountCard = () => {
  const store = createStore({
    getters: {
      getCurrentAccountId: () => 1,
      getCurrentUser: () => ({ id: 1 }),
      getCurrentRole: () => 'agent',
    },
    modules: {
      labels: {
        namespaced: true,
        getters: { getLabels: () => [] },
      },
      teams: {
        namespaced: true,
        getters: { getTeams: () => [] },
      },
      inboxAssignableAgents: {
        namespaced: true,
        getters: {
          getUIFlags: () => ({ isFetching: false }),
          getAssignableAgents: () => () => [],
        },
      },
    },
  });
  store.dispatch = vi.fn();
  store.commit = vi.fn();

  return mount(PipelineBoardCard, {
    props: { conversation, stage: { id: 10, name: 'Pendente' } },
    global: {
      plugins: [store],
      // O ContextMenu usa teleport para o body; stubamos para o menu renderizar
      // dentro do wrapper e o teste não depender do document.
      stubs: {
        ContextMenu: {
          template: '<div data-testid="context-menu"><slot /></div>',
        },
        TeleportWithDirection: {
          template: '<div><slot /></div>',
        },
      },
    },
  });
};

const openMenu = async wrapper => {
  await wrapper
    .get('[role="button"]')
    .trigger('contextmenu', { clientX: 120, clientY: 80 });
  await nextTick();
};

const clickMenuItem = async (wrapper, label) => {
  await openMenu(wrapper);
  const items = wrapper
    .findAll('div')
    .filter(el => el.text()?.trim() === label);
  expect(items.length).toBeGreaterThan(0);
  items[items.length - 1].trigger('click');
  await nextTick();
};

describe('PipelineBoardCard', () => {
  let wrapper;

  beforeEach(() => {
    wrapper = mountCard();
  });

  it('renders the contact name and stage status', () => {
    expect(wrapper.get('[role="button"]').attributes('aria-label')).toContain(
      'Jane Doe'
    );
  });

  it('opens the context menu on right click with the conversation actions', async () => {
    await openMenu(wrapper);

    expect(wrapper.get('[data-testid="context-menu"]').text()).toContain(
      'Open conversation'
    );
    // unread_count > 0 → o menu oferece marcar como lida.
    expect(wrapper.get('[data-testid="context-menu"]').text()).toContain(
      'Mark as read'
    );
    expect(wrapper.get('[data-testid="context-menu"]').text()).toContain(
      'Mark as resolved'
    );
  });

  it('emits open-conversation when the menu action is clicked', async () => {
    await clickMenuItem(wrapper, 'Open conversation');

    expect(wrapper.emitted('openConversation')).toHaveLength(1);
    expect(wrapper.emitted('openConversation')[0][0]).toEqual(conversation);
  });

  it('dispatches toggleStatus when resolving from the menu', async () => {
    await clickMenuItem(wrapper, 'Mark as resolved');

    expect(wrapper.vm.$store.dispatch).toHaveBeenCalledWith('toggleStatus', {
      conversationId: 100,
      status: 'resolved',
      snoozedUntil: null,
    });
  });
});
