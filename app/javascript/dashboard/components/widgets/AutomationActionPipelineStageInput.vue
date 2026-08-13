<script>
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';

export default {
  components: {
    SingleSelect,
  },
  props: {
    modelValue: {
      type: [Object, Array],
      default: () => [],
    },
    pipelines: { type: Array, required: true },
    dropdownMaxHeight: { type: String, default: 'max-h-80' },
  },
  emits: ['update:modelValue'],
  data() {
    return {
      selectedPipeline: null,
      selectedStage: null,
    };
  },
  computed: {
    pipelineOptions() {
      return (this.pipelines || []).map(pipeline => ({
        id: pipeline.id,
        name: pipeline.name,
      }));
    },
    stageOptions() {
      if (!this.selectedPipeline) return [];
      return (this.selectedPipeline.stages || []).map(stage => ({
        id: stage.id,
        name: stage.name,
      }));
    },
  },
  watch: {
    modelValue: 'hydrateFromModel',
  },
  mounted() {
    this.hydrateFromModel();
  },
  methods: {
    hydrateFromModel() {
      const params = Array.isArray(this.modelValue)
        ? this.modelValue[0]
        : this.modelValue;
      if (!params) {
        this.selectedPipeline = null;
        this.selectedStage = null;
        return;
      }
      const { pipeline_id: pipelineId, stage_id: stageId } = params;
      const pipeline =
        (this.pipelines || []).find(p => p.id === pipelineId) || null;
      this.selectedPipeline = pipeline;
      this.selectedStage =
        pipeline && stageId
          ? (pipeline.stages || []).find(stage => stage.id === stageId) || null
          : null;
    },
    onPipelineChange(pipeline) {
      // O SingleSelect emite apenas { id, name } — re-resolver o registro
      // completo mantém o array de stages disponível para o segundo select.
      this.selectedPipeline =
        (this.pipelines || []).find(p => p.id === pipeline?.id) || null;
      this.selectedStage = null;
      this.$emit('update:modelValue', {
        pipeline_id: this.selectedPipeline ? this.selectedPipeline.id : null,
        stage_id: null,
      });
    },
    onStageChange(stage) {
      this.selectedStage = stage || null;
      this.$emit('update:modelValue', {
        pipeline_id: this.selectedPipeline ? this.selectedPipeline.id : null,
        stage_id: this.selectedStage ? this.selectedStage.id : null,
      });
    },
  },
};
</script>

<template>
  <div class="flex flex-col gap-2">
    <SingleSelect
      :model-value="selectedPipeline"
      :options="pipelineOptions"
      :placeholder="$t('AUTOMATION.ACTION.PIPELINE_DROPDOWN_PLACEHOLDER')"
      :dropdown-max-height="dropdownMaxHeight"
      disable-deselect
      @update:model-value="onPipelineChange"
    />
    <SingleSelect
      :model-value="selectedStage"
      :options="stageOptions"
      :placeholder="$t('AUTOMATION.ACTION.STAGE_DROPDOWN_PLACEHOLDER')"
      :dropdown-max-height="dropdownMaxHeight"
      @update:model-value="onStageChange"
    />
  </div>
</template>
