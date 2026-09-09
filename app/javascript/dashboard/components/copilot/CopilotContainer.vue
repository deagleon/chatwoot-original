<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import Copilot from 'dashboard/components-next/copilot/Copilot.vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useWindowSize } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import wootConstants from 'dashboard/constants/globals';
import { MESSAGE_TYPE } from 'shared/constants/messages';

const props = defineProps({
  conversationInboxType: {
    type: String,
    default: '',
  },
  // When embedded (e.g. inside the pipeline board preview dialog), the panel
  // is force-shown regardless of the global is_copilot_panel_open UI setting
  // and renders statically within the parent layout instead of as a fixed
  // overlay. Default behavior (Dashboard-level panel) stays unchanged.
  embedded: {
    type: Boolean,
    default: false,
  },
});

defineEmits(['close']);

const store = useStore();
const { uiSettings, updateUISettings } = useUISettings();
const { width: windowWidth } = useWindowSize();

const currentUser = useMapGetter('getCurrentUser');
const assistants = useMapGetter('captainAssistants/getRecords');
const uiFlags = useMapGetter('captainAssistants/getUIFlags');
const inboxAssistant = useMapGetter('getCopilotAssistant');
const currentChat = useMapGetter('getSelectedChat');
const lastPublicMessage = useMapGetter('getLastEmailInSelectedChat');

const canSuggestReply = computed(
  () => lastPublicMessage.value?.message_type === MESSAGE_TYPE.INCOMING
);

const isSmallScreen = computed(
  () => windowWidth.value < wootConstants.SMALL_SCREEN_BREAKPOINT
);

const selectedCopilotThreadId = ref(null);
const messages = computed(() =>
  store.getters['copilotMessages/getMessagesByThreadId'](
    selectedCopilotThreadId.value
  )
);

const currentAccountId = useMapGetter('getCurrentAccountId');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

const selectedAssistantId = ref(null);

const activeAssistant = computed(() => {
  const preferredId = uiSettings.value.preferred_captain_assistant_id;

  // If the user has selected a specific assistant, it takes first preference for Copilot.
  if (preferredId) {
    const preferredAssistant = assistants.value.find(a => a.id === preferredId);
    // Return the preferred assistant if found, otherwise continue to next cases
    if (preferredAssistant) return preferredAssistant;
  }

  // If the above is not available, the assistant connected to the inbox takes preference.
  if (inboxAssistant.value) {
    const inboxMatchedAssistant = assistants.value.find(
      a => a.id === inboxAssistant.value.id
    );
    if (inboxMatchedAssistant) return inboxMatchedAssistant;
  }
  // If neither of the above is available, the first assistant in the account takes preference.
  return assistants.value[0];
});

const closeCopilotPanel = () => {
  // Embedded instances must not touch the global sidebar UI settings.
  if (props.embedded) return;
  if (isSmallScreen.value && uiSettings.value?.is_copilot_panel_open) {
    updateUISettings({
      is_contact_sidebar_open: false,
      is_copilot_panel_open: false,
    });
  }
};

const setAssistant = async assistant => {
  selectedAssistantId.value = assistant.id;
  await updateUISettings({
    preferred_captain_assistant_id: assistant.id,
  });
};

const shouldShowCopilotPanel = computed(() => {
  const isCaptainEnabled = isFeatureEnabledonAccount.value(
    currentAccountId.value,
    FEATURE_FLAGS.CAPTAIN
  );
  const { is_copilot_panel_open: isCopilotPanelOpen } = uiSettings.value;
  // Embedded instances are force-shown by the parent regardless of the global
  // is_copilot_panel_open setting; the assistants list is still fetched on
  // mount, but the embedded panel shows its own empty/loading state instead
  // of staying hidden while the list loads.
  const isPanelOpen =
    props.embedded || (isCopilotPanelOpen && !uiFlags.value.fetchingList);
  return isCaptainEnabled && isPanelOpen;
});

const containerClasses = computed(() =>
  props.embedded
    ? 'flex flex-col bg-n-surface-2 h-full w-[320px] min-w-[320px] shrink-0 overflow-hidden ltr:border-l rtl:border-r border-n-weak'
    : 'bg-n-surface-2 h-full overflow-hidden flex-col fixed top-0 ltr:right-0 rtl:left-0 z-40 w-full max-w-sm transition-transform duration-300 ease-in-out md:static md:w-[320px] md:min-w-[320px] ltr:border-l rtl:border-r border-n-weak 2xl:min-w-[360px] 2xl:w-[360px] shadow-lg md:shadow-none'
);

const handleReset = () => {
  selectedCopilotThreadId.value = null;
};

watch(() => currentChat.value?.id, handleReset);

const sendMessage = async payload => {
  const message = typeof payload === 'string' ? payload : payload.message;
  const requestType =
    typeof payload === 'string' ? undefined : payload.requestType;

  try {
    if (selectedCopilotThreadId.value) {
      await store.dispatch('copilotMessages/create', {
        assistant_id: activeAssistant.value.id,
        conversation_id: currentChat.value?.id,
        threadId: selectedCopilotThreadId.value,
        message,
      });
    } else {
      const conversationId = currentChat.value?.id;
      const response = await store.dispatch('copilotThreads/create', {
        assistant_id: activeAssistant.value.id,
        conversation_id: conversationId,
        message,
        ...(requestType && { request_type: requestType }),
      });
      if (currentChat.value?.id === conversationId) {
        selectedCopilotThreadId.value = response.id;
      }
    }
    return true;
  } catch (error) {
    useAlert(error.message);
    return false;
  }
};

onMounted(() => {
  store.dispatch('captainAssistants/get');
});
</script>

<template>
  <div
    v-if="shouldShowCopilotPanel"
    v-on-click-outside="() => closeCopilotPanel()"
    :class="[
      containerClasses,
      {
        'md:flex': shouldShowCopilotPanel,
        'md:hidden': !shouldShowCopilotPanel,
      },
    ]"
  >
    <Copilot
      :messages="messages"
      :support-agent="currentUser"
      :assistants="assistants"
      :active-assistant="activeAssistant"
      :embedded="embedded"
      :can-suggest-reply="canSuggestReply"
      :on-send-message="sendMessage"
      @set-assistant="setAssistant"
      @reset="handleReset"
      @close="$emit('close')"
    />
  </div>
  <template v-else />
</template>
