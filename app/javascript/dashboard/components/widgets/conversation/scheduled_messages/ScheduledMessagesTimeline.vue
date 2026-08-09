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

const formatScheduledAt = scheduledAt =>
  formatInTimeZone(
    new Date(scheduledAt),
    accountTimezone.value,
    'MMM dd, yyyy HH:mm'
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
</script>

<template>
  <div
    v-if="scheduledMessages.length"
    data-testid="scheduled-timeline"
    class="flex flex-col gap-1 px-3 py-2"
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
        <Button
          v-if="scheduledMessage.status === 'failed'"
          size="xs"
          variant="ghost"
          data-testid="scheduled-timeline-retry"
          class="self-start"
          :label="t('SCHEDULED_MESSAGES.RETRY')"
          @click="onRetry(scheduledMessage)"
        />
      </div>
    </div>
  </div>
</template>
