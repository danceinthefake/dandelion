<script setup lang="ts">
// A search snippet: plain text with the matching words marked. It is rendered with `{{ }}`,
// never `v-html`: the text is whatever an admin typed in a product's description.
import { computed } from "vue";
import { pieces } from "../highlight";

const props = defineProps<{ text: string | null | undefined }>();
const parts = computed(() => pieces(props.text));
</script>

<template>
  <span class="snippet" data-testid="snippet">
    <template v-for="(p, i) in parts" :key="i"><mark v-if="p.mark">{{ p.text }}</mark><template v-else>{{ p.text }}</template></template>
  </span>
</template>

<style>
.snippet mark {
  background: var(--bless-accent-soft, rgba(255, 200, 0, 0.35));
  color: inherit;
  padding: 0 0.15em;
}
</style>
