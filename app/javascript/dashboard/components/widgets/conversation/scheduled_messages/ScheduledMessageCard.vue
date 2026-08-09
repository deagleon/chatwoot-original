<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import ScheduledMessagesAPI from 'dashboard/api/scheduledMessages';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

const props = defineProps({
  conversationId: { type: Number, required: true },
});

const emit = defineEmits(['edit']);

const { t } = useI18n();

const nextMessage = ref(null);
const remainingMs = ref(0);
const showCancelConfirm = ref(false);
const isCancelling = ref(false);

let countdownInterval = null;
let reconcileTimer = null;
// Guard da reconciliação no zero: o refetch dispara no máximo uma vez por row
// pendente a cada re-arm, senão o loop (refetch → objeto novo → countdown mais
// negativo → watcher) vira polling contínuo enquanto a row estiver vencida mas
// ainda não claimada pelo sweep.
let reconciledId = null;

const stopCountdown = () => {
  if (countdownInterval) {
    clearInterval(countdownInterval);
    countdownInterval = null;
  }
};

// Re-arma a reconciliação ~20s depois, apenas enquanto a pendente vencida ainda
// estiver no card — o fetch do watcher então confere o estado real sem depender
// do evento realtime (websocket caído no fire-time), e o sweep claimando a row
// (processing sai da index) encerra o ciclo.
const scheduleReconcile = () => {
  clearTimeout(reconcileTimer);
  reconcileTimer = setTimeout(() => {
    reconcileTimer = null;
    if (nextMessage.value) {
      reconciledId = null;
      scheduleReconcile();
    }
  }, 20_000);
};

const updateRemaining = () => {
  if (!nextMessage.value) return;
  remainingMs.value =
    new Date(nextMessage.value.scheduled_at).getTime() - Date.now();
};

const startCountdown = () => {
  stopCountdown();
  updateRemaining();
  countdownInterval = setInterval(updateRemaining, 1000);
};

