import { flushPromises, mount } from '@vue/test-utils';
import { nextTick } from 'vue';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { withFullI18n } from 'test-i18n';

import ScheduledMessageCard from '../ScheduledMessageCard.vue';
import ScheduledMessagesAPI from 'dashboard/api/scheduledMessages';

withFullI18n();

vi.mock('dashboard/api/scheduledMessages', () => ({
  default: {
    index: vi.fn(),
    delete: vi.fn(),
  },
}));

const scheduledMessage = {
  id: 10,
  content: 'Bom dia, tudo bem?',
  scheduled_at: new Date(Date.now() + 2 * 60 * 1000).toISOString(),
  status: 'pending',
  internal_note: null,
};

const mountCard = () =>
  mount(ScheduledMessageCard, {
    props: { conversationId: 1 },
  });

let wrapper = null;

describe('ScheduledMessageCard', () => {
  beforeEach(() => {
    // Objeto novo por chamada: a API real sempre devolve JSON fresco, e o
    // caminho de referência nova (watcher de nextMessage) precisa ser exercitado.
    ScheduledMessagesAPI.index.mockImplementation(() =>
      Promise.resolve({ data: { payload: [{ ...scheduledMessage }] } })
    );
  });

  afterEach(() => {
    wrapper?.unmount();
    vi.useRealTimers();
  });

  it('renders the next pending message with a live countdown', async () => {
    vi.useFakeTimers();
    wrapper = mountCard();
    await flushPromises();

    expect(wrapper.find('[data-testid="scheduled-card"]').exists()).toBe(true);
    expect(wrapper.text()).toContain('Próxima mensagem agendada');
    expect(wrapper.find('[data-testid="scheduled-card-content"]').text()).toBe(
      'Bom dia, tudo bem?'
    );

    const initialCountdown = wrapper
      .find('[data-testid="scheduled-card-countdown"]')
      .text();
    expect(initialCountdown).toMatch(/^\d+m \d+s$/);

    vi.advanceTimersByTime(1000);
    await nextTick();

    const countdownAfterTick = wrapper
      .find('[data-testid="scheduled-card-countdown"]')
      .text();
    expect(countdownAfterTick).not.toBe(initialCountdown);
  });

  it('emits edit with the scheduled message when the edit action is clicked', async () => {
    wrapper = mountCard();
    await flushPromises();

    await wrapper.find('[data-testid="scheduled-card-edit"]').trigger('click');

    expect(wrapper.emitted('edit')).toHaveLength(1);
    expect(wrapper.emitted('edit')[0][0]).toEqual(scheduledMessage);
  });

  it('confirms cancellation inline and calls the delete API', async () => {
    ScheduledMessagesAPI.delete.mockResolvedValue({
      data: { id: 10, status: 'cancelled' },
    });
    wrapper = mountCard();
    await flushPromises();

    await wrapper
      .find('[data-testid="scheduled-card-cancel"]')
      .trigger('click');

    expect(
      wrapper.find('[data-testid="scheduled-card-confirm-cancel"]').exists()
    ).toBe(true);
    expect(wrapper.text()).toContain('Tem certeza? Ela não será enviada.');

    await wrapper
      .find('[data-testid="scheduled-card-confirm-cancel"]')
      .trigger('click');
    await flushPromises();

    expect(ScheduledMessagesAPI.delete).toHaveBeenCalledWith(1, 10);
  });

  it('shows the pending message with the earliest scheduled_at (index returns desc)', async () => {
    const near = {
      id: 11,
      content: 'próxima a disparar',
      scheduled_at: new Date(Date.now() + 2 * 60 * 1000).toISOString(),
      status: 'pending',
    };
    const far = {
      id: 12,
      content: 'muito depois',
      scheduled_at: new Date(Date.now() + 2 * 60 * 60 * 1000).toISOString(),
      status: 'pending',
    };
    ScheduledMessagesAPI.index.mockResolvedValue({
      data: { payload: [far, near] },
    });

    wrapper = mountCard();
    await flushPromises();

    expect(wrapper.find('[data-testid="scheduled-card-content"]').text()).toBe(
      'próxima a disparar'
    );
  });

  it('reconcilies at zero with bounded polling, no tight loop', async () => {
    vi.useFakeTimers();
    wrapper = mountCard();
    await flushPromises();

    expect(ScheduledMessagesAPI.index).toHaveBeenCalledTimes(1);

    // Cruzou o zero: refetch imediato de reconciliação.
    vi.advanceTimersByTime(2 * 60 * 1000 + 1000);
    await flushPromises();

    expect(ScheduledMessagesAPI.index).toHaveBeenCalledTimes(2);

    // Re-arm ~20s depois: uma nova checagem enquanto a pendente segue vencida.
    vi.advanceTimersByTime(21_000);
    await flushPromises();

    expect(ScheduledMessagesAPI.index).toHaveBeenCalledTimes(3);

    // A row continua pendente (janela de claim do sweep): o polling segue
    // limitado (~1 fetch/20s), nunca virando um loop apertado.
    vi.advanceTimersByTime(60_000);
    await flushPromises();

    const callsAfter = ScheduledMessagesAPI.index.mock.calls.length;
    expect(callsAfter).toBeGreaterThan(3);
    expect(callsAfter).toBeLessThanOrEqual(6);
  });
});
