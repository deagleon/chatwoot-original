<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import StageCleanupRulesAPI from 'dashboard/api/stageCleanupRules';
import AutomationActionPipelineStageInput from 'dashboard/components/widgets/AutomationActionPipelineStageInput.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';

const { t } = useI18n();
const store = useStore();
const { isCloudFeatureEnabled } = useAccount();

const pipelines = useMapGetter('pipelines/getPipelines');

const rules = ref([]);
const loading = ref(false);
const saving = ref(false);
const togglingId = ref(null);
const deletingId = ref(null);
const showForm = ref(false);
const form = ref({
  pipeline_id: null,
  stage_id: null,
  cleanup_time: '23:59',
});

const isPipelinesEnabled = computed(() =>
  isCloudFeatureEnabled(FEATURE_FLAGS.PIPELINES)
);

const canSave = computed(
  () => form.value.pipeline_id && form.value.stage_id && form.value.cleanup_time
);

// The cascade input emits { pipeline_id, stage_id } and replaces the whole
// model value, so keep cleanup_time out of its v-model target.
const stageSelection = computed({
  get: () => ({
    pipeline_id: form.value.pipeline_id,
    stage_id: form.value.stage_id,
  }),
  set: value => {
    form.value.pipeline_id = value.pipeline_id;
    form.value.stage_id = value.stage_id;
  },
});

const tableHeaders = computed(() => [
  t('AUTOMATION.STAGE_CLEANUP.COLUMN_LABEL'),
  t('AUTOMATION.STAGE_CLEANUP.TIME_LABEL'),
  t('AUTOMATION.STAGE_CLEANUP.ACTIVE'),
  '',
]);

const fetchRules = async () => {
  loading.value = true;
  try {
    const { data } = await StageCleanupRulesAPI.get();
    rules.value = data.payload || [];
  } catch {
    useAlert(t('AUTOMATION.STAGE_CLEANUP.ERROR'));
  } finally {
    loading.value = false;
  }
};

const saveRule = async () => {
  if (!canSave.value) return;
  saving.value = true;
  try {
    await StageCleanupRulesAPI.create({
      pipeline_stage_id: form.value.stage_id,
      cleanup_time: form.value.cleanup_time,
      active: true,
    });
    useAlert(t('AUTOMATION.STAGE_CLEANUP.SUCCESS'));
    form.value = {
      pipeline_id: null,
      stage_id: null,
      cleanup_time: '23:59',
    };
    showForm.value = false;
    fetchRules();
  } catch {
    useAlert(t('AUTOMATION.STAGE_CLEANUP.ERROR'));
  } finally {
    saving.value = false;
  }
};

const toggleRule = async (rule, active) => {
  togglingId.value = rule.id;
  try {
    await StageCleanupRulesAPI.update(rule.id, { active });
    rules.value = rules.value.map(record =>
      record.id === rule.id ? { ...record, active } : record
    );
  } catch {
    useAlert(t('AUTOMATION.STAGE_CLEANUP.ERROR'));
  } finally {
    togglingId.value = null;
  }
};

const deleteRule = async rule => {
  deletingId.value = rule.id;
  try {
    await StageCleanupRulesAPI.delete(rule.id);
    useAlert(t('AUTOMATION.STAGE_CLEANUP.DELETE_SUCCESS'));
    rules.value = rules.value.filter(record => record.id !== rule.id);
  } catch {
    useAlert(t('AUTOMATION.STAGE_CLEANUP.DELETE_ERROR'));
  } finally {
    deletingId.value = null;
  }
};

onMounted(async () => {
  if (!isPipelinesEnabled.value) return;
  if (!pipelines.value.length) {
    await store.dispatch('pipelines/get');
  }
  fetchRules();
});
</script>

<template>
  <section class="mt-8">
    <div class="flex items-center justify-between mb-4">
      <div>
        <h2 class="text-base font-semibold text-n-slate-12">
          {{ t('AUTOMATION.STAGE_CLEANUP.TITLE') }}
        </h2>
        <p class="mt-1 text-sm text-n-slate-10">
          {{ t('AUTOMATION.STAGE_CLEANUP.TIMEZONE_HINT') }}
        </p>
      </div>
      <Button
        :label="t('AUTOMATION.STAGE_CLEANUP.ADD')"
        size="sm"
        icon="ri-add-line"
        @click="showForm = !showForm"
      />
    </div>

    <form
      v-if="showForm"
      class="flex flex-col gap-4 p-4 mb-4 rounded-lg bg-n-slate-2"
      @submit.prevent="saveRule"
    >
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div class="flex flex-col gap-1.5">
          <span class="text-sm text-n-slate-11">
            {{ t('AUTOMATION.STAGE_CLEANUP.COLUMN_LABEL') }}
          </span>
          <AutomationActionPipelineStageInput
            v-model="stageSelection"
            :pipelines="pipelines"
          />
        </div>
        <div class="flex flex-col gap-1.5">
          <label class="text-sm text-n-slate-11" for="stage-cleanup-time">
            {{ t('AUTOMATION.STAGE_CLEANUP.TIME_LABEL') }}
          </label>
          <input
            id="stage-cleanup-time"
            v-model="form.cleanup_time"
            type="time"
            class="h-10 w-full rounded-lg bg-n-alpha-black2 px-3 py-2.5 text-sm text-n-slate-12 outline outline-1 outline-n-weak hover:outline-n-slate-6 focus:outline-n-brand transition-all duration-500 ease-in-out"
          />
        </div>
      </div>
      <div class="flex justify-end">
        <Button
          :label="t('AUTOMATION.STAGE_CLEANUP.SAVE')"
          size="sm"
          :disabled="!canSave"
          :is-loading="saving"
          type="submit"
        />
      </div>
    </form>

    <BaseTable
      :headers="tableHeaders"
      :items="rules"
      :loading="loading"
      :no-data-message="t('AUTOMATION.STAGE_CLEANUP.EMPTY')"
    >
      <template #row="{ items }">
        <BaseTableRow v-for="rule in items" :key="rule.id" :item="rule">
          <BaseTableCell>
            <span class="font-medium text-n-slate-12">
              {{ rule.pipeline_stage?.pipeline?.name }}
            </span>
            <span> {{ rule.pipeline_stage?.name }}</span>
          </BaseTableCell>
          <BaseTableCell>{{ rule.cleanup_time }}</BaseTableCell>
          <BaseTableCell>
            <Switch
              :model-value="rule.active"
              :disabled="togglingId === rule.id"
              @change="active => toggleRule(rule, active)"
            />
          </BaseTableCell>
          <BaseTableCell align="end">
            <Button
              :label="t('AUTOMATION.STAGE_CLEANUP.DELETE')"
              variant="ghost"
              color="ruby"
              size="sm"
              icon="ri-delete-bin-line"
              :disabled="deletingId === rule.id"
              :is-loading="deletingId === rule.id"
              @click="deleteRule(rule)"
            />
          </BaseTableCell>
        </BaseTableRow>
      </template>
    </BaseTable>
  </section>
</template>