const formatCountdown = ms => {
  const totalSeconds = Math.max(0, Math.floor(ms / 1000));
  const days = Math.floor(totalSeconds / 86400);
  const hours = Math.floor((totalSeconds % 86400) / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;

  if (days > 0) return `${days}d ${hours}h ${minutes}m`;
  if (hours > 0) return `${hours}h ${minutes}m ${seconds}s`;
  return `${minutes}m ${seconds}s`;
};

const countdownText = computed(() => formatCountdown(remainingMs.value));

const fetchNextScheduledMessage = async () => {
  try {
    const { data } = await ScheduledMessagesAPI.index(props.conversationId);
    // A index ordena por scheduled_at desc, então a próxima a disparar é a
    // pendente com scheduled_at mais cedo — é ela que o card deve exibir.
    const pending = (data.payload || [])
      .filter(item => item.status === 'pending')
      .sort(
        (a, b) =>
          new Date(a.scheduled_at).getTime() -
          new Date(b.scheduled_at).getTime()
      )[0];
    nextMessage.value = pending || null;
  } catch {
    nextMessage.value = null;
  }
};

watch(
  () => props.conversationId,
  () => {
    showCancelConfirm.value = false;
    fetchNextScheduledMessage();
  }
);

watch(nextMessage, (message, oldMessage) => {
  const isNewRow = message?.id !== oldMessage?.id;
  if (isNewRow) {
    reconciledId = null;
  }
  if (message) {
    if (isNewRow) {
      // Só reinicia o intervalo quando a row muda; refetch same-id mantém o
      // countdown atualizado sem resetar (e sem matar o timer de reconciliação).
      startCountdown();
    } else {
      updateRemaining();
    }
  } else {
    stopCountdown();
    // Row saiu do card: encerra a reconciliação periódica.
    clearTimeout(reconcileTimer);
    reconcileTimer = null;
    remainingMs.value = 0;
  }
});

// Countdown chegou a zero: reconcilia com o estado real (o evento realtime pode
// ter sido perdido — websocket caindo no fire-time) em vez de ficar preso em "0m 0s".
watch(remainingMs, ms => {
  if (ms <= 0 && nextMessage.value && nextMessage.value.id !== reconciledId) {
    reconciledId = nextMessage.value.id;
    fetchNextScheduledMessage();
    scheduleReconcile();
  }
});

onMounted(() => {
  fetchNextScheduledMessage();
  emitter.on(BUS_EVENTS.SCHEDULED_MESSAGE_CREATED, fetchNextScheduledMessage);
  emitter.on(BUS_EVENTS.SCHEDULED_MESSAGE_UPDATED, fetchNextScheduledMessage);
  emitter.on(BUS_EVENTS.SCHEDULED_MESSAGE_CANCELLED, fetchNextScheduledMessage);
});

onBeforeUnmount(() => {
  stopCountdown();
  clearTimeout(reconcileTimer);
  reconcileTimer = null;
  emitter.off(BUS_EVENTS.SCHEDULED_MESSAGE_CREATED, fetchNextScheduledMessage);
  emitter.off(BUS_EVENTS.SCHEDULED_MESSAGE_UPDATED, fetchNextScheduledMessage);
  emitter.off(
    BUS_EVENTS.SCHEDULED_MESSAGE_CANCELLED,
    fetchNextScheduledMessage
  );
});

const onEdit = () => {
  if (nextMessage.value) {
    emit('edit', nextMessage.value);
  }
};

const onCancel = () => {
  showCancelConfirm.value = true;
};

const dismissCancel = () => {
  showCancelConfirm.value = false;
};

const onConfirmCancel = async () => {
  if (!nextMessage.value) return;
  isCancelling.value = true;
  try {
    await ScheduledMessagesAPI.delete(
      props.conversationId,
      nextMessage.value.id
    );
    showCancelConfirm.value = false;
    emitter.emit(BUS_EVENTS.SCHEDULED_MESSAGE_CANCELLED, nextMessage.value);
    useAlert(t('SCHEDULED_MESSAGES.CANCEL_SUCCESS'));
  } catch (error) {
    const status = error?.response?.data?.status;
    if (status) {
      useAlert(t('SCHEDULED_MESSAGES.CONFLICT', { status }));
    } else {
      useAlert(error?.response?.data?.error || t('SCHEDULED_MESSAGES.ERROR'));
    }
  } finally {
    isCancelling.value = false;
  }
};
</script>

<template>
  <div
    v-if="nextMessage"
    data-testid="scheduled-card"
    class="flex items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2"
  >
    <div class="flex flex-col min-w-0 flex-1 gap-0.5">
      <div class="flex items-center gap-2">
        <span
          data-testid="scheduled-card-countdown"
          class="text-xs font-semibold text-n-brand"
        >
          {{ countdownText }}
        </span>
        <span class="text-xs text-n-slate-11">
          {{ t('SCHEDULED_MESSAGES.CARD_TITLE') }}
        </span>
      </div>
      <p
        data-testid="scheduled-card-content"
        class="text-sm text-n-slate-12 line-clamp-2 break-words"
      >
        {{ nextMessage.content }}
      </p>
    </div>

    <div
      v-if="showCancelConfirm"
      class="flex items-center gap-2 text-xs text-n-slate-11"
    >
      <span>{{ t('SCHEDULED_MESSAGES.CANCEL_CONFIRM') }}</span>
      <Button
        size="xs"
        variant="ghost"
        color="ruby"
        data-testid="scheduled-card-confirm-cancel"
        :is-loading="isCancelling"
        :disabled="isCancelling"
        :label="t('SCHEDULED_MESSAGES.CONFIRM_CANCEL')"
        @click="onConfirmCancel"
      />
      <Button
        size="xs"
        ghost
        slate
        data-testid="scheduled-card-dismiss-cancel"
        :label="t('SCHEDULED_MESSAGES.DISMISS_CANCEL')"
        @click="dismissCancel"
      />
    </div>

    <div v-else class="flex items-center gap-1 shrink-0">
      <Button
        size="xs"
        ghost
        slate
        data-testid="scheduled-card-edit"
        :label="t('SCHEDULED_MESSAGES.CARD_EDIT')"
        @click="onEdit"
      />
      <Button
        size="xs"
        ghost
        slate
        data-testid="scheduled-card-cancel"
        :label="t('SCHEDULED_MESSAGES.CARD_CANCEL')"
        @click="onCancel"
      />
    </div>
  </div>
</template>
