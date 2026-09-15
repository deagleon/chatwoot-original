import { shallowMount } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createStore } from 'vuex';
import MessagesView from '../MessagesView.vue';

// useLabelSuggestions/useAccount disparam computeds que dependem de
// integrations/getAppIntegrations e da rota — fora do escopo deste spec
// (scroll), então mockamos os dois na fonte.
vi.mock('dashboard/composables/useLabelSuggestions', () => ({
  useLabelSuggestions: () => ({
    captainTasksEnabled: { value: false },
    isLabelSuggestionFeatureEnabled: { value: false },
    getLabelSuggestions: vi.fn(async () => []),
  }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: {}, query: {} }),
}));

const buildStore = () =>
  createStore({
    getters: {
      getSelectedChat: () => ({ id: 1, messages: [{ id: 10 }] }),
      getCurrentUserID: () => 1,
      getAllMessagesLoaded: () => true,
      getCurrentAccountId: () => 1,
      'globalConfig/isMetaMessageSendingDisabled': () => false,
      'accounts/isFeatureEnabledonAccount': () => () => false,
      'inboxes/getInbox': () => () => ({}),
      'inboxes/getInstagramInboxByInstagramId': () => () => null,
      'conversationTypingStatus/getUserList': () => () => [],
      'integrations/getAppIntegrations': () => [],
    },
    actions: {
      fetchAllAttachments: vi.fn(),
      markMessagesRead: vi.fn(),
      fetchPreviousMessages: vi.fn(),
      sendMessageWithData: vi.fn(),
    },
    modules: {
      conversationLabels: { namespaced: true, actions: { get: vi.fn() } },
      dashboardApps: {
        namespaced: true,
        getters: { getRecords: () => [] },
        actions: { get: vi.fn() },
      },
      inboxAssignableAgents: {
        namespaced: true,
        actions: { fetch: vi.fn() },
      },
    },
  });

const mountView = store =>
  shallowMount(MessagesView, {
    global: {
      plugins: [store],
      stubs: {
        MessageList: { template: '<div class="conversation-panel" />' },
        ReplyBox: { template: '<div />' },
        Banner: { template: '<div />' },
        ConversationLabelSuggestion: { template: '<div />' },
        Spinner: { template: '<div />' },
        ResizableEditorWrapper: { template: '<div><slot /></div>' },
        ScheduledMessagesTimeline: { template: '<div />' },
        ReferralBubble: { template: '<div />' },
      },
      mocks: { $t: key => key, $route: { query: {} } },
    },
  });

describe('MessagesView scroll handling', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  it('coalesces a burst of scroll events into one rAF-scheduled fetch check', async () => {
    const store = buildStore();
    // Espiona o dispatch ANTES do mount: o handler chama
    // fetchPreviousMessages via store dentro do rAF.
    const dispatchSpy = vi.spyOn(store, 'dispatch');
    const wrapper = mountView(store);
    const panel = wrapper.find('.conversation-panel');

    // Mocka o rAF antes da rajada para capturar o agendamento.
    const rafCallbacks = [];
    const rafSpy = vi
      .spyOn(window, 'requestAnimationFrame')
      .mockImplementation(cb => {
        rafCallbacks.push(cb);
        return rafCallbacks.length;
      });

    // Rajada de 10 eventos: exatamente 1 rAF agendado, nenhum fetch ainda.
    panel.element.dispatchEvent(new Event('scroll'));
    await Promise.all(
      Array.from({ length: 9 }, () => {
        panel.element.dispatchEvent(new Event('scroll'));
        return wrapper.vm.$nextTick();
      })
    );
    expect(rafSpy).toHaveBeenCalledTimes(1);
    expect(dispatchSpy).not.toHaveBeenCalledWith(
      'fetchPreviousMessages',
      expect.anything()
    );

    // Flush do frame: o rAF roda fetchPreviousMessages (método) 1×.
    // O método checa guards (dataFetched etc.) — espiona o método para
    // provar coalesce sem depender de estado da store.
    const methodSpy = vi.spyOn(wrapper.vm, 'fetchPreviousMessages');
    rafCallbacks.forEach(cb => cb());
    await wrapper.vm.$nextTick();
    expect(methodSpy).toHaveBeenCalledTimes(1);
  });

  it('registers the scroll listener as passive', () => {
    const store = buildStore();
    const addEventListener = vi.spyOn(
      window.HTMLElement.prototype,
      'addEventListener'
    );
    mountView(store);
    const scrollCall = addEventListener.mock.calls.find(
      ([type]) => type === 'scroll'
    );
    expect(scrollCall?.[2]).toEqual({ passive: true });
  });
});
