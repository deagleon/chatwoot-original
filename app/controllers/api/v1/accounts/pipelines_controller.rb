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
    @pipeline.update!(pipeline_params)
  end

  def destroy
    @pipeline.archive!
    head :ok
  end

  private

  def ensure_pipeline_feature_enabled
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('pipeline')
  end

  def fetch_pipeline
    @pipeline = Current.account.pipelines.find(params[:id])
  end

  def pipeline_params
    params.require(:pipeline).permit(:name)
  end
end
