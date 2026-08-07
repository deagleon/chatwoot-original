<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Icon from 'dashboard/components-next/icon/Icon.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  conversation: {
    type: Object,
    required: true,
  },
  stage: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['dragstart', 'dragend', 'open']);

const { t } = useI18n();

const contact = computed(() => props.conversation?.meta?.sender ?? {});
const contactName = computed(() => contact.value?.name ?? '');
const contactThumbnail = computed(() => contact.value?.thumbnail ?? '');
const contactStatus = computed(() => contact.value?.availability_status);

const lastMessage = computed(() => {
  const messages = props.conversation?.messages;
  if (!messages?.length) return '';
  const last = messages[messages.length - 1];
  return last?.content ?? '';
});

const statusLabel = computed(() => {
  const status = props.conversation?.status;
  if (!status) return '';
  return status.charAt(0).toUpperCase() + status.slice(1);
});

const statusClass = computed(() => {
  const status = props.conversation?.status;
  const map = {
    open: 'bg-n-solid-blue text-n-blue-11',
    resolved: 'bg-n-solid text-n-slate-11',
    pending: 'bg-n-solid-amber text-n-amber-11',
    snoozed: 'bg-n-solid text-n-slate-11',
  };
  return map[status] ?? 'bg-n-solid text-n-slate-11';
});

const daysInStage = computed(() => {
  const changedAt = props.conversation?.pipeline_stage_changed_at;
  if (!changedAt) return null;
  const diff = Date.now() - new Date(changedAt).getTime();
  const days = Math.floor(diff / (1000 * 60 * 60 * 24));
  if (days === 0) return t('PIPELINES.BOARD.CARD.TODAY_IN_STAGE');
  return t('PIPELINES.BOARD.CARD.DAYS_IN_STAGE', { days });
});

const isScheduled = computed(() => props.conversation?.status === 'snoozed');

const ariaLabel = computed(
  () => `${contactName.value}, ${props.stage?.name ?? ''}, ${statusLabel.value}`
);

const onDragStart = e => {
  e.dataTransfer.effectAllowed = 'move';
  e.dataTransfer.setData('text/plain', String(props.conversation.id));
  emit('dragstart', props.conversation.id);
};

const onDragEnd = () => {
  emit('dragend');
};

const onKeydown = e => {
  if (e.key === 'Enter' || e.key === ' ') {
    e.preventDefault();
    emit('open', props.conversation);
  }
};
</script>

<template>
  <div
    draggable="true"
    tabindex="0"
    role="button"
    :aria-label="ariaLabel"
    class="flex flex-col gap-2 p-3 rounded-lg bg-n-solid-1 border border-n-weak cursor-grab hover:border-n-strong transition-colors duration-150 motion-reduce:transition-none focus:outline-none focus:ring-2 focus:ring-n-brand"
    @dragstart="onDragStart"
    @dragend="onDragEnd"
    @click="emit('open', conversation)"
    @keydown="onKeydown"
  >
    <div class="flex items-center gap-2 min-w-0">
      <Avatar
        :name="contactName"
        :src="contactThumbnail"
        :size="24"
        :status="contactStatus"
        rounded-full
      />
      <span class="text-sm font-medium truncate text-n-slate-12 flex-1">
        {{ contactName }}
      </span>
      <span
        v-if="isScheduled"
        v-tooltip.top="t('PIPELINES.BOARD.CARD.SCHEDULED')"
        class="flex items-center justify-center size-4 text-n-amber-11"
      >
        <Icon icon="i-lucide-bell" class="size-3" />
      </span>
    </div>
    <p
      v-if="lastMessage"
      class="text-xs text-n-slate-11 line-clamp-2 break-words"
    >
      {{ lastMessage }}
    </p>
    <div class="flex items-center justify-between gap-2">
      <span
        class="text-xs px-1.5 py-0.5 rounded font-medium"
        :class="statusClass"
      >
        {{ statusLabel }}
      </span>
      <span v-if="daysInStage" class="text-xs text-n-slate-10">
        {{ daysInStage }}
      </span>
    </div>
  </div>
</template>
