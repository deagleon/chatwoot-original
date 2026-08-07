<script setup>
import { ref, reactive, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';

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
});

const validationRules = {
  name: { required },
};

const v$ = useVuelidate(validationRules, state);

const nameError = computed(() =>
  v$.value.name.$error ? t('PIPELINES.FORM.NAME.ERROR') : ''
);

const isSubmitDisabled = computed(() => v$.value.$invalid);

const open = (pipeline = null) => {
  editingPipeline.value = pipeline;
  state.name = pipeline?.name ?? '';
  v$.value.$reset();
  dialogRef.value?.open();
};

const close = () => {
  dialogRef.value?.close();
};

const handleSubmit = async () => {
  const isFormValid = await v$.value.$validate();
  if (!isFormValid) return;

  try {
    if (isEditMode.value) {
      await store.dispatch('pipelines/update', {
        id: editingPipeline.value.id,
        name: state.name,
      });
      useAlert(t('PIPELINES.FORM.UPDATE_SUCCESS'));
    } else {
      await store.dispatch('pipelines/create', { name: state.name });
      useAlert(t('PIPELINES.FORM.CREATE_SUCCESS'));
    }
    close();
  } catch (error) {
    useAlert(error?.response?.message ?? t('PIPELINES.FORM.ERROR_MESSAGE'));
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
    @confirm="handleSubmit"
  >
    <Input
      v-model="state.name"
      :label="t('PIPELINES.FORM.NAME.LABEL')"
      :placeholder="t('PIPELINES.FORM.NAME.PLACEHOLDER')"
      :message="nameError"
      :message-type="nameError ? 'error' : 'info'"
      autofocus
      @enter="handleSubmit"
    />
  </Dialog>
</template>
