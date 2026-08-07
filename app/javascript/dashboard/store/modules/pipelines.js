import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import types from '../mutation-types';
import PipelinesAPI from '../../api/pipelines';

export const state = {
  records: [],
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
  },
};

export const getters = {
  getUIFlags(_state) {
    return _state.uiFlags;
  },
  getPipelines: _state => {
    return _state.records;
  },
  getPipeline: _state => id => {
    return _state.records.find(record => record.id === id);
  },
};

export const actions = {
  get: async function getPipelines({ commit }) {
    commit(types.SET_PIPELINES_UI_FLAG, { isFetching: true });
    try {
      const response = await PipelinesAPI.get();
      commit(types.SET_PIPELINES, response.data.payload);
    } catch (error) {
      // Ignore error
    } finally {
      commit(types.SET_PIPELINES_UI_FLAG, { isFetching: false });
    }
  },
  create: async function createPipeline({ commit }, pipelineObj) {
    commit(types.SET_PIPELINES_UI_FLAG, { isCreating: true });
    try {
      const response = await PipelinesAPI.create(pipelineObj);
      commit(types.ADD_PIPELINE, response.data);
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_PIPELINES_UI_FLAG, { isCreating: false });
    }
  },
  update: async ({ commit }, { id, ...updateObj }) => {
    commit(types.SET_PIPELINES_UI_FLAG, { isUpdating: true });
    try {
      const response = await PipelinesAPI.update(id, updateObj);
      commit(types.EDIT_PIPELINE, response.data);
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_PIPELINES_UI_FLAG, { isUpdating: false });
    }
  },
  delete: async ({ commit }, id) => {
    commit(types.SET_PIPELINES_UI_FLAG, { isDeleting: true });
    try {
      await PipelinesAPI.delete(id);
      commit(types.DELETE_PIPELINE, id);
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_PIPELINES_UI_FLAG, { isDeleting: false });
    }
  },
};

export const mutations = {
  [types.SET_PIPELINES_UI_FLAG](_state, data) {
    _state.uiFlags = {
      ..._state.uiFlags,
      ...data,
    };
  },
  [types.ADD_PIPELINE]: MutationHelpers.create,
  [types.SET_PIPELINES]: MutationHelpers.set,
  [types.EDIT_PIPELINE]: MutationHelpers.update,
  [types.DELETE_PIPELINE]: MutationHelpers.destroy,
};

export default {
  namespaced: true,
  actions,
  state,
  getters,
  mutations,
};
