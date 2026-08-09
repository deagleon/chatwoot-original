/* global axios */
import ApiClient from './ApiClient';

class ScheduledMessagesAPI extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  index(conversationId) {
    return axios.get(`${this.url}/${conversationId}/scheduled_messages`);
  }

  create(conversationId, data) {
    return axios.post(`${this.url}/${conversationId}/scheduled_messages`, data);
  }

  update(conversationId, id, data) {
    return axios.patch(
      `${this.url}/${conversationId}/scheduled_messages/${id}`,
      data
    );
  }

  delete(conversationId, id) {
    return axios.delete(
      `${this.url}/${conversationId}/scheduled_messages/${id}`
    );
  }

  retry(conversationId, id) {
    return axios.post(
      `${this.url}/${conversationId}/scheduled_messages/${id}/retry`
    );
  }
}

export default new ScheduledMessagesAPI();
