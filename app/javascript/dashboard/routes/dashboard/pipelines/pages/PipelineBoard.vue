<script setup>
import {
  ref,
  reactive,
  computed,
  onMounted,
  onBeforeUnmount,
  watch,
  defineAsyncComponent,
} from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

import types from 'dashboard/store/mutation-types';
import PipelinesAPI from 'dashboard/api/pipelines';
import ConversationAPI from 'dashboard/api/inbox/conversation';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import NextInput from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';

// Lazy: o ConversationBox (mensagens + composer + prosemirror) só carrega
// quando o preview abre — o board inicial não paga esse custo.
const ConversationBox = defineAsyncComponent(
  () => import('dashboard/components/widgets/conversation/ConversationBox.vue')
);
import PipelineBoardColumn from '../components/PipelineBoardColumn.vue';

const route = useRoute();
const store = useStore();
const { t } = useI18n();

const inboxes = useMapGetter('inboxes/getInboxes');
const agents = useMapGetter('agents/getAgents');
const labels = useMapGetter('labels/getLabels');

const pipelineId = computed(() => route.params.pipelineId);

const stages = ref([]);
const conversationsByStage = reactive({});
const loadingByStage = reactive({});
const hasMoreByStage = reactive({});
const pageByStage = reactive({});
const selectedConversation = ref(null);
const previewDialogRef = ref(null);
const isLoading = ref(false);

const filters = reactive({
  inbox_ids: [],
  assignee_id: null,
  label: null,
  status: [],
  q: '',
});

let searchDebounce = null;
// Contador de requests do preview: só a resposta do clique mais recente pode
// escrever no store (evita overwrite por resposta antiga que chega atrasada).
let conversationPreviewRequest = 0;

const statusOptions = [
  { value: 'open', label: 'Open' },
  { value: 'resolved', label: 'Resolved' },
  { value: 'pending', label: 'Pending' },
  { value: 'snoozed', label: 'Snoozed' },
];

const inboxOptions = computed(() =>
  (inboxes.value || []).map(i => ({ value: i.id, label: i.name }))
);
const assigneeOptions = computed(() => [
  { value: null, label: t('PIPELINES.BOARD.FILTER.ALL_ASSIGNEES') },
  ...(agents.value || []).map(a => ({ value: a.id, label: a.name })),
]);
const labelOptions = computed(() => [
  { value: null, label: t('PIPELINES.BOARD.FILTER.ALL_LABELS') },
  ...(labels.value || []).map(l => ({ value: l.title, label: l.title })),
]);

const buildParams = () => {
  const params = {};
  if (filters.inbox_ids.length) params.inbox_ids = filters.inbox_ids;
  if (filters.assignee_id) params.assignee_id = filters.assignee_id;
  if (filters.label) params.label = filters.label;
  if (filters.status.length) params.status = filters.status;
  if (filters.q) params.q = filters.q;
  return params;
};

