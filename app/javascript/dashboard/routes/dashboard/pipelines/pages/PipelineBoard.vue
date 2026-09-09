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
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import PipelinesAPI from 'dashboard/api/pipelines';
import ConversationAPI from 'dashboard/api/inbox/conversation';
import CmdBarConversationSnooze from 'dashboard/routes/dashboard/commands/CmdBarConversationSnooze.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import NextInput from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';

// Lazy: o ConversationBox (mensagens + composer + prosemirror) só carrega
// quando o preview abre — o board inicial não paga esse custo.
const ConversationBox = defineAsyncComponent(
  () => import('dashboard/components/widgets/conversation/ConversationBox.vue')
);
// Lazy pelo mesmo motivo: painel de contato (abre por padrão junto do
// preview) e Captain (opt-in) só carregam quando o preview os usa.
const ContactPanel = defineAsyncComponent(
  () => import('dashboard/routes/dashboard/conversation/ContactPanel.vue')
);
const CopilotContainer = defineAsyncComponent(
  () => import('dashboard/components/copilot/CopilotContainer.vue')
);
import PipelineBoardColumn from '../components/PipelineBoardColumn.vue';

const route = useRoute();
const store = useStore();
const { t } = useI18n();

const inboxes = useMapGetter('inboxes/getInboxes');
const agents = useMapGetter('agents/getAgents');
const labels = useMapGetter('labels/getLabels');
const currentAccountId = useMapGetter('getCurrentAccountId');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

const pipelineId = computed(() => route.params.pipelineId);

const stages = ref([]);
const conversationsByStage = reactive({});
const loadingByStage = reactive({});
const hasMoreByStage = reactive({});
const pageByStage = reactive({});
const selectedConversation = ref(null);
const previewDialogRef = ref(null);
const isLoading = ref(false);

// Modal-local side panel state: o preview não pode escrever nos uiSettings
// globais (is_contact_sidebar_open/is_copilot_panel_open) — eles controlam os
// painéis da view de conversa atrás do dialog e vazariam estado ao fechar.
const isContactPanelOpen = ref(false);
const isCopilotPanelOpen = ref(false);

const isCaptainEnabled = computed(() =>
  isFeatureEnabledonAccount.value(currentAccountId.value, FEATURE_FLAGS.CAPTAIN)
);

const isSidePanelOpen = computed(
  () => isContactPanelOpen.value || isCopilotPanelOpen.value
);

// Espelha o SidepanelSwitch: um painel lateral por vez.
const handleContactPanelToggle = () => {
  isContactPanelOpen.value = !isContactPanelOpen.value;
  isCopilotPanelOpen.value = false;
};

const handleCopilotPanelToggle = () => {
  isCopilotPanelOpen.value = !isCopilotPanelOpen.value;
  isContactPanelOpen.value = false;
};

const handleContactPanelClose = () => {
  isContactPanelOpen.value = false;
};

const handleCopilotPanelClose = () => {
  isCopilotPanelOpen.value = false;
};

const filters = reactive({
  inbox_ids: [],
  assignee_id: null,
  label: null,
  status: [],
  q: '',
  sort_by: 'last_activity_at',
});

let searchDebounce = null;
// Contador de requests do preview: só a resposta do clique mais recente pode
// escrever no store (evita overwrite por resposta antiga que chega atrasada).
let conversationPreviewRequest = 0;
// Debounce dos refetches disparados por conversation.created com busca (q)
// ativa — mesmo padrão do input de busca: um burst de eventos coalesce em um
// único refetch por coluna alvo.
const createdRefetchDebounce = {};
// Sequência de requests por coluna: só a resposta do request mais recente
// pode escrever no estado da coluna (evita resposta antiga — ex.: fetch
// filtrado por q em voo quando a busca foi limpa — sobrescrever o reload
// completo que resolveu depois).
const stageFetchRequestSeq = {};

