<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  useFunctionGetter,
  useMapGetter,
  useStore,
} from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import integrationAPI from 'dashboard/api/integrations';
import { INBOX_TYPES, TWILIO_CHANNEL_MEDIUM } from 'dashboard/helper/inbox';

import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';

const { t } = useI18n();
const store = useStore();

const integrationLoaded = ref(false);
const apiKey = ref('');
const token = ref('');
const selectedBoardId = ref('');
const selectedWhatsappInboxId = ref('');
const boards = ref([]);
const isFetchingBoards = ref(false);
const isConnecting = ref(false);
const isDisconnecting = ref(false);
const dialogRef = ref(null);
const pendingBoardId = ref('');

const integration = useFunctionGetter('integrations/getIntegration', 'trello');

const uiFlags = useMapGetter('integrations/getUIFlags');
const inboxes = useMapGetter('inboxes/getInboxes');

// WhatsApp pode chegar como Channel::Whatsapp (Cloud API) ou como
// Channel::TwilioSms com medium whatsapp (Twilio) — mesma detecção do resto do app.
const whatsappInboxes = computed(() =>
  inboxes.value.filter(
    inbox =>
      inbox.channel_type === INBOX_TYPES.WHATSAPP ||
      (inbox.channel_type === INBOX_TYPES.TWILIO &&
        inbox.medium === TWILIO_CHANNEL_MEDIUM.WHATSAPP)
  )
);

const whatsappInboxOptions = computed(() =>
  whatsappInboxes.value.map(inbox => ({
    value: inbox.id,
    label: inbox.name,
  }))
);

const whatsappInboxName = inboxId =>
  whatsappInboxes.value.find(inbox => String(inbox.id) === String(inboxId))
    ?.name || inboxId;

const connectedBoards = computed(() => {
  const { hooks = [] } = integration.value || {};
  return hooks
    .map(hook => hook.settings)
    .filter(settings => settings && settings.board_id && settings.board_name);
});

const boardOptions = computed(() =>
  boards.value.map(board => ({ value: board.id, label: board.name }))
);

const canConnect = computed(
  () =>
    !!selectedBoardId.value &&
    !!selectedWhatsappInboxId.value &&
    boards.value.length > 0
);

const initializeTrelloIntegration = async () => {
  await Promise.all([
    store.dispatch('integrations/get'),
    store.dispatch('inboxes/get'),
  ]);
  integrationLoaded.value = true;
};

const loadBoards = async () => {
  isFetchingBoards.value = true;
  try {
    const { data } = await integrationAPI.fetchTrelloBoards({
      apiKey: apiKey.value,
      token: token.value,
    });
    boards.value = data;
    selectedBoardId.value = '';
  } catch (error) {
    const errorMessage = error.response?.data?.error;
    useAlert(
      errorMessage || t('INTEGRATION_SETTINGS.TRELLO.LOAD_BOARDS_ERROR')
    );
    boards.value = [];
  } finally {
    isFetchingBoards.value = false;
  }
};

const connect = async () => {
  isConnecting.value = true;
  try {
    await integrationAPI.connectTrello({
      apiKey: apiKey.value,
      token: token.value,
      boardId: selectedBoardId.value,
      whatsappInboxId: selectedWhatsappInboxId.value,
    });
    await store.dispatch('integrations/get');
    apiKey.value = '';
    token.value = '';
    boards.value = [];
    selectedBoardId.value = '';
    selectedWhatsappInboxId.value = '';
    useAlert(t('INTEGRATION_SETTINGS.TRELLO.CONNECT.SUCCESS'));
  } catch (error) {
    const errorMessage = error.response?.data?.error;
    useAlert(errorMessage || t('INTEGRATION_SETTINGS.TRELLO.CONNECT.ERROR'));
  } finally {
    isConnecting.value = false;
  }
};

const disconnectBoard = boardId => {
  pendingBoardId.value = boardId;
  if (dialogRef.value) {
    dialogRef.value.open();
  }
};

const confirmDisconnect = async () => {
  if (dialogRef.value) {
    dialogRef.value.close();
  }
  isDisconnecting.value = true;
  try {
    await integrationAPI.disconnectTrello({ boardId: pendingBoardId.value });
    await store.dispatch('integrations/get');
    useAlert(t('INTEGRATION_SETTINGS.TRELLO.DISCONNECT.SUCCESS'));
  } catch (error) {
    useAlert(t('INTEGRATION_SETTINGS.TRELLO.DISCONNECT.ERROR'));
  } finally {
    isDisconnecting.value = false;
    pendingBoardId.value = '';
  }
};

onMounted(() => {
  initializeTrelloIntegration();
});
</script>

