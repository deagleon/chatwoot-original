import { frontendURL } from 'dashboard/helper/URLHelper.js';

import PipelinesIndex from './pages/PipelinesIndex.vue';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const meta = {
  featureFlag: FEATURE_FLAGS.PIPELINES,
  permissions: ['administrator'],
};

const pipelinesRoutes = {
  routes: [
    {
      path: frontendURL('accounts/:accountId/pipelines'),
      children: [
        {
          path: '',
          name: 'pipelines_index',
          meta,
          component: PipelinesIndex,
        },
        {
          path: ':pipelineId',
          name: 'pipelines_board',
          meta,
          component: () => import('./pages/PipelineBoard.vue'),
        },
      ],
    },
  ],
};

export default pipelinesRoutes;