const statusOptions = [
  { value: 'open', label: 'Open' },
  { value: 'resolved', label: 'Resolved' },
  { value: 'pending', label: 'Pending' },
  { value: 'snoozed', label: 'Snoozed' },
];

const sortOptions = [
  { value: 'last_activity_at', label: t('PIPELINES.BOARD.SORT.LAST_ACTIVITY') },
  { value: 'oldest', label: t('PIPELINES.BOARD.SORT.OLDEST_IN_STAGE') },
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
  if (filters.sort_by) params.sort_by = filters.sort_by;
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
  stageFetchRequestSeq[stageId] = (stageFetchRequestSeq[stageId] ?? 0) + 1;
  const requestSeq = stageFetchRequestSeq[stageId];
  loadingByStage[stageId] = true;
  try {
    const params = { ...buildParams(), page };
    const response = await PipelinesAPI.stageConversations(
      pipelineId.value,
      stageId,
      params
    );
    // Resposta de request antigo (ex.: fetch filtrado por q que ainda estava
    // em voo quando a busca foi limpa): descarta para não sobrescrever o
    // estado mais novo da coluna.
    if (requestSeq !== stageFetchRequestSeq[stageId]) return;
    // O endpoint envolve em json.data { meta, payload } — a leitura é
    // response.data.data, não response.data.
    const payload = response.data?.data?.payload ?? [];
    const meta = response.data?.data?.meta ?? {};
    if (page === 1) {
      conversationsByStage[stageId] = payload;
    } else {
      // Cartões inseridos em tempo real podem aparecer de novo na página do
      // servidor — o dedupe evita cards duplicados no append.
      const existingIds = new Set(conversationsByStage[stageId].map(c => c.id));
      conversationsByStage[stageId] = [
        ...conversationsByStage[stageId],
        ...payload.filter(c => !existingIds.has(c.id)),
      ];
    }
    hasMoreByStage[stageId] =
      payload.length > 0 &&
      conversationsByStage[stageId].length < (meta.all_count ?? 0);
    pageByStage[stageId] = page;
  } catch {
    // silently ignore — individual column errors don't block the board
  } finally {
    // Um request mais novo já em andamento mantém o loading dele.
    if (requestSeq === stageFetchRequestSeq[stageId]) {
      loadingByStage[stageId] = false;
    }
  }
};

const fetchAllColumns = () => {
  stages.value.forEach(stage => {
    fetchStageConversations(stage.id, 1);
  });
};

