<script setup>
import {
  computed,
  onMounted,
  nextTick,
  onUnmounted,
  useTemplateRef,
  inject,
} from 'vue';
import { useWindowSize, useElementBounding, useScrollLock } from '@vueuse/core';

import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';

const props = defineProps({
  x: { type: Number, default: 0 },
  y: { type: Number, default: 0 },
});

const emit = defineEmits(['close']);

const elementToLock = inject('contextMenuElementTarget', null);

const menuRef = useTemplateRef('menuRef');
const dialogRef = useTemplateRef('dialogRef');

const scrollLockElement = computed(() => {
  if (!elementToLock?.value) return null;
  return elementToLock.value?.$el;
});

const isLocked = useScrollLock(scrollLockElement);

const { width: windowWidth, height: windowHeight } = useWindowSize();
const { width: menuWidth, height: menuHeight } = useElementBounding(menuRef);

const calculatePosition = (x, y, menuW, menuH, windowW, windowH) => {
  const PADDING = 16;
  // Initial position
  let left = x;
  let top = y;
  // Boundary checks
  const isOverflowingRight = left + menuW > windowW - PADDING;
  const isOverflowingBottom = top + menuH > windowH - PADDING;
  // Adjust position if overflowing
  if (isOverflowingRight) left = windowW - menuW - PADDING;
  if (isOverflowingBottom) top = windowH - menuH - PADDING;
  return {
    left: Math.max(PADDING, left),
    top: Math.max(PADDING, top),
  };
};

const position = computed(() => {
  // right/bottom/margin resetam o posicionamento centralizado do UA
  // stylesheet do dialog — sem eles left/top não ancoram o menu no clique
  // (o inset oposto fica 0 e as margens auto redistribuem o espaço).
  if (!menuRef.value) {
    return {
      top: `${props.y}px`,
      left: `${props.x}px`,
      right: 'auto',
      bottom: 'auto',
      margin: 0,
    };
  }

  const { left, top } = calculatePosition(
    props.x,
    props.y,
    menuWidth.value,
    menuHeight.value,
    windowWidth.value,
    windowHeight.value
  );

  return {
    top: `${top}px`,
    left: `${left}px`,
    right: 'auto',
    bottom: 'auto',
    margin: 0,
  };
});

onMounted(() => {
  isLocked.value = true;
  // showModal() coloca o menu no top layer do browser, acima de qualquer
  // outro dialog já aberto (ex.: o preview do pipeline board). Sem isso um
  // div fixed comum pinta atrás do top-layer e o menu "não abre".
  dialogRef.value?.showModal();
  nextTick(() => menuRef.value?.focus());
});

const handleClose = () => {
  isLocked.value = false;
  emit('close');
};

const handleFocusOut = event => {
  // Keep the menu open while focus stays inside it (e.g. the label search
  // input); close it once focus leaves the menu entirely.
  if (menuRef.value?.contains(event.relatedTarget)) {
    return;
  }
  handleClose();
};

const handleBackdropClick = event => {
  // Cliques no ::backdrop chegam com o próprio <dialog> como target; cliques
  // no conteúdo borram para os filhos.
  if (event.target === dialogRef.value) {
    handleClose();
  }
};

onUnmounted(() => {
  isLocked.value = false;
});
</script>

<template>
  <TeleportWithDirection to="body">
    <dialog
      ref="dialogRef"
      class="w-fit h-fit max-w-none max-h-none overflow-visible border-0 bg-transparent p-0 outline-none cursor-pointer backdrop:bg-transparent"
      :style="position"
      @click="handleBackdropClick"
      @close="handleClose"
    >
      <div
        ref="menuRef"
        class="outline-none cursor-pointer"
        tabindex="0"
        @focusout="handleFocusOut"
      >
        <slot />
      </div>
    </dialog>
  </TeleportWithDirection>
</template>
