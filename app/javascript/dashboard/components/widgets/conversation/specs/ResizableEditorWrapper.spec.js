import { mount } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import ResizableEditorWrapper from '../ResizableEditorWrapper.vue';

describe('ResizableEditorWrapper', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('initializes with minimum default height (64px)', () => {
    const wrapper = mount(ResizableEditorWrapper, {
      props: {
        containerHeight: 600,
      },
      slots: {
        default: '<div class="resizable-editor-body">Editor content</div>',
      },
    });

    const style = wrapper.attributes('style');
    expect(style).toContain('--editor-height: 64px');
    expect(style).toContain('--editor-min-allowed: 64px');
  });

  it('toggles editor expand and shrinks back to minimum default', async () => {
    const wrapper = mount(ResizableEditorWrapper, {
      props: {
        containerHeight: 600,
      },
      slots: {
        default: '<div class="resizable-editor-body">Editor content</div>',
      },
    });

    expect(wrapper.attributes('style')).toContain('--editor-height: 64px');

    // First toggle expands
    wrapper.vm.toggleEditorExpand();
    await wrapper.vm.$nextTick();
    expect(wrapper.attributes('style')).not.toContain('--editor-height: 64px');

    // Second toggle returns to minimum default
    wrapper.vm.toggleEditorExpand();
    await wrapper.vm.$nextTick();
    expect(wrapper.attributes('style')).toContain('--editor-height: 64px');
  });

  it('resets editor height to minimum default on resetEditorHeight', async () => {
    const wrapper = mount(ResizableEditorWrapper, {
      props: {
        containerHeight: 600,
      },
      slots: {
        default: '<div class="resizable-editor-body">Editor content</div>',
      },
    });

    wrapper.vm.toggleEditorExpand();
    await wrapper.vm.$nextTick();
    expect(wrapper.attributes('style')).not.toContain('--editor-height: 64px');

    wrapper.vm.resetEditorHeight();
    await wrapper.vm.$nextTick();
    expect(wrapper.attributes('style')).toContain('--editor-height: 64px');
  });
});