const sortColumn = stageId => {
  const list = conversationsByStage[stageId];
  if (!list) return;
  if (filters.sort_by === 'last_activity_at') {
    list.sort((a, b) => (b.last_activity_at || 0) - (a.last_activity_at || 0));
  } else {
    list.sort(
      (a, b) =>
        new Date(a.pipeline_stage_changed_at || 0).getTime() -
        new Date(b.pipeline_stage_changed_at || 0).getTime()
    );
  }
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

  // Optimistic move — o timestamp novo espelha o set_pipeline_stage_changed_at
  // do backend para a ordenação FIFO local bater com o servidor.
  conversationsByStage[fromStage.id] = conversationsByStage[
    fromStage.id
  ].filter(c => c.id !== conversationId);
  conversationsByStage[stageId] = [
    {
      ...conversation,
      pipeline_stage_id: stageId,
      pipeline_stage_changed_at: new Date().toISOString(),
    },
    ...conversationsByStage[stageId],
  ];
  sortColumn(stageId);

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
//
// O endpoint show (assim como a lista) só devolve a última mensagem no payload.
// setActiveChat dispara o fetch do histórico completo (fetchPreviousMessages) a
// partir da última mensagem e marca dataFetched para o MessagesView renderizar.
const activateChat = async data => {
  const existingChat = store.state.conversations.allConversations.find(
    c => c.id === data.id
  );
  // Reabrir a mesma conversa preserva o histórico completo no store
  // (SET_ALL_CONVERSATION mantém messages/dataFetched do chat selecionado);
  // pular o re-fetch aqui evita duplicar as mensagens na timeline.
  if (existingChat?.dataFetched) {
    store.commit(types.SET_CURRENT_CHAT_WINDOW, { id: data.id });
    return;
  }
  if ((data.messages || []).length === 0) {
    store.commit(types.SET_CURRENT_CHAT_WINDOW, { id: data.id });
    store.commit(types.SET_CHAT_DATA_FETCHED, data.id);
    return;
  }
  await store.dispatch('setActiveChat', { data });
};

const onCardMarkRead = conversationId => {
  const stage = stages.value.find(s =>
    conversationsByStage[s.id]?.some(c => c.id === conversationId)
  );
  if (!stage) return;
  const list = conversationsByStage[stage.id];
  const idx = list.findIndex(c => c.id === conversationId);
  if (idx === -1) return;
  list[idx] = { ...list[idx], unread_count: 0 };
};

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
    await activateChat(data);
  } catch {
    if (requestId !== conversationPreviewRequest) return;
    // Fallback: o payload do board já carrega a conversa (última mensagem inclusa).
    store.commit(types.SET_ALL_CONVERSATION, [conversation]);
    await activateChat(conversation);
  }
  // Abrir o preview = ler a conversa: zera o badge no card e atualiza o
  // agent_last_seen_at no backend.
  store.dispatch('markMessagesRead', { id: conversation.id });
  onCardMarkRead(conversation.id);
  // Painel de informações do cliente vem ativado por padrão ao abrir o
  // preview; o Captain continua opt-in.
  isContactPanelOpen.value = true;
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

// Refetch debounced da coluna alvo quando um created chega com busca (q)
// ativa — burst de eventos vira um único fetch por coluna.
const scheduleCreatedRefetch = stageId => {
  clearTimeout(createdRefetchDebounce[stageId]);
  createdRefetchDebounce[stageId] = setTimeout(() => {
    delete createdRefetchDebounce[stageId];
    fetchStageConversations(stageId, 1);
  }, 400);
};

// Real-time: react to conversation.created events from ActionCable so new
// conversations with a pipeline stage show up on the board without a refresh.
// O payload do cable (EventDataPresenter#push_data) já tem o mesmo shape do
// card do board (id = display_id, meta.sender, messages, last_activity_at
// epoch, pipeline_stage_changed_at ISO) — insere direto, como o merge do
// onConversationUpdated.
const matchesActiveFilters = data => {
  if (filters.inbox_ids.length && !filters.inbox_ids.includes(data.inbox_id))
    return false;
  if (filters.assignee_id && data.meta?.assignee?.id !== filters.assignee_id)
    return false;
  if (filters.label && !(data.labels || []).includes(filters.label))
    return false;
  if (filters.status.length && !filters.status.includes(data.status))
    return false;
  return true;
};

const onConversationCreated = data => {
  const stageId = data.pipeline_stage_id;
  if (!stageId || !conversationsByStage[stageId]) return;

  const alreadyOnBoard = Object.values(conversationsByStage).some(list =>
    list?.some(c => c.id === data.id)
  );
  if (alreadyOnBoard) return;

  // A busca (q) casa com conteúdo de mensagens/contatos no servidor — não dá
  // para avaliar client-side; re-fetcha a coluna alvo (debounced) para manter
  // o resultado correto.
  if (filters.q) {
    scheduleCreatedRefetch(stageId);
    return;
  }

  if (!matchesActiveFilters(data)) return;

  // Fetch da coluna em voo: a resposta substituiria conversationsByStage[stageId]
  // inteiro e descartaria o card recém-inserido. Invalida o request em voo
  // (bump de seq antes da inserção) e agenda o refetch para o estado convergir
  // com o servidor dentro da janela de debounce.
  if (loadingByStage[stageId]) {
    stageFetchRequestSeq[stageId] = (stageFetchRequestSeq[stageId] ?? 0) + 1;
    scheduleCreatedRefetch(stageId);
  }

  conversationsByStage[stageId] = [...conversationsByStage[stageId], data];
  sortColumn(stageId);
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

  // Cleanup jobs remove the conversation from its stage (pipeline_stage_id
  // becomes null): the card leaves the board instead of staying in place.
  if (!newStageId) {
    conversationsByStage[fromStage.id] = list.filter(
      c => c.id !== conversationId
    );
    return;
  }

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
    sortColumn(newStageId);
    sortColumn(fromStage.id);
  } else {
    conversationsByStage[fromStage.id] = list.map(c =>
      c.id === conversationId ? { ...c, ...data } : c
    );
    sortColumn(fromStage.id);
  }
};

