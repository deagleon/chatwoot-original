import { mount, flushPromises } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import CannedResponse from '../CannedResponse.vue';
import { useMapGetter } from 'dashboard/composables/store';

const cannedResponses = [
  { id: 1, short_code: 'ola', content: 'Olá, como podemos ajudar?' },
  { id: 2, short_code: 'pedido', content: 'Seu pedido está a caminho.' },
];

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: vi.fn(),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: vi.fn(),
}));

vi.mock('dashboard/composables/useKeyboardNavigableList', () => ({
  useKeyboardNavigableList: () => ({
    moveSelectionUp: vi.fn(),
    moveSelectionDown: vi.fn(),
  }),
}));

const globalOptions = {
  directives: {
    'dompurify-html': () => {},
  },
};

describe('CannedResponse', () => {
  let wrapper;

  beforeEach(() => {
    useMapGetter.mockImplementation(key => {
      if (key === 'getCannedResponses') return { value: cannedResponses };
      if (key === 'getUIFlags') return { value: { fetchingList: false } };
      return { value: false };
    });
  });

  afterEach(() => {
    wrapper?.unmount();
    document.body.innerHTML = '';
  });

  const mountCannedResponse = props =>
    mount(CannedResponse, {
      props,
      global: globalOptions,
      attachTo: document.body,
    });

  const listedItems = () =>
    document.body.querySelectorAll('[role="option"]').length;

  it('lists every canned response when there is no trigger text', async () => {
    wrapper = mountCannedResponse({ searchKey: '' });
    await flushPromises();

    expect(listedItems()).toBe(cannedResponses.length);
  });

  // The keystrokes can keep landing in the composer instead of the picker's own
  // search field, so the trigger text has to keep the list in sync.
  it('filters the list by the search key typed in the composer', async () => {
    wrapper = mountCannedResponse({ searchKey: '' });
    await flushPromises();

    await wrapper.setProps({ searchKey: 'ola' });
    await flushPromises();

    expect(document.body.querySelector('input[role="combobox"]').value).toBe(
      'ola'
    );
    expect(listedItems()).toBe(1);
  });

  it('goes back to the full list when the trigger text is cleared', async () => {
    wrapper = mountCannedResponse({ searchKey: 'ola' });
    await flushPromises();
    expect(listedItems()).toBe(1);

    await wrapper.setProps({ searchKey: '' });
    await flushPromises();

    expect(listedItems()).toBe(cannedResponses.length);
  });
});
