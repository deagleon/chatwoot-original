class Api::V1::Accounts::PipelinesController < Api::V1::Accounts::BaseController
  before_action :ensure_pipeline_feature_enabled
  before_action :fetch_pipeline, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @pipelines = Current.account.pipelines.active.includes(:pipeline_stages)
  end

  def show; end

  def create
    @pipeline = Current.account.pipelines.create!(pipeline_params)
  end

  def update
    return render json: { error: 'Cannot delete a stage with conversations' }, status: :conflict if stages_to_destroy_with_conversations?

    @pipeline.update!(pipeline_params)
  end

  def destroy
    @pipeline.archive!
    head :ok
  end

  private

  def ensure_pipeline_feature_enabled
    render json: { error: 'Feature not enabled' }, status: :not_found unless Current.account.feature_enabled?('pipeline')
  end

  def fetch_pipeline
    @pipeline = Current.account.pipelines.find(params[:id])
  end

  def pipeline_params
    params.require(:pipeline).permit(
      :name,
      pipeline_stages_attributes: [:id, :name, :color, :position, :_destroy]
    )
  end

  def stages_to_destroy_with_conversations?
    attrs = params.dig(:pipeline, :pipeline_stages_attributes) || []
    destroy_ids = attrs.select { |a| ActiveModel::Type::Boolean.new.cast(a[:_destroy]) }.pluck(:id)
    return false if destroy_ids.empty?

    @pipeline.pipeline_stages.where(id: destroy_ids).joins(:conversations).exists?
  end
end
