<script setup>
import { ref, reactive, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ColorPicker from 'dashboard/components-next/colorpicker/ColorPicker.vue';

// Mirrors Pipeline::DEFAULT_STAGES — used to prefill the columns editor on create.
const DEFAULT_STAGES = [
  { name: 'Pendente', color: '#6B7280' },
  { name: 'Follow-up', color: '#3B82F6' },
  { name: 'Proposta', color: '#F59E0B' },
  { name: 'Finalizado', color: '#10B981' },
];

const { t } = useI18n();
const store = useStore();

const dialogRef = ref(null);
const editingPipeline = ref(null);

const uiFlags = useMapGetter('pipelines/getUIFlags');
const isSaving = computed(
  () => uiFlags.value.isCreating || uiFlags.value.isUpdating
);

const isEditMode = computed(() => !!editingPipeline.value);

const state = reactive({
  name: '',
  // Each entry: { id?, name, color, conversations_count?, removed }
  stages: [],
});

const validationRules = {
  name: { required },
};

const v$ = useVuelidate(validationRules, state);

const nameError = computed(() =>
  v$.value.name.$error ? t('PIPELINES.FORM.NAME.ERROR') : ''
);

const activeStages = computed(() => state.stages.filter(s => !s.removed));
const hasEmptyStageName = computed(() =>
  activeStages.value.some(s => !s.name?.trim())
);

const isSubmitDisabled = computed(
  () =>
    v$.value.$invalid ||
    activeStages.value.length === 0 ||
    hasEmptyStageName.value
);

const open = (pipeline = null) => {
  editingPipeline.value = pipeline;
  state.name = pipeline?.name ?? '';
  state.stages = pipeline
    ? pipeline.stages.map(s => ({
        id: s.id,
        name: s.name,
        color: s.color,
        conversations_count: s.conversations_count || 0,
        removed: false,
      }))
    : DEFAULT_STAGES.map(s => ({ ...s, removed: false }));
  v$.value.$reset();
  dialogRef.value?.open();
};

const close = () => {
  dialogRef.value?.close();
};

const addStage = () => {
  state.stages.push({
    name: '',
    color: DEFAULT_STAGES[0].color,
    removed: false,
  });
};

const removeStage = stage => {
  if (stage.id) {
    // Keep the record so the payload can mark it for destruction.
    stage.removed = true;
  } else {
    state.stages.splice(state.stages.indexOf(stage), 1);
  }
};

const moveStage = (stage, direction) => {
  const active = state.stages.filter(s => !s.removed);
  const index = active.indexOf(stage);
  const target = index + direction;
  if (target < 0 || target >= active.length) return;

  const tmp = active[target];
  active[target] = active[index];
  active[index] = tmp;
  // Keep stages marked for removal at the end so their _destroy survives.
  state.stages = [...active, ...state.stages.filter(s => s.removed)];
};

const buildPayload = () => {
  const removed = state.stages.filter(s => s.removed && s.id);
  const pipelineStagesAttributes = [
    ...activeStages.value.map((s, index) => ({
      ...(s.id ? { id: s.id } : {}),
      name: s.name.trim(),
      color: s.color,
      position: index + 1,
    })),
    ...removed.map(s => ({ id: s.id, _destroy: true })),
  ];
  return {
    name: state.name.trim(),
    pipeline_stages_attributes: pipelineStagesAttributes,
  };
};

const handleSubmit = async () => {
  const isFormValid = await v$.value.$validate();
  if (!isFormValid || isSubmitDisabled.value) return;

  try {
    if (isEditMode.value) {
      await store.dispatch('pipelines/update', {
        id: editingPipeline.value.id,
        ...buildPayload(),
      });
      useAlert(t('PIPELINES.FORM.UPDATE_SUCCESS'));
    } else {
      await store.dispatch('pipelines/create', buildPayload());
      useAlert(t('PIPELINES.FORM.CREATE_SUCCESS'));
    }
    close();
  } catch (error) {
    useAlert(error?.response?.data?.error ?? t('PIPELINES.FORM.ERROR_MESSAGE'));
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    :title="
      isEditMode
        ? t('PIPELINES.FORM.EDIT_TITLE')
        : t('PIPELINES.FORM.CREATE_TITLE')
    "
    :confirm-button-label="
      isEditMode ? t('PIPELINES.FORM.UPDATE') : t('PIPELINES.FORM.SUBMIT')
    "
    :is-loading="isSaving"
    :disable-confirm-button="isSaving || isSubmitDisabled"
    width="2xl"
    overflow-y-auto
    @confirm="handleSubmit"
  >
    <Input
      v-model="state.name"
      :label="t('PIPELINES.FORM.NAME.LABEL')"
      :placeholder="t('PIPELINES.FORM.NAME.PLACEHOLDER')"
      :message="nameError"
      :message-type="nameError ? 'error' : 'info'"
      autofocus
    />

    <div class="flex flex-col gap-2">
      <div class="flex items-center justify-between">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('PIPELINES.FORM.STAGES.LABEL') }}
        </span>
        <Button
          variant="ghost"
          color="slate"
          size="sm"
          :label="t('PIPELINES.FORM.STAGES.ADD')"
          icon="i-lucide-plus"
          @click="addStage"
        />
      </div>

      <div
        v-if="activeStages.length === 0"
        class="py-3 text-sm text-center text-n-slate-11 rounded-lg bg-n-slate-3"
      >
        {{ t('PIPELINES.FORM.STAGES.EMPTY_HINT') }}
      </div>

      <template v-else>
        <div
          v-for="(stage, index) in activeStages"
          :key="stage.id || `new-${index}`"
          class="flex items-center gap-2"
        >
          <ColorPicker v-model="stage.color" class="shrink-0" />
          <Input
            v-model="stage.name"
            size="sm"
            :placeholder="t('PIPELINES.FORM.STAGES.NAME_PLACEHOLDER')"
            class="flex-1 min-w-0"
          />
          <div class="flex items-center gap-1 shrink-0">
            <Button
              variant="ghost"
              color="slate"
              icon="i-lucide-chevron-up"
              size="sm"
              :disabled="index === 0"
              :title="t('PIPELINES.FORM.STAGES.MOVE_UP')"
              @click="moveStage(stage, -1)"
            />
            <Button
              variant="ghost"
              color="slate"
              icon="i-lucide-chevron-down"
              size="sm"
              :disabled="index === activeStages.length - 1"
              :title="t('PIPELINES.FORM.STAGES.MOVE_DOWN')"
              @click="moveStage(stage, 1)"
            />
            <Button
              variant="ghost"
              color="ruby"
              icon="i-lucide-trash-2"
              size="sm"
              :disabled="
                activeStages.length === 1 || stage.conversations_count > 0
              "
              :title="
                stage.conversations_count > 0
                  ? t('PIPELINES.FORM.STAGES.CONVERSATIONS_BLOCK')
                  : t('PIPELINES.FORM.STAGES.REMOVE')
              "
              @click="removeStage(stage)"
            />
          </div>
        </div>
        <span v-if="hasEmptyStageName" class="text-xs text-n-ruby-11">
          {{ t('PIPELINES.FORM.STAGES.NAME_REQUIRED') }}
        </span>
      </template>
    </div>
  </Dialog>
</template>
