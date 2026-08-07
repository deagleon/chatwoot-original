<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import PipelineFormModal from '../components/PipelineFormModal.vue';

const store = useStore();
const router = useRouter();
const { t } = useI18n();

const pipelines = useMapGetter('pipelines/getPipelines');
const uiFlags = useMapGetter('pipelines/getUIFlags');

const isFetching = computed(() => uiFlags.value.isFetching);
const isDeleting = computed(() => uiFlags.value.isDeleting);

const searchQuery = ref('');
const showArchived = ref(false);

const formModalRef = ref(null);
const deleteDialogRef = ref(null);
const pipelineToDelete = ref(null);

const filteredPipelines = computed(() => {
  let list = pipelines.value;

  if (!showArchived.value) {
    list = list.filter(p => !p.archived_at);
  }

  if (searchQuery.value) {
    const query = searchQuery.value.toLowerCase();
    list = list.filter(p => p.name?.toLowerCase().includes(query));
  }

  return list;
});

const hasPipelines = computed(() => pipelines.value.length > 0);
const hasResults = computed(() => filteredPipelines.value.length > 0);

const totalConversations = pipeline => {
  if (!pipeline.stages) return 0;
  return pipeline.stages.reduce(
    (sum, stage) => sum + (stage.conversations_count || 0),
    0
  );
};

const openCreateModal = () => {
  formModalRef.value?.open();
};

const openEditModal = pipeline => {
  formModalRef.value?.open(pipeline);
};

const openDeleteDialog = pipeline => {
  pipelineToDelete.value = pipeline;
  deleteDialogRef.value?.open();
};

const confirmDelete = async () => {
  if (!pipelineToDelete.value) return;
  try {
    await store.dispatch('pipelines/delete', pipelineToDelete.value.id);
    useAlert(t('PIPELINES.DELETE.SUCCESS'));
  } catch (error) {
    useAlert(error?.response?.message ?? t('PIPELINES.DELETE.ERROR_MESSAGE'));
  } finally {
    pipelineToDelete.value = null;
  }
};

const navigateToBoard = pipeline => {
  router.push({
    name: 'pipelines_board',
    params: { pipelineId: pipeline.id },
  });
};

onMounted(() => {
  store.dispatch('pipelines/get');
});
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <header class="sticky top-0 z-10 px-6">
      <div class="w-full max-w-5xl mx-auto">
        <div class="flex items-center justify-between w-full h-20 gap-2">
          <span class="text-heading-1 text-n-slate-12">
            {{ t('PIPELINES.HEADER.TITLE') }}
          </span>
          <Button
            :label="t('PIPELINES.HEADER.NEW_PIPELINE')"
            icon="i-lucide-plus"
            size="sm"
            @click="openCreateModal"
          />
        </div>
        <div class="flex items-center gap-3 pb-4">
          <div class="relative flex-1">
            <span
              class="absolute left-3 top-1/2 -translate-y-1/2 i-lucide-search size-4 text-n-slate-10"
            />
            <input
              v-model="searchQuery"
              type="text"
              :placeholder="t('PIPELINES.HEADER.SEARCH_PLACEHOLDER')"
              class="block w-full h-10 pl-9 pr-3 text-sm border-none outline outline-1 outline-n-weak rounded-lg bg-n-alpha-black2 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-n-brand transition-all duration-200"
            />
          </div>
          <Button
            variant="faded"
            color="slate"
            size="sm"
            :label="
              showArchived
                ? t('PIPELINES.HIDE_ARCHIVED')
                : t('PIPELINES.SHOW_ARCHIVED')
            "
            :icon="showArchived ? 'i-lucide-eye-off' : 'i-lucide-eye'"
            @click="showArchived = !showArchived"
          />
        </div>
      </div>
    </header>

    <main class="flex-1 px-6 overflow-y-auto">
      <div class="w-full max-w-5xl mx-auto py-4">
        <div
          v-if="isFetching && !hasPipelines"
          class="flex items-center justify-center py-10 text-n-slate-11"
        >
          <Spinner />
        </div>

        <div
          v-else-if="!hasResults"
          data-testid="pipelines-empty-state"
          class="flex flex-col items-center justify-center py-20"
        >
          <span class="text-xl font-medium text-n-slate-12">
            {{ t('PIPELINES.EMPTY_STATE.TITLE') }}
          </span>
          <p class="mt-2 text-sm text-n-slate-11">
            {{ t('PIPELINES.EMPTY_STATE.SUBTITLE') }}
          </p>
          <Button
            class="mt-6"
            :label="t('PIPELINES.HEADER.NEW_PIPELINE')"
            icon="i-lucide-plus"
            size="sm"
            @click="openCreateModal"
          />
        </div>

        <table v-else class="w-full" data-testid="pipelines-table">
          <thead>
            <tr class="border-b border-n-weak text-left">
              <th class="py-3 px-4 text-sm font-medium text-n-slate-11">
                {{ t('PIPELINES.TABLE.NAME') }}
              </th>
              <th class="py-3 px-4 text-sm font-medium text-n-slate-11">
                {{ t('PIPELINES.TABLE.STAGES') }}
              </th>
              <th class="py-3 px-4 text-sm font-medium text-n-slate-11">
                {{ t('PIPELINES.TABLE.CONVERSATIONS') }}
              </th>
              <th
                class="py-3 px-4 text-sm font-medium text-n-slate-11 text-right"
              >
                {{ t('PIPELINES.TABLE.ACTIONS') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="pipeline in filteredPipelines"
              :key="pipeline.id"
              class="border-b border-n-weak hover:bg-n-slate-3/50 transition-colors cursor-pointer"
              data-testid="pipeline-row"
              @click="navigateToBoard(pipeline)"
            >
              <td class="py-3 px-4 text-sm text-n-slate-12">
                <div class="flex items-center gap-2">
                  <span class="font-medium">{{ pipeline.name }}</span>
                  <span
                    v-if="pipeline.archived_at"
                    class="px-2 py-0.5 text-xs rounded bg-n-slate-4 text-n-slate-11"
                  >
                    {{ t('PIPELINES.ARCHIVED') }}
                  </span>
                </div>
              </td>
              <td class="py-3 px-4 text-sm text-n-slate-11">
                {{
                  t('PIPELINES.STAGES_COUNT', {
                    count: pipeline.stages?.length || 0,
                  })
                }}
              </td>
              <td class="py-3 px-4 text-sm text-n-slate-11">
                {{
                  t('PIPELINES.CONVERSATIONS_COUNT', {
                    count: totalConversations(pipeline),
                  })
                }}
              </td>
              <td class="py-3 px-4 text-right">
                <div class="flex items-center justify-end gap-1">
                  <Button
                    variant="ghost"
                    color="slate"
                    icon="i-lucide-pencil"
                    size="sm"
                    @click.stop="openEditModal(pipeline)"
                  />
                  <Button
                    variant="ghost"
                    color="ruby"
                    icon="i-lucide-trash-2"
                    size="sm"
                    :is-loading="isDeleting"
                    @click.stop="openDeleteDialog(pipeline)"
                  />
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </main>

    <PipelineFormModal ref="formModalRef" />

    <Dialog
      ref="deleteDialogRef"
      type="alert"
      :title="t('PIPELINES.DELETE.TITLE')"
      :description="t('PIPELINES.DELETE.DESCRIPTION')"
      :confirm-button-label="t('PIPELINES.DELETE.CONFIRM')"
      :is-loading="isDeleting"
      @confirm="confirmDelete"
    />
  </section>
</template>
