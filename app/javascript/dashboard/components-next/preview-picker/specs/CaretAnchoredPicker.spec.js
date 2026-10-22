import { mount, flushPromises } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import { nextTick } from 'vue';
import CaretAnchoredPicker from '../CaretAnchoredPicker.vue';

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: false }),
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

const globalDirectives = {
  'dompurify-html': () => {},
};

describe('CaretAnchoredPicker', () => {
  const defaultProps = {
    items: [{ id: 1, label: '/test', content: 'test content' }],
  };

  it('teleports into closest dialog when mounted inside a dialog', async () => {
    const dialog = document.createElement('dialog');
    document.body.appendChild(dialog);

    const wrapper = mount(CaretAnchoredPicker, {
      props: defaultProps,
      attachTo: dialog,
      global: {
        directives: globalDirectives,
      },
    });

    await nextTick();

    const pickerInDialog = dialog.querySelector('[data-popover-content]');
    expect(pickerInDialog).not.toBeNull();

    wrapper.unmount();
    dialog.remove();
  });

  it('teleports to body when mounted outside a dialog', async () => {
    const container = document.createElement('div');
    document.body.appendChild(container);

    const wrapper = mount(CaretAnchoredPicker, {
      props: defaultProps,
      attachTo: container,
      global: {
        directives: globalDirectives,
      },
    });

    await nextTick();

    const pickerInBody = document.body.querySelector('[data-popover-content]');
    expect(pickerInBody).not.toBeNull();

    wrapper.unmount();
    container.remove();
  });

  // The picker content is teleported to `body` on the first render and only moved
  // into the dialog afterwards. Inside a modal dialog the body is inert, so the
  // autofocus on mount is silently ignored and the search field never gets focus.
  it('focuses the search field only after the picker lands inside the dialog', async () => {
    const dialog = document.createElement('dialog');
    document.body.appendChild(dialog);

    const focusCalls = [];
    const focusSpy = vi
      .spyOn(HTMLInputElement.prototype, 'focus')
      .mockImplementation(function focus() {
        focusCalls.push(this.closest('dialog'));
      });

    const wrapper = mount(CaretAnchoredPicker, {
      props: defaultProps,
      attachTo: dialog,
      global: {
        directives: globalDirectives,
      },
    });

    await flushPromises();

    const searchField = dialog.querySelector('input[role="combobox"]');
    expect(searchField).not.toBeNull();
    expect(focusCalls.some(call => call === dialog)).toBe(true);

    focusSpy.mockRestore();
    wrapper.unmount();
    dialog.remove();
  });
});
