<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { addHours, format } from 'date-fns';
import { formatInTimeZone } from 'date-fns-tz';

import Modal from 'dashboard/components/Modal.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ScheduledMessagesAPI from 'dashboard/api/scheduledMessages';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

const props = defineProps({
  show: { type: Boolean, default: false },
  conversationId: { type: Number, required: true },
  initialContent: { type: String, default: '' },
  editing: { type: Object, default: null },
});

const emit = defineEmits(['close', 'saved']);

const { t } = useI18n();

const currentAccount = useMapGetter('getCurrentAccount');

const accountTimezone = computed(
  () => currentAccount.value?.reporting_timezone || 'America/Sao_Paulo'
);

const datetime = ref('');
const internalNote = ref('');
const errorMessage = ref('');
const isSaving = ref(false);

const DATETIME_FORMAT = "yyyy-MM-dd'T'HH:mm";
const PREVIEW_FORMAT = 'MMM dd, yyyy HH:mm';

const toLocalInputValue = date => format(new Date(date), DATETIME_FORMAT);

const previewDatetime = computed(() => {
  if (!datetime.value) return '';
  return formatInTimeZone(
    new Date(datetime.value),
    accountTimezone.value,
    PREVIEW_FORMAT
  );
});

const resetForm = () => {
  errorMessage.value = '';
  isSaving.value = false;
  if (props.editing) {
    datetime.value = toLocalInputValue(props.editing.scheduled_at);
    internalNote.value = props.editing.internal_note || '';
  } else {
    datetime.value = toLocalInputValue(addHours(new Date(), 1));
    internalNote.value = '';
  }
};

watch(
  () => props.show,
  show => {
    if (show) {
      resetForm();
    }
  },
  { immediate: true }
);

const onClose = () => {
  emit('close');
};

const onSubmit = async () => {
  if (isSaving.value) return;

  const scheduledAt = new Date(datetime.value);
  if (!scheduledAt || scheduledAt.getTime() <= Date.now()) {
    errorMessage.value = t('SCHEDULED_MESSAGES.FUTURE_REQUIRED');
    return;
  }

  errorMessage.value = '';
  isSaving.value = true;

  const payload = {
    content: props.initialContent,
    scheduled_at: scheduledAt.toISOString(),
    internal_note: internalNote.value || undefined,
  };

  try {
    if (props.editing) {
      const { data } = await ScheduledMessagesAPI.update(
        props.conversationId,
        props.editing.id,
        payload
      );
      useAlert(t('SCHEDULED_MESSAGES.EDIT_SUCCESS'));
      emitter.emit(BUS_EVENTS.SCHEDULED_MESSAGE_UPDATED, data);
    } else {
      const { data } = await ScheduledMessagesAPI.create(
        props.conversationId,
        payload
      );
      useAlert(
        t('SCHEDULED_MESSAGES.SUCCESS', {
          date: formatInTimeZone(
            new Date(data.scheduled_at),
            accountTimezone.value,
            PREVIEW_FORMAT
          ),
        })
      );
      emitter.emit(BUS_EVENTS.SCHEDULED_MESSAGE_CREATED, data);
    }
    emit('saved');
  } catch (error) {
    const status = error?.response?.data?.status;
    if (status) {
      useAlert(t('SCHEDULED_MESSAGES.CONFLICT', { status }));
    } else {
      useAlert(error?.response?.data?.error || t('SCHEDULED_MESSAGES.ERROR'));
    }
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <Modal :show="show" @close="onClose">
    <div class="flex flex-col h-auto overflow-auto">
      <woot-modal-header
        :header-title="
          editing
            ? t('SCHEDULED_MESSAGES.EDIT_TITLE')
            : t('SCHEDULED_MESSAGES.MODAL_TITLE')
        "
      />
      <form class="w-full" @submit.prevent="onSubmit">
        <div class="flex flex-col gap-4">
          <div class="flex flex-col gap-1">
            <label
              for="scheduled-message"
              class="text-sm font-medium text-n-slate-11"
            >
              {{ t('SCHEDULED_MESSAGES.MESSAGE_LABEL') }}
            </label>
            <p
              id="scheduled-message"
              data-testid="scheduled-message"
              class="text-sm break-words whitespace-pre-wrap text-n-slate-12 bg-n-alpha-1 rounded-lg px-3 py-2 max-h-32 overflow-y-auto"
            >
              {{ initialContent }}
            </p>
          </div>

          <div class="flex flex-col gap-1">
            <label
              for="scheduled-datetime"
              class="text-sm font-medium text-n-slate-11"
            >
              {{ t('SCHEDULED_MESSAGES.DATETIME_LABEL') }}
            </label>
            <input
              id="scheduled-datetime"
              v-model="datetime"
              data-testid="scheduled-datetime"
              type="datetime-local"
              class="w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 focus:border-n-brand focus:outline-none"
              @input="errorMessage = ''"
            />
            <p
              v-if="previewDatetime"
              class="text-xs text-n-slate-11"
              data-testid="scheduled-datetime-preview"
            >
              {{
                t('SCHEDULED_MESSAGES.DATETIME_PREVIEW', {
                  date: previewDatetime,
                })
              }}
            </p>
            <p
              v-if="errorMessage"
              class="text-xs text-n-ruby-11"
              data-testid="scheduled-error"
            >
              {{ errorMessage }}
            </p>
          </div>

          <div class="flex flex-col gap-1">
            <label
              for="scheduled-internal-note"
              class="text-sm font-medium text-n-slate-11"
            >
              {{ t('SCHEDULED_MESSAGES.INTERNAL_NOTE_LABEL') }}
            </label>
            <textarea
              id="scheduled-internal-note"
              v-model="internalNote"
              data-testid="scheduled-internal-note"
              maxlength="500"
              rows="3"
              class="w-full resize-none rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 focus:border-n-brand focus:outline-none"
            />
          </div>

          <div class="flex justify-end gap-2">
            <Button
              ghost
              slate
              size="sm"
              data-testid="scheduled-close"
              :label="t('SCHEDULED_MESSAGES.CLOSE')"
              @click="onClose"
            />
            <Button
              type="submit"
              size="sm"
              data-testid="scheduled-submit"
              :is-loading="isSaving"
              :disabled="isSaving"
              :label="
                editing
                  ? t('SCHEDULED_MESSAGES.EDIT_SAVE')
                  : t('SCHEDULED_MESSAGES.SAVE')
              "
              @click="onSubmit"
            />
          </div>
        </div>
      </form>
    </div>
  </Modal>
</template>
