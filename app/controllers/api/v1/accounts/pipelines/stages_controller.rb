class Api::V1::Accounts::Pipelines::StagesController < Api::V1::Accounts::BaseController
  before_action :ensure_pipeline_feature_enabled
  before_action :fetch_pipeline
  before_action :fetch_stage, only: [:update, :destroy, :conversations]
  before_action :check_authorization

  def create
    @stage = @pipeline.pipeline_stages.create!(stage_params)
  end

  def update
    @stage.update!(stage_params)
  end

  def destroy
    if @stage.conversations.exists?
      return render json: { error: 'Cannot delete a stage with conversations', conversations_count: @stage.conversations_count },
                    status: :conflict
    end

    @stage.destroy!
    head :ok
  end

  def conversations
    result = Conversations::StageFilterService.new(params, Current.user, Current.account, @stage).perform
    @conversations = result[:conversations]
    @conversations_count = result[:count]
  end

  private

  def check_authorization
    authorize(@stage || PipelineStage)
  end

  def ensure_pipeline_feature_enabled
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('pipeline')
  end

  def fetch_pipeline
    @pipeline = Current.account.pipelines.find(params[:pipeline_id])
  end

  def fetch_stage
    @stage = @pipeline.pipeline_stages.find(params[:id])
  end

  def stage_params
    params.require(:stage).permit(:name, :color, :position)
  end
end
