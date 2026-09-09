import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import Dialog from '../Dialog.vue';

// Mock HTMLDialogElement showModal and close for jsdom
HTMLDialogElement.prototype.showModal = vi.fn();
HTMLDialogElement.prototype.close = vi.fn();

const globalStubs = {
  TeleportWithDirection: {
    template: '<div><slot /></div>',
  },
  OnClickOutside: {
    template: '<div><slot /></div>',
  },
  Button: {
    props: ['label'],
    template: '<button><slot />{{ label }}</button>',
  },
};

const createWrapper = (props = {}, options = {}) =>
  mount(Dialog, {
    props,
    global: {
      stubs: globalStubs,
      mocks: {
        $t: key => key,
      },
    },
    ...options,
  });

describe('Dialog', () => {
  it('renders with default width class max-w-lg', () => {
    const wrapper = createWrapper();
    const dialog = wrapper.find('dialog');
    expect(dialog.classes()).toContain('max-w-lg');
  });

  it('renders with width 7xl class max-w-7xl', () => {
    const wrapper = createWrapper({ width: '7xl' });
    const dialog = wrapper.find('dialog');
    expect(dialog.classes()).toContain('max-w-7xl');
  });

  it('renders with width full class max-w-[95vw]', () => {
    const wrapper = createWrapper({ width: 'full' });
    const dialog = wrapper.find('dialog');
    expect(dialog.classes()).toContain('max-w-[95vw]');
  });

  it('renders with width 4xl class max-w-4xl', () => {
    const wrapper = createWrapper({ width: '4xl' });
    const dialog = wrapper.find('dialog');
    expect(dialog.classes()).toContain('max-w-4xl');
  });

  it('renders title and description', () => {
    const wrapper = createWrapper({
      title: 'Modal Title',
      description: 'Modal Description',
    });
    expect(wrapper.text()).toContain('Modal Title');
    expect(wrapper.text()).toContain('Modal Description');
  });

  it('renders headerActions slot when provided', () => {
    const wrapper = createWrapper(
      { title: 'Modal Title' },
      {
        slots: {
          headerActions: '<button id="custom-close-btn">Close</button>',
        },
      }
    );
    expect(wrapper.find('#custom-close-btn').exists()).toBe(true);
  });

  it('opens and closes dialog via exposed methods', async () => {
    const wrapper = createWrapper();
    wrapper.vm.open();
    expect(wrapper.vm.isOpen).toBe(true);

    wrapper.vm.close();
    expect(wrapper.vm.isOpen).toBe(false);
    expect(wrapper.emitted('close')).toBeTruthy();
  });

  it('emits confirm when form is submitted', async () => {
    const wrapper = createWrapper();
    wrapper.vm.open();
    await wrapper.find('form').trigger('submit.prevent');
    expect(wrapper.emitted('confirm')).toBeTruthy();
  });
});
