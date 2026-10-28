class CreatePipelineStages < ActiveRecord::Migration[7.1]
  def change
    create_table :pipeline_stages do |t|
      t.references :pipeline, null: false
      t.string :name, null: false
      t.string :color
      t.integer :position, null: false
      t.timestamps
    end
    add_index :pipeline_stages, [:pipeline_id, :position], unique: true, name: 'index_pipeline_stages_on_pipeline_id_and_position'
  end
end
