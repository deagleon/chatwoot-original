<script setup>
import { useI18n } from 'vue-i18n';

import Icon from 'dashboard/components-next/icon/Icon.vue';
import PipelineBoardCard from './PipelineBoardCard.vue';

const props = defineProps({
  stage: {
    type: Object,
    required: true,
  },
  conversations: {
    type: Array,
    default: () => [],
  },
  loading: {
    type: Boolean,
    default: false,
  },
  hasMore: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['drop', 'open-card', 'load-more']);

const { t } = useI18n();

const onDrop = e => {
  e.preventDefault();
  const conversationId = e.dataTransfer.getData('text/plain');
  emit('drop', {
    stageId: props.stage.id,
    conversationId: Number(conversationId),
  });
};

const onDragOver = e => {
  e.preventDefault();
  e.dataTransfer.dropEffect = 'move';
};
</script>

<template>
  <div
    class="flex flex-col w-[280px] flex-shrink-0 h-full rounded-lg bg-n-solid-2 border border-n-weak transition-colors duration-150 motion-reduce:transition-none"
    role="list"
    :aria-label="stage.name"
    @dragover="onDragOver"
    @drop="onDrop"
  >
    <!-- Header -->
    <div class="flex items-center gap-2 px-3 py-2.5 border-b border-n-weak">
      <span
        class="inline-block w-2 h-2 rounded-full flex-shrink-0"
        :style="{ backgroundColor: stage.color }"
      />
      <span
        class="flex-1 text-sm font-medium truncate text-n-slate-12"
        :title="stage.name"
      >
        {{ stage.name }}
      </span>
      <span class="text-xs text-n-slate-10 tabular-nums">
        {{
          t('PIPELINES.BOARD.COLUMN.CONVERSATIONS_COUNT', {
            count: conversations.length,
          })
        }}
      </span>
    </div>

    <!-- Cards -->
    <div class="flex-1 overflow-y-auto px-2 py-2 space-y-2 min-h-0">
      <div
        v-if="loading && conversations.length === 0"
        class="flex justify-center py-4"
      >
        <Icon
          icon="i-lucide-loader-2"
          class="size-4 animate-spin text-n-slate-10"
        />
      </div>
      <template v-else>
        <PipelineBoardCard
          v-for="conversation in conversations"
          :key="conversation.id"
          :conversation="conversation"
          :stage="stage"
          @open="conv => emit('open-card', conv)"
        />
        <div
          v-if="conversations.length === 0 && !loading"
          class="flex items-center justify-center py-4 text-xs text-n-slate-10"
        >
          {{ t('PIPELINES.BOARD.COLUMN.EMPTY') }}
        </div>
      </template>
    </div>

    <!-- Load more -->
    <div v-if="hasMore" class="px-3 py-2 border-t border-n-weak">
      <button
        class="w-full text-xs text-n-slate-11 hover:text-n-slate-12 transition-colors motion-reduce:transition-none"
        @click="emit('load-more', stage.id)"
      >
        {{ t('PIPELINES.BOARD.LOAD_MORE') }}
      </button>
    </div>
  </div>
</template>
