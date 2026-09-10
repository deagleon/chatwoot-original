import { mount } from '@vue/test-utils';
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
});