const fetchPipeline = async () => {
  isLoading.value = true;
  try {
    const response = await PipelinesAPI.show(pipelineId.value);
    stages.value = (response.data.stages ?? []).sort(
      (a, b) => a.position - b.position
    );
    stages.value.forEach(stage => {
      conversationsByStage[stage.id] = [];
      pageByStage[stage.id] = 1;
      hasMoreByStage[stage.id] = false;
    });
  } catch {
    useAlert(t('PIPELINES.BOARD.ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const fetchStageConversations = async (stageId, page = 1) => {
  loadingByStage[stageId] = true;
  try {
    const params = { ...buildParams(), page };
    const response = await PipelinesAPI.stageConversations(
      pipelineId.value,
      stageId,
      params
    );
    // O endpoint envolve em json.data { meta, payload } — a leitura é
    // response.data.data, não response.data.
    const payload = response.data?.data?.payload ?? [];
    const meta = response.data?.data?.meta ?? {};
    if (page === 1) {
      conversationsByStage[stageId] = payload;
    } else {
      conversationsByStage[stageId] = [
        ...conversationsByStage[stageId],
        ...payload,
      ];
    }
    hasMoreByStage[stageId] =
      payload.length > 0 &&
      conversationsByStage[stageId].length < (meta.all_count ?? 0);
    pageByStage[stageId] = page;
  } catch {
    // silently ignore — individual column errors don't block the board
  } finally {
    loadingByStage[stageId] = false;
  }
};

const fetchAllColumns = () => {
  stages.value.forEach(stage => {
    fetchStageConversations(stage.id, 1);
  });
};

const handleDrop = async ({ stageId, conversationId }) => {
  if (!conversationId) return;

  const fromStage = stages.value.find(s =>
    conversationsByStage[s.id]?.some(c => c.id === conversationId)
  );
  if (fromStage?.id === stageId) return;

  const conversation = conversationsByStage[fromStage.id]?.find(
    c => c.id === conversationId
  );
  if (!conversation) return;

  // Optimistic move
  conversationsByStage[fromStage.id] = conversationsByStage[
    fromStage.id
  ].filter(c => c.id !== conversationId);
  conversationsByStage[stageId] = [
    { ...conversation, pipeline_stage_id: stageId },
    ...conversationsByStage[stageId],
  ];

  try {
    await ConversationAPI.moveToStage({
      conversationId,
      pipelineStageId: stageId,
    });
  } catch {
    // Revert on error
    conversationsByStage[stageId] = conversationsByStage[stageId].filter(
      c => c.id !== conversationId
    );
    conversationsByStage[fromStage.id] = [
      conversation,
      ...conversationsByStage[fromStage.id],
    ];
    useAlert(t('PIPELINES.BOARD.MOVE_ERROR'));
  }
};

// Preview da conversa: carrega a conversa completa no store e abre o modal com
// o ConversationBox embutido — todas as funcionalidades da conversa (mensagens,
// composer, ações) sem navegar para fora do board.
//
// getConversation só atualiza conversas já na lista do store; a conversa do
// board não está lá — então buscamos via API e adicionamos + selecionamos.
const openConversationInPanel = async conversation => {
  conversationPreviewRequest += 1;
  const requestId = conversationPreviewRequest;
  selectedConversation.value = conversation;
  try {
    const { data } = await ConversationAPI.show(conversation.id);
    // Cliques rápidos em cards diferentes podem resolver fora de ordem: só a
    // resposta do request mais recente pode escrever no store/abrir o modal.
    if (requestId !== conversationPreviewRequest) return;
    store.commit(types.SET_ALL_CONVERSATION, [data]);
    store.commit(types.SET_CURRENT_CHAT_WINDOW, { id: data.id });
  } catch {
    if (requestId !== conversationPreviewRequest) return;
    // Fallback: o payload do board já carrega a conversa (mensagens inclusas).
    store.commit(types.SET_ALL_CONVERSATION, [conversation]);
    store.commit(types.SET_CURRENT_CHAT_WINDOW, { id: conversation.id });
  }
  previewDialogRef.value?.open();
};

const openCard = conversation => {
  openConversationInPanel(conversation);
};

const loadMore = stageId => {
  fetchStageConversations(stageId, (pageByStage[stageId] ?? 1) + 1);
};

const onSearchInput = () => {
  clearTimeout(searchDebounce);
  searchDebounce = setTimeout(() => {
    fetchAllColumns();
  }, 400);
};

// Real-time: react to conversation.updated events from ActionCable
const onConversationUpdated = data => {
  const conversationId = data.id;
  const newStageId = data.pipeline_stage_id;

  const fromStage = stages.value.find(stage => {
    const list = conversationsByStage[stage.id];
    return list && list.some(c => c.id === conversationId);
  });
  if (!fromStage) return;

  const list = conversationsByStage[fromStage.id];
  const idx = list.findIndex(c => c.id === conversationId);
  if (idx === -1) return;

  if (newStageId && newStageId !== fromStage.id) {
    conversationsByStage[fromStage.id] = list.filter(
      c => c.id !== conversationId
    );
    if (conversationsByStage[newStageId]) {
      conversationsByStage[newStageId] = [
        { ...list[idx], ...data },
        ...conversationsByStage[newStageId],
      ];
    }
  } else {
    conversationsByStage[fromStage.id] = list.map(c =>
      c.id === conversationId ? { ...c, ...data } : c
    );
  }
};

onMounted(async () => {
  await fetchPipeline();
  fetchAllColumns();
  emitter.on(BUS_EVENTS.CONVERSATION_UPDATED, onConversationUpdated);
});

onBeforeUnmount(() => {
  emitter.off(BUS_EVENTS.CONVERSATION_UPDATED, onConversationUpdated);
  clearTimeout(searchDebounce);
});

watch(
  [
    () => filters.inbox_ids,
    () => filters.assignee_id,
    () => filters.label,
    () => filters.status,
  ],
  () => fetchAllColumns()
);
</script>

<template>
  <div class="flex flex-col h-full min-h-0">
    <!-- Filter bar — usa os componentes do design system (ComboBox single,
         TagMultiSelectComboBox multi) em vez de <select> nativos: visual
         consistente com a lista de conversas e a página de conversa. -->
    <div
      class="flex items-center gap-2 px-4 py-2 border-b border-n-weak flex-shrink-0"
    >
      <TagMultiSelectComboBox
        v-model="filters.inbox_ids"
        :options="inboxOptions"
        :placeholder="t('PIPELINES.BOARD.FILTER.INBOX')"
        :aria-label="t('PIPELINES.BOARD.FILTER.INBOX')"
        class="max-w-48"
      />
      <ComboBox
        v-model="filters.assignee_id"
        :options="assigneeOptions"
        :placeholder="t('PIPELINES.BOARD.FILTER.ASSIGNEE')"
        :aria-label="t('PIPELINES.BOARD.FILTER.ASSIGNEE')"
        class="max-w-40"
      />
      <ComboBox
        v-model="filters.label"
        :options="labelOptions"
        :placeholder="t('PIPELINES.BOARD.FILTER.LABEL')"
        :aria-label="t('PIPELINES.BOARD.FILTER.LABEL')"
        class="max-w-40"
      />
      <TagMultiSelectComboBox
        v-model="filters.status"
        :options="statusOptions"
        :placeholder="t('PIPELINES.BOARD.FILTER.STATUS')"
        :aria-label="t('PIPELINES.BOARD.FILTER.STATUS')"
        class="max-w-48"
      />
      <NextInput
        v-model="filters.q"
        type="text"
        size="sm"
        :placeholder="t('PIPELINES.BOARD.FILTER.SEARCH_PLACEHOLDER')"
        class="flex-1 max-w-60"
        @input="onSearchInput"
      />
    </div>

    <!-- Board -->
    <div
      v-if="isLoading"
      class="flex items-center justify-center flex-1 min-h-0"
    >
      <Icon
        icon="i-lucide-loader-2"
        class="size-6 animate-spin text-n-slate-10"
      />
    </div>
    <div v-else class="flex gap-4 p-4 overflow-x-auto flex-1 min-h-0">
      <PipelineBoardColumn
        v-for="stage in stages"
        :key="stage.id"
        :stage="stage"
        :conversations="conversationsByStage[stage.id] ?? []"
        :loading="!!loadingByStage[stage.id]"
        :has-more="!!hasMoreByStage[stage.id]"
        @drop="handleDrop"
        @open-card="openCard"
        @open-conversation="openConversationInPanel"
        @load-more="loadMore"
      />
    </div>

    <!-- Preview da conversa: ConversationBox embutido (header + mensagens +
         composer completos). O Dialog é ref-based — o open() precisa ser chamado. -->
    <Dialog
      ref="previewDialogRef"
      :title="selectedConversation?.meta?.sender?.name ?? ''"
      width="3xl"
      :show-cancel-button="false"
      :show-confirm-button="false"
      @close="selectedConversation = null"
    >
      <!-- Modal com altura que acomoda o conteúdo típico (header + mensagens +
           composer) e cresce até 80vh para conversas longas. O flex-1 + h-full
           no ConversationBox permite que o MessagesView (que tem h-full +
           flex-grow) ocupe o espaço entre header e composer. -->
      <div class="flex flex-col min-h-[28rem] h-[36rem] max-h-[80vh]">
        <ConversationBox
          class="h-full flex-1 min-h-0 flex flex-col"
          :is-contact-panel-open="false"
          :is-on-expanded-layout="false"
          is-inbox-view
        />
      </div>
    </Dialog>
  </div>
</template>
