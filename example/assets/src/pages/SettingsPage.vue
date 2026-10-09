<script setup lang="ts">
// Settings you can change while the service runs (flags). One switch pauses new orders on every
// node at once; the rest of the flags are a table. Staff only.
import { computed, onMounted, ref } from "vue";
import { BlessAlert, BlessButton, BlessField, BlessInput, BlessSection, BlessSwitch, BlessTable, BlessText, useToast } from "blessing-ui";
import { api, type Flag } from "../api";

const toast = useToast();
const flags = ref<Flag[]>([]);
const loading = ref(true);
const error = ref("");

async function load() {
  const res = await api.flags();
  loading.value = false;
  if (res.ok) flags.value = res.data.flags;
  else error.value = res.error.message;
}
onMounted(load);

// "orders.enabled" is on unless somebody set it to false
const ordersOn = computed(() => flags.value.find((f) => f.key === "orders.enabled")?.value !== false);
const saving = ref(false);

async function setOrders(on: boolean) {
  saving.value = true;
  const res = on ? await api.deleteFlag("orders.enabled") : await api.setFlag("orders.enabled", false);
  saving.value = false;
  if (res.ok) {
    toast.success({ title: on ? "Orders are open" : "Orders are paused on every node" });
    await load();
  } else toast.error({ title: res.error.message });
}

const key = ref("");
const value = ref("true");
const formError = ref("");

async function add() {
  formError.value = "";
  let parsed: unknown;
  try {
    parsed = JSON.parse(value.value);
  } catch {
    formError.value = "the value must be JSON: true, 50, \"text\", {\"a\": 1}";
    return;
  }
  const res = await api.setFlag(key.value.trim(), parsed);
  if (res.ok) {
    key.value = "";
    await load();
  } else formError.value = res.error.message;
}

async function remove(k: string) {
  const res = await api.deleteFlag(k);
  if (res.ok) await load();
  else toast.error({ title: res.error.message });
}

const columns = [
  { key: "key", label: "Setting" },
  { key: "shown", label: "Value" },
  { key: "when", label: "Changed" },
  { key: "act", label: "" },
];
const rows = () => flags.value.map((f) => ({ key: f.key, shown: JSON.stringify(f.value), when: new Date(f.updated_at).toLocaleString() }));
</script>

<template>
  <BlessSection title="Settings" subtitle="change while it runs" watermark="settings">
    <BlessAlert v-if="error" color="danger" title="Can't show the settings">{{ error }}</BlessAlert>
    <BlessSwitch :model-value="ordersOn" :disabled="saving || loading" data-testid="orders-switch" @update:model-value="setOrders">
      Accept new orders
    </BlessSwitch>
    <BlessText as="p" size="sm" muted data-testid="orders-state">
      <template v-if="ordersOn">New orders are accepted.</template>
      <template v-else>New orders are refused with a 503 on every node, until you turn this back on. Everything else keeps working.</template>
    </BlessText>

    <BlessTable v-if="flags.length" :columns="columns" :rows="rows()" row-key="key" caption="Every setting that has been set" data-testid="flags">
      <template #cell-act="{ row }"><a href="#/settings" @click.prevent="remove(row.key)">unset</a></template>
    </BlessTable>

    <form class="new" @submit.prevent="add">
      <BlessField label="Setting" required><BlessInput v-model="key" required placeholder="search.page_size" data-testid="flag-key" /></BlessField>
      <BlessField label="Value (JSON)" required><BlessInput v-model="value" required data-testid="flag-value" /></BlessField>
      <BlessButton type="submit" color="accent" data-testid="flag-set">Set</BlessButton>
    </form>
    <BlessAlert v-if="formError" color="danger" title="Not set">{{ formError }}</BlessAlert>
    <BlessText as="p" size="xs" muted>
      Saved in Postgres and cleared from every node's memory at once; a node that cannot hear the others serves its
      old value for at most a minute.
    </BlessText>
  </BlessSection>
</template>
