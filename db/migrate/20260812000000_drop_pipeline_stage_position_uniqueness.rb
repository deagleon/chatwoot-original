# frozen_string_literal: true

# Position is a display-order hint managed by the app (batch reorders via
# nested attributes swap adjacent positions mid-save, which a unique index
# would reject). Uniqueness is not required for correctness.
class DropPipelineStagePositionUniqueness < ActiveRecord::Migration[7.0]
  def change
    remove_index :pipeline_stages, column: %i[pipeline_id position],
                                   name: 'index_pipeline_stages_on_pipeline_id_and_position', unique: true
  end
end
