import { flushPromises, mount } from '@vue/test-utils';
import { nextTick } from 'vue';
import { createStore } from 'vuex';
import { format } from 'date-fns';
import { describe, expect, it, vi, beforeEach } from 'vitest';
import { withFullI18n } from 'test-i18n';

import ScheduledMessageModal from '../ScheduledMessageModal.vue';
import ScheduledMessagesAPI from 'dashboard/api/scheduledMessages';

withFullI18n();

vi.mock('dashboard/api/scheduledMessages', () => ({
  default: {
    create: vi.fn(),
    update: vi.fn(),
  },
}));

const DATETIME_FORMAT = "yyyy-MM-dd'T'HH:mm";

const store = createStore({
  getters: {
    getCurrentAccount: () => ({ reporting_timezone: 'UTC' }),
  },
});

const mountModal = (props = {}) =>
  mount(ScheduledMessageModal, {
    props: {
      show: true,
      conversationId: 1,
      initialContent: 'Bom dia',
      ...props,
    },
    global: { plugins: [store] },
  });

describe('ScheduledMessageModal', () => {
  beforeEach(() => {
    ScheduledMessagesAPI.create.mockResolvedValue({
      data: {
        id: 1,
        content: 'Bom dia',
        scheduled_at: new Date(Date.now() + 3600 * 1000).toISOString(),
        status: 'pending',
      },
    });
  });

  it('renders the composer content as the scheduled message', () => {
    const wrapper = mountModal({ initialContent: 'Olá, tudo bem?' });

    expect(wrapper.find('[data-testid="scheduled-message"]').text()).toBe(
      'Olá, tudo bem?'
    );
  });

  it('blocks submission when the chosen datetime is in the past', async () => {
    const wrapper = mountModal();
    await flushPromises();

    const pastDate = format(new Date(Date.now() - 60000), DATETIME_FORMAT);
    await wrapper.find('[data-testid="scheduled-datetime"]').setValue(pastDate);
    await wrapper.find('[data-testid="scheduled-submit"]').trigger('click');
    await nextTick();

    expect(wrapper.find('[data-testid="scheduled-error"]').text()).toContain(
      'A data precisa ser no futuro'
    );
    expect(ScheduledMessagesAPI.create).not.toHaveBeenCalled();
  });

  it('disables the submit button while saving', async () => {
    ScheduledMessagesAPI.create.mockReturnValue(new Promise(() => {}));
    const wrapper = mountModal();
    await flushPromises();

    await wrapper.find('[data-testid="scheduled-submit"]').trigger('click');
    await nextTick();

    const submit = wrapper.find('[data-testid="scheduled-submit"]');
    expect(submit.attributes('disabled')).toBeDefined();
    expect(ScheduledMessagesAPI.create).toHaveBeenCalledWith(
      1,
      expect.objectContaining({ content: 'Bom dia' })
    );
  });

  it('emits close when the close button is clicked', async () => {
    const wrapper = mountModal();
    await flushPromises();

    await wrapper.find('[data-testid="scheduled-close"]').trigger('click');

    expect(wrapper.emitted('close')).toHaveLength(1);
  });

  it('prefills the form with the edited message and saves on submit', async () => {
    const scheduledAt = new Date(Date.now() + 2 * 3600 * 1000);
    ScheduledMessagesAPI.update.mockResolvedValue({
      data: {
        id: 7,
        content: 'Boa tarde',
        scheduled_at: scheduledAt.toISOString(),
        status: 'pending',
      },
    });
    const wrapper = mountModal({
      initialContent: 'Boa tarde',
      editing: {
        id: 7,
        content: 'Boa tarde',
        scheduled_at: scheduledAt.toISOString(),
        status: 'pending',
      },
    });
    await flushPromises();

    expect(
      wrapper.find('[data-testid="scheduled-datetime"]').element.value
    ).toBe(format(scheduledAt, DATETIME_FORMAT));

    await wrapper.find('[data-testid="scheduled-submit"]').trigger('click');
    await flushPromises();

    expect(ScheduledMessagesAPI.update).toHaveBeenCalledWith(
      1,
      7,
      expect.objectContaining({ content: 'Boa tarde' })
    );
    expect(wrapper.emitted('saved')).toHaveLength(1);
  });
});