// Real-time: react to message.created events from ActionCable and keep the
// card's unread state and preview fresh without refetching the column.
const onMessageCreated = data => {
  const conversationId = data.conversation_id;
  const stage = stages.value.find(s =>
    conversationsByStage[s.id]?.some(c => c.id === conversationId)
  );
  if (!stage) return;
  const list = conversationsByStage[stage.id];
  const idx = list.findIndex(c => c.id === conversationId);
  if (idx === -1) return;
  const card = list[idx];
  list[idx] = {
    ...card,
    unread_count: data.conversation?.unread_count ?? card.unread_count,
    last_activity_at:
      data.conversation?.last_activity_at ?? card.last_activity_at,
    ...(data.content ? { messages: [data] } : {}),
  };
  sortColumn(stage.id);
};

const onCardMarkUnread = async conversationId => {
  try {
    // O endpoint de unread responde sem payload; o show devolve o
    // unread_count recalculado após a marcação.
    const { data } = await ConversationAPI.show(conversationId);
    const stage = stages.value.find(s =>
      conversationsByStage[s.id]?.some(c => c.id === conversationId)
    );
    if (!stage) return;
    const list = conversationsByStage[stage.id];
    const idx = list.findIndex(c => c.id === conversationId);
    if (idx === -1) return;
    list[idx] = { ...list[idx], unread_count: data.unread_count ?? 1 };
  } catch {
    // ignora — o badge fica como está até o próximo evento
  }
};

const closePreview = () => {
  selectedConversation.value = null;
  // Reset dos painéis locais: o Captain volta fechado; o painel de contato é
  // reativado no próximo open() (padrão do preview).
  isCopilotPanelOpen.value = false;
  // Sem isso, a conversa continua "selecionada" no store e o
  // DashboardAudioNotificationHelper silencia os sons das mensagens novas
  // dela enquanto o board está aberto.
  store.dispatch('clearSelectedState');
};

onMounted(async () => {
  await fetchPipeline();
  fetchAllColumns();
  emitter.on(BUS_EVENTS.CONVERSATION_CREATED, onConversationCreated);
  emitter.on(BUS_EVENTS.CONVERSATION_UPDATED, onConversationUpdated);
  emitter.on(BUS_EVENTS.MESSAGE_CREATED, onMessageCreated);
});

onBeforeUnmount(() => {
  emitter.off(BUS_EVENTS.CONVERSATION_CREATED, onConversationCreated);
  emitter.off(BUS_EVENTS.CONVERSATION_UPDATED, onConversationUpdated);
  emitter.off(BUS_EVENTS.MESSAGE_CREATED, onMessageCreated);
  clearTimeout(searchDebounce);
  Object.values(createdRefetchDebounce).forEach(clearTimeout);
});

watch(
  [
    () => filters.inbox_ids,
    () => filters.assignee_id,
    () => filters.label,
    () => filters.status,
    () => filters.sort_by,
  ],
  () => fetchAllColumns()
);
</script>

