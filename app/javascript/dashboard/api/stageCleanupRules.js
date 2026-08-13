import ApiClient from './ApiClient';

class StageCleanupRulesAPI extends ApiClient {
  constructor() {
    super('automation_stage_cleanup_rules', { accountScoped: true });
  }
}

export default new StageCleanupRulesAPI();
