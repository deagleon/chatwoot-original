class Api::V1::Accounts::AutomationStageCleanupRulesController < Api::V1::Accounts::BaseController
  before_action :ensure_pipeline_feature_enabled
  before_action -> { check_authorization(StageCleanupRule) }
  before_action :fetch_rule, only: [:update, :destroy]

  def index
    @rules = Current.account.stage_cleanup_rules.includes(pipeline_stage: :pipeline).order(:created_at)
  end

  def create
    @rule = Current.account.stage_cleanup_rules.new(rule_params)
    return render_create_error unless @rule.save

    render :create
  end

  def update
    return render_create_error unless @rule.update(rule_params)

    render :update
  end

  def destroy
    @rule.destroy!
    head :ok
  end

  private

  def rule_params
    params.permit(:pipeline_stage_id, :cleanup_time, :active)
  end

  def fetch_rule
    @rule = Current.account.stage_cleanup_rules.find(params[:id])
  end

  def render_create_error
    render json: { error: @rule.errors.messages }, status: :unprocessable_entity
  end

  def ensure_pipeline_feature_enabled
    render json: { error: 'Feature not enabled' }, status: :not_found unless Current.account.feature_enabled?('pipeline')
  end
end