<template>
  <div class="flex flex-col w-full h-full min-h-0 min-w-0">
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
      <ComboBox
        v-model="filters.sort_by"
        :options="sortOptions"
        :placeholder="t('PIPELINES.BOARD.SORT.PLACEHOLDER')"
        :aria-label="t('PIPELINES.BOARD.SORT.PLACEHOLDER')"
        class="max-w-52"
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
        @mark-read="onCardMarkRead"
        @mark-unread="onCardMarkUnread"
        @load-more="loadMore"
      />
    </div>

    <!-- Preview da conversa: ConversationBox embutido (header + mensagens +
         composer completos). O Dialog é ref-based — o open() precisa ser chamado. -->
    <Dialog
      ref="previewDialogRef"
      :title="selectedConversation?.meta?.sender?.name ?? ''"
      :width="isSidePanelOpen ? '7xl' : '5xl'"
      :show-cancel-button="false"
      :show-confirm-button="false"
      @close="closePreview"
    >
      <!-- Toggles dos painéis laterais do preview (contato / Captain): estado
           local ao modal, mesma linguagem visual do SidepanelSwitch. Sem
           tooltip (v-tooltip teleporta para o body, que pinta atrás do
           top-layer do dialog nativo) — o nome acessível vem do aria-label. -->
      <template #headerActions>
        <div v-if="selectedConversation" class="flex items-center gap-1">
          <Button
            ghost
            slate
            sm
            type="button"
            icon="i-ph-user-bold"
            class="!rounded-full transition-all duration-[250ms] ease-out active:!scale-95 active:!brightness-105 active:duration-75"
            :class="{ 'bg-n-alpha-2 active:shadow-sm': isContactPanelOpen }"
            :aria-label="t('CONVERSATION.SIDEBAR.CONTACT')"
            @click="handleContactPanelToggle"
          />
          <Button
            v-if="isCaptainEnabled"
            ghost
            slate
            sm
            type="button"
            icon="i-woot-captain"
            class="!rounded-full transition-all duration-[250ms] ease-out active:!scale-95 active:!brightness-105 active:duration-75"
            :class="{
              'bg-n-alpha-2 !text-n-iris-9 active:!brightness-105 active:shadow-sm':
                isCopilotPanelOpen,
            }"
            :aria-label="t('CONVERSATION.SIDEBAR.COPILOT')"
            @click="handleCopilotPanelToggle"
          />
          <Button
            ghost
            slate
            xs
            icon="i-lucide-x"
            class="!rounded-full ml-1"
            @click="previewDialogRef?.close()"
          />
        </div>
      </template>
      <!-- Modal espaçoso usando width 7xl/5xl e 80vh para acomodar mensagens,
           composer e painéis confortavelmente sem sufocar a conversa. -->
      <div class="flex flex-col min-h-[32rem] h-[80vh] max-h-[84vh]">
        <div class="flex flex-1 min-h-0">
          <ConversationBox
            class="h-full flex-1 min-h-0 flex flex-col"
            :is-contact-panel-open="false"
            :is-on-expanded-layout="false"
            :is-inbox-view="false"
          />
          <div
            v-if="isContactPanelOpen"
            class="w-[320px] shrink-0 h-full overflow-y-auto bg-n-surface-2 ltr:border-l rtl:border-r border-n-weak"
          >
            <ContactPanel
              :conversation-id="selectedConversation.id"
              :inbox-id="selectedConversation.inbox_id"
              embedded
              @close="handleContactPanelClose"
            />
          </div>
          <CopilotContainer
            v-if="isCopilotPanelOpen"
            embedded
            @close="handleCopilotPanelClose"
          />
        </div>
      </div>
    </Dialog>

    <!-- Listener do comando de snooze do palete ninja-keys (CMD_SNOOZE_CONVERSATION)
         + modal de horário customizado. Sem ele o snooze do menu de contexto
         do card não executa nada no board. -->
    <CmdBarConversationSnooze />
  </div>
</template>
