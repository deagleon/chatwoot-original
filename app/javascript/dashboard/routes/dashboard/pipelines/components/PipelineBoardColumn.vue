<script setup>
import { ref, watch, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { Virtualizer } from 'virtua/vue';

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

const emit = defineEmits([
  'drop',
  'open-card',
  'open-conversation',
  'mark-read',
  'mark-unread',
  'load-more',
]);

const { t } = useI18n();

// Scroll infinito: sentinel vazio ao final da área de scroll dispara o
// `load-more` existente quando o usuário rola perto do fim (rootMargin 400px
// pré-carrega antes do fim). O botão "Load more" continua como fallback.
const scrollContainerRef = ref(null);
const sentinelRef = ref(null);
let infiniteScrollObserver = null;

const maybeEmitLoadMore = () => {
  if (props.hasMore && !props.loading) {
    // Nome do evento é contrato com o board (e o botão existente): mantém
    // kebab-case como o `load-more` já emitido no template.
    // eslint-disable-next-line vue/custom-event-name-casing
    emit('load-more', props.stage.id);
  }
};

const disconnectInfiniteScroll = () => {
  infiniteScrollObserver?.disconnect();
  infiniteScrollObserver = null;
};

const connectInfiniteScroll = () => {
  if (!scrollContainerRef.value || !sentinelRef.value) return;
  if (typeof IntersectionObserver === 'undefined') return;
  disconnectInfiniteScroll();
  infiniteScrollObserver = new IntersectionObserver(
    entries => {
      if (entries.some(entry => entry.isIntersecting)) maybeEmitLoadMore();
    },
    { root: scrollContainerRef.value, rootMargin: '400px', threshold: 0 }
  );
  infiniteScrollObserver.observe(sentinelRef.value);
};

onMounted(connectInfiniteScroll);
onBeforeUnmount(disconnectInfiniteScroll);
// Sem mais páginas, o observer perde a função — desconecta para não
// re-disparar; se voltar a haver (refetch com hasMore true), reconecta.
watch(
  () => props.hasMore,
  hasMore => {
    if (!hasMore) disconnectInfiniteScroll();
    else connectInfiniteScroll();
  }
);

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
    class="flex flex-col w-[280px] flex-shrink-0 h-full rounded-lg bg-n-solid-2 border border-n-weak transition-colors duration-150 motion-reduce:transition-none [content-visibility:auto] [contain-intrinsic-size:auto_280px_auto_100%] [contain:layout_style_paint]"
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
    <div
      ref="scrollContainerRef"
      class="flex-1 overflow-y-auto px-2 py-2 min-h-0"
    >
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
        <Virtualizer
          v-if="conversations.length > 0"
          v-slot="{ item: conversation }"
          :data="conversations"
        >
          <div class="pb-2">
            <PipelineBoardCard
              :key="conversation.id"
              :conversation="conversation"
              :stage="stage"
              @open="conv => emit('open-card', conv)"
              @open-conversation="conv => emit('open-conversation', conv)"
              @mark-read="conversationId => emit('mark-read', conversationId)"
              @mark-unread="
                conversationId => emit('mark-unread', conversationId)
              "
            />
          </div>
        </Virtualizer>
        <div
          v-else-if="!loading"
          class="flex items-center justify-center py-4 text-xs text-n-slate-10"
        >
          {{ t('PIPELINES.BOARD.COLUMN.EMPTY') }}
        </div>
      </template>
      <!-- Sentinel do scroll infinito: vazio, ao final da área de scroll. -->
      <div ref="sentinelRef" aria-hidden="true" />
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
