<script setup>
import {
  ref,
  reactive,
  computed,
  onMounted,
  onBeforeUnmount,
  watch,
} from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { conversationUrl, frontendURL } from 'dashboard/helper/URLHelper';

import PipelinesAPI from 'dashboard/api/pipelines';
import ConversationAPI from 'dashboard/api/inbox/conversation';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import SidePanel from 'dashboard/components-next/side-panel/SidePanel.vue';
import PipelineBoardColumn from '../components/PipelineBoardColumn.vue';

const route = useRoute();
const router = useRouter();
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
const isLoading = ref(false);

const filters = reactive({
  inbox_ids: [],
  assignee_id: null,
  label: null,
  status: [],
  q: '',
});

let searchDebounce = null;

const statusOptions = [
  { value: 'open', label: 'Open' },
  { value: 'resolved', label: 'Resolved' },
  { value: 'pending', label: 'Pending' },
  { value: 'snoozed', label: 'Snoozed' },
];

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

const openCard = conversation => {
  selectedConversation.value = conversation;
};

const openFullConversation = () => {
  if (!selectedConversation.value) return;
  const path = frontendURL(
    conversationUrl({
      accountId: route.params.accountId,
      id: selectedConversation.value.id,
    })
  );
  router.push({ path });
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
    <!-- Filter bar -->
    <div
      class="flex items-center gap-3 px-4 py-2 border-b border-n-weak flex-shrink-0"
    >
      <select
        v-model="filters.inbox_ids"
        multiple
        class="text-sm border border-n-weak rounded px-2 py-1 bg-n-solid-1 text-n-slate-12 max-w-40"
        :aria-label="t('PIPELINES.BOARD.FILTER.INBOX')"
      >
        <option value="" disabled>
          {{ t('PIPELINES.BOARD.FILTER.ALL_INBOXES') }}
        </option>
        <option v-for="inbox in inboxes" :key="inbox.id" :value="inbox.id">
          {{ inbox.name }}
        </option>
      </select>
      <select
        v-model="filters.assignee_id"
        class="text-sm border border-n-weak rounded px-2 py-1 bg-n-solid-1 text-n-slate-12"
        :aria-label="t('PIPELINES.BOARD.FILTER.ASSIGNEE')"
      >
        <option :value="null">
          {{ t('PIPELINES.BOARD.FILTER.ALL_ASSIGNEES') }}
        </option>
        <option v-for="agent in agents" :key="agent.id" :value="agent.id">
          {{ agent.name }}
        </option>
      </select>
      <select
        v-model="filters.label"
        class="text-sm border border-n-weak rounded px-2 py-1 bg-n-solid-1 text-n-slate-12"
        :aria-label="t('PIPELINES.BOARD.FILTER.LABEL')"
      >
        <option :value="null">—</option>
        <option v-for="label in labels" :key="label.id" :value="label.title">
          {{ label.title }}
        </option>
      </select>
      <select
        v-model="filters.status"
        multiple
        class="text-sm border border-n-weak rounded px-2 py-1 bg-n-solid-1 text-n-slate-12 max-w-40"
        :aria-label="t('PIPELINES.BOARD.FILTER.STATUS')"
      >
        <option value="" disabled>
          {{ t('PIPELINES.BOARD.FILTER.ALL_STATUSES') }}
        </option>
        <option
          v-for="opt in statusOptions"
          :key="opt.value"
          :value="opt.value"
        >
          {{ opt.label }}
        </option>
      </select>
      <input
        v-model="filters.q"
        type="text"
        :placeholder="t('PIPELINES.BOARD.FILTER.SEARCH_PLACEHOLDER')"
        class="text-sm border border-n-weak rounded px-2 py-1 bg-n-solid-1 text-n-slate-12 flex-1 max-w-60"
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
        @load-more="loadMore"
      />
    </div>

    <!-- Drawer -->
    <SidePanel
      v-if="selectedConversation"
      :title="selectedConversation?.meta?.sender?.name ?? ''"
      width="lg"
      @close="selectedConversation = null"
    >
      <div class="flex flex-col gap-4">
        <div class="flex items-center gap-2">
          <span
            class="text-xs px-2 py-1 rounded font-medium bg-n-alpha-2 text-n-slate-12"
          >
            {{ selectedConversation?.status }}
          </span>
          <span class="text-xs text-n-slate-10">
            {{ t('PIPELINES.BOARD.CARD.ID') }}: {{ selectedConversation?.id }}
          </span>
        </div>
        <button
          class="text-sm text-n-brand hover:underline"
          @click="openFullConversation"
        >
          {{ t('PIPELINES.BOARD.DRAWER.OPEN') }}
        </button>
      </div>
    </SidePanel>
  </div>
</template>