<template>
  <SettingsLayout :is-loading="!integrationLoaded || uiFlags.isFetching">
    <template #header>
      <BaseSettingsHeader
        :title="$t('INTEGRATION_SETTINGS.TRELLO.HEADER')"
        description=""
        feature-name="trello_integration"
        :back-button-label="$t('INTEGRATION_SETTINGS.HEADER')"
      />
    </template>
    <template #body>
      <div class="flex flex-col gap-6">
        <div
          class="flex flex-col gap-4 p-6 outline outline-n-container outline-1 bg-n-card rounded-xl"
        >
          <h3 class="text-heading-1 text-n-slate-12">
            {{ $t('INTEGRATION_SETTINGS.TRELLO.CONNECTED_BOARDS.TITLE') }}
          </h3>
          <div v-if="connectedBoards.length" class="flex flex-col gap-3">
            <div
              v-for="board in connectedBoards"
              :key="board.board_id"
              class="flex flex-col items-start justify-between gap-2 sm:flex-row sm:items-center"
            >
              <div class="flex flex-col gap-1">
                <p class="text-body-main text-n-slate-12 mb-0">
                  {{ board.board_name }}
                </p>
                <p class="text-sm text-n-slate-11 mb-0">
                  {{ board.board_id }}
                </p>
                <p class="text-sm text-n-slate-11 mb-0">
                  {{
                    $t(
                      'INTEGRATION_SETTINGS.TRELLO.CONNECTED_BOARDS.INBOX_LABEL',
                      { inboxName: whatsappInboxName(board.whatsapp_inbox_id) }
                    )
                  }}
                </p>
              </div>
              <Button
                faded
                ruby
                :label="$t('INTEGRATION_SETTINGS.TRELLO.DISCONNECT.BUTTON')"
                :is-loading="isDisconnecting"
                @click="disconnectBoard(board.board_id)"
              />
            </div>
          </div>
          <p v-else class="text-body-main text-n-slate-11 mb-0">
            {{ $t('INTEGRATION_SETTINGS.TRELLO.CONNECTED_BOARDS.EMPTY') }}
          </p>
        </div>

        <div
          class="flex flex-col gap-4 p-6 outline outline-n-container outline-1 bg-n-card rounded-xl"
        >
          <h3 class="text-heading-1 text-n-slate-12">
            {{ $t('INTEGRATION_SETTINGS.TRELLO.CONNECT_FORM.TITLE') }}
          </h3>
          <div class="flex flex-col gap-4 max-w-xl">
            <Input
              v-model="apiKey"
              :label="
                $t('INTEGRATION_SETTINGS.TRELLO.CONNECT_FORM.API_KEY.LABEL')
              "
              :placeholder="
                $t(
                  'INTEGRATION_SETTINGS.TRELLO.CONNECT_FORM.API_KEY.PLACEHOLDER'
                )
              "
            />
            <Input
              v-model="token"
              type="password"
              :label="
                $t('INTEGRATION_SETTINGS.TRELLO.CONNECT_FORM.TOKEN.LABEL')
              "
              :placeholder="
                $t('INTEGRATION_SETTINGS.TRELLO.CONNECT_FORM.TOKEN.PLACEHOLDER')
              "
            />
            <div class="flex gap-2">
              <Button
                blue
                :label="
                  $t('INTEGRATION_SETTINGS.TRELLO.CONNECT_FORM.LOAD_BOARDS')
                "
                :is-loading="isFetchingBoards"
                :disabled="!apiKey || !token || isFetchingBoards"
                @click="loadBoards"
              />
            </div>
            <div v-if="boards.length" class="flex flex-col gap-2">
              <label class="text-sm font-medium text-n-slate-11">
                {{ $t('INTEGRATION_SETTINGS.TRELLO.CONNECT_FORM.BOARD.LABEL') }}
              </label>
              <Select
                v-model="selectedBoardId"
                :options="boardOptions"
                :placeholder="
                  $t(
                    'INTEGRATION_SETTINGS.TRELLO.CONNECT_FORM.BOARD.PLACEHOLDER'
                  )
                "
              />
              <label class="text-sm font-medium text-n-slate-11">
                {{
                  $t(
                    'INTEGRATION_SETTINGS.TRELLO.CONNECT_FORM.WHATSAPP_INBOX.LABEL'
                  )
                }}
              </label>
              <Select
                v-model="selectedWhatsappInboxId"
                :options="whatsappInboxOptions"
                :placeholder="
                  $t(
                    'INTEGRATION_SETTINGS.TRELLO.CONNECT_FORM.WHATSAPP_INBOX.PLACEHOLDER'
                  )
                "
              />
              <div class="mt-2">
                <Button
                  blue
                  :label="
                    $t('INTEGRATION_SETTINGS.TRELLO.CONNECT_FORM.CONNECT')
                  "
                  :is-loading="isConnecting"
                  :disabled="!canConnect || isConnecting"
                  @click="connect"
                />
              </div>
            </div>
          </div>
        </div>
      </div>
    </template>
  </SettingsLayout>
  <Dialog
    ref="dialogRef"
    type="alert"
    :title="$t('INTEGRATION_SETTINGS.TRELLO.DISCONNECT.CONFIRM.TITLE')"
    :description="$t('INTEGRATION_SETTINGS.TRELLO.DISCONNECT.CONFIRM.MESSAGE')"
    :confirm-button-label="$t('INTEGRATION_SETTINGS.TRELLO.DISCONNECT.BUTTON')"
    :cancel-button-label="$t('INTEGRATION_SETTINGS.TRELLO.DISCONNECT.CANCEL')"
    @confirm="confirmDisconnect"
  />
</template>
