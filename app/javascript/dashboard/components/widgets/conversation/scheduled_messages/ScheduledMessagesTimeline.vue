<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatInTimeZone } from 'date-fns-tz';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ScheduledMessagesAPI from 'dashboard/api/scheduledMessages';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

const props = defineProps({
  conversationId: { type: Number, required: true },
});

const { t } = useI18n();

const currentAccount = useMapGetter('getCurrentAccount');

const accountTimezone = computed(
  () => currentAccount.value?.reporting_timezone || 'America/Sao_Paulo'
);

const scheduledMessages = ref([]);
const isExpanded = ref(false);
const deleteConfirmId = ref(null);
const isDeleting = ref(false);

const STATUS_ORDER = ['pending', 'sent', 'cancelled', 'failed'];

const statusCounts = computed(() => {
  const counts = {};
  scheduledMessages.value.forEach(item => {
    counts[item.status] = (counts[item.status] || 0) + 1;
  });
  return counts;
});

// Somente status com pelo menos uma mensagem, na ordem fixa de exibição.
const visibleStatuses = computed(() =>
  STATUS_ORDER.filter(status => statusCounts.value[status])
);

const formatScheduledAt = scheduledAt =>
  formatInTimeZone(
    new Date(scheduledAt),
    accountTimezone.value,
    'dd/MM/yyyy HH:mm'
  );

const statusLabels = {
  sent: () => t('SCHEDULED_MESSAGES.STATUS_SENT'),
  failed: () => t('SCHEDULED_MESSAGES.STATUS_FAILED'),
  cancelled: () => t('SCHEDULED_MESSAGES.STATUS_CANCELLED'),
  pending: () => t('SCHEDULED_MESSAGES.STATUS_PENDING'),
};

const statusLabel = status => {
  const labelFn = statusLabels[status] || statusLabels.pending;
  return labelFn();
};

const statusClasses = status => {
  const classes = {
    sent: 'bg-n-teal-9/10 text-n-teal-11',
    failed: 'bg-n-ruby-9/10 text-n-ruby-11',
    cancelled: 'bg-n-alpha-2 text-n-slate-11',
    pending: 'bg-n-brand/10 text-n-blue-11',
  };
  return classes[status] || 'bg-n-alpha-2 text-n-slate-11';
};

const fetchScheduledMessages = async () => {
  try {
    const { data } = await ScheduledMessagesAPI.index(props.conversationId);
    scheduledMessages.value = data.payload || [];
  } catch {
    scheduledMessages.value = [];
  }
};

watch(
  () => props.conversationId,
  () => {
    // Recolhe o histórico ao trocar de conversa
    isExpanded.value = false;
    fetchScheduledMessages();
  }
);

onMounted(() => {
  fetchScheduledMessages();
  emitter.on(BUS_EVENTS.SCHEDULED_MESSAGE_CREATED, fetchScheduledMessages);
  emitter.on(BUS_EVENTS.SCHEDULED_MESSAGE_UPDATED, fetchScheduledMessages);
  emitter.on(BUS_EVENTS.SCHEDULED_MESSAGE_CANCELLED, fetchScheduledMessages);
});

onBeforeUnmount(() => {
  emitter.off(BUS_EVENTS.SCHEDULED_MESSAGE_CREATED, fetchScheduledMessages);
  emitter.off(BUS_EVENTS.SCHEDULED_MESSAGE_UPDATED, fetchScheduledMessages);
  emitter.off(BUS_EVENTS.SCHEDULED_MESSAGE_CANCELLED, fetchScheduledMessages);
});

const onRetry = async scheduledMessage => {
  try {
    await ScheduledMessagesAPI.retry(props.conversationId, scheduledMessage.id);
    fetchScheduledMessages();
  } catch (error) {
    const status = error?.response?.data?.status;
    if (status) {
      useAlert(t('SCHEDULED_MESSAGES.CONFLICT', { status }));
    } else {
      useAlert(error?.response?.data?.error || t('SCHEDULED_MESSAGES.ERROR'));
    }
  }
};

const isDeletable = scheduledMessage =>
  scheduledMessage.status === 'cancelled' || scheduledMessage.status === 'sent';

const onDelete = scheduledMessage => {
  deleteConfirmId.value = scheduledMessage.id;
};

const dismissDelete = () => {
  deleteConfirmId.value = null;
};

const onConfirmDelete = async scheduledMessage => {
  if (isDeleting.value) return;
  isDeleting.value = true;
  try {
    await ScheduledMessagesAPI.delete(
      props.conversationId,
      scheduledMessage.id
    );
    deleteConfirmId.value = null;
    fetchScheduledMessages();
    useAlert(t('SCHEDULED_MESSAGES.DELETE_SUCCESS'));
  } catch (error) {
    const status = error?.response?.data?.status;
    if (status) {
      useAlert(t('SCHEDULED_MESSAGES.CONFLICT', { status }));
    } else {
      useAlert(error?.response?.data?.error || t('SCHEDULED_MESSAGES.ERROR'));
    }
  } finally {
    isDeleting.value = false;
  }
};
</script>

