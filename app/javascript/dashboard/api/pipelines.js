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

  createStage(pipelineId, data) {
    return axios.post(`${this.url}/${pipelineId}/stages`, { stage: data });
  }

  updateStage(pipelineId, stageId, data) {
    return axios.patch(`${this.url}/${pipelineId}/stages/${stageId}`, {
      stage: data,
    });
  }

  deleteStage(pipelineId, stageId) {
    return axios.delete(`${this.url}/${pipelineId}/stages/${stageId}`);
  }
}

export default new PipelinesAPI();
