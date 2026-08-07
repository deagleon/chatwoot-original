/* global axios */
import ApiClient from './ApiClient';

class PipelinesAPI extends ApiClient {
  constructor() {
    super('pipelines', { accountScoped: true });
  }

  stageConversations(pipelineId, stageId, params) {
    return axios.get(
      `${this.url}/${pipelineId}/stages/${stageId}/conversations`,
      { params }
    );
  }
}

export default new PipelinesAPI();