<template>
  <div
    v-if="scheduledMessages.length"
    data-testid="scheduled-timeline"
    class="flex flex-col gap-1 px-3 py-2"
  >
    <button
      type="button"
      data-testid="scheduled-timeline-toggle"
      :aria-expanded="isExpanded"
      aria-controls="scheduled-timeline-list"
      :title="
        isExpanded
          ? t('SCHEDULED_MESSAGES.TIMELINE_COLLAPSE')
          : t('SCHEDULED_MESSAGES.TIMELINE_EXPAND')
      "
      class="flex items-center gap-2 w-full text-xs text-n-slate-11 text-start"
      @click="isExpanded = !isExpanded"
    >
      <Icon
        icon="i-lucide-calendar"
        class="w-4 h-4 mt-0.5 text-n-slate-11 flex-shrink-0"
      />
      <span class="text-n-slate-12 font-medium">
        {{ t('SCHEDULED_MESSAGES.TIMELINE_TITLE') }}
      </span>
      <span
        v-for="status in visibleStatuses"
        :key="status"
        class="rounded-md px-1.5 py-0.5 text-[0.625rem] font-medium"
        :class="statusClasses(status)"
      >
        {{ statusCounts[status] }} {{ statusLabel(status) }}
      </span>
      <Icon
        :icon="isExpanded ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        class="w-4 h-4 ms-auto flex-shrink-0 text-n-slate-10"
      />
    </button>

    <div
      v-if="isExpanded"
      id="scheduled-timeline-list"
      class="flex flex-col gap-1"
    >
      <div
        v-for="scheduledMessage in scheduledMessages"
        :key="scheduledMessage.id"
        data-testid="scheduled-timeline-item"
        class="flex items-start gap-2 text-xs text-n-slate-11"
      >
        <Icon
          icon="i-lucide-calendar"
          class="w-4 h-4 mt-0.5 text-n-slate-11 flex-shrink-0"
        />
        <div class="flex flex-col min-w-0 flex-1 gap-1">
          <div class="flex flex-wrap items-center gap-2">
            <span class="text-n-slate-12">
              {{
                t('SCHEDULED_MESSAGES.TIMELINE_ITEM', {
                  name: scheduledMessage.created_by?.name || '—',
                  date: formatScheduledAt(scheduledMessage.scheduled_at),
                })
              }}
            </span>
            <span
              class="rounded-md px-1.5 py-0.5 text-[0.625rem] font-medium"
              :class="statusClasses(scheduledMessage.status)"
            >
              {{ statusLabel(scheduledMessage.status) }}
            </span>
          </div>
          <p
            class="text-n-slate-11 line-clamp-2 break-words"
            data-testid="scheduled-timeline-content"
          >
            {{ scheduledMessage.content }}
          </p>
          <div class="flex items-center gap-1">
            <Button
              v-if="scheduledMessage.status === 'failed'"
              size="xs"
              variant="ghost"
              data-testid="scheduled-timeline-retry"
              class="self-start"
              :label="t('SCHEDULED_MESSAGES.RETRY')"
              @click="onRetry(scheduledMessage)"
            />
            <Button
              v-if="isDeletable(scheduledMessage)"
              size="xs"
              variant="ghost"
              icon="i-lucide-trash"
              data-testid="scheduled-timeline-delete"
              :title="t('SCHEDULED_MESSAGES.TIMELINE_DELETE')"
              class="self-start text-n-slate-10 hover:text-n-ruby-11"
              @click="onDelete(scheduledMessage)"
            />
          </div>
          <div
            v-if="deleteConfirmId === scheduledMessage.id"
            class="flex items-center gap-2 text-xs text-n-slate-11"
          >
            <span>{{ t('SCHEDULED_MESSAGES.DELETE_CONFIRM') }}</span>
            <Button
              size="xs"
              variant="ghost"
              color="ruby"
              data-testid="scheduled-timeline-confirm-delete"
              :is-loading="isDeleting"
              :disabled="isDeleting"
              :label="t('SCHEDULED_MESSAGES.CONFIRM_DELETE')"
              @click="onConfirmDelete(scheduledMessage)"
            />
            <Button
              size="xs"
              ghost
              slate
              data-testid="scheduled-timeline-dismiss-delete"
              :label="t('SCHEDULED_MESSAGES.DISMISS_CANCEL')"
              @click="dismissDelete"
            />
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
