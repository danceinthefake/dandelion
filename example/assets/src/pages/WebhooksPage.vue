<script setup lang="ts">
// Where the service tells other people's servers what happened. Staff only. The secret that
// signs what is sent is shown once, when the endpoint is made.
import { onMounted, ref } from "vue";
import { BlessAlert, BlessAlertDialog, BlessBadge, BlessButton, BlessCheckbox, BlessField, BlessInput, BlessSection, BlessTable, BlessText, useToast } from "blessing-ui";
import { api, type Webhook } from "../api";

const toast = useToast();
const hooks = ref<Webhook[]>([]);
const error = ref("");

async function load() {
  const res = await api.webhooks();
  if (res.ok) hooks.value = res.data.endpoints;
  else error.value = res.error.message;
}
onMounted(load);

const url = ref("");
const events = ref<string[]>(["order.created"]);
const creating = ref(false);
const formError = ref("");
const secret = ref("");

async function create() {
  creating.value = true;
  formError.value = "";
  const res = await api.createWebhook(url.value, events.value);
  creating.value = false;
  if (res.ok) {
    secret.value = res.data.secret ?? "";
    url.value = "";
    await load();
  } else formError.value = res.error.fields ? JSON.stringify(res.error.fields) : res.error.message;
}

const removing = ref<Webhook | null>(null);
const confirmRemove = ref(false);
async function remove() {
  confirmRemove.value = false; // the dialog stays open until it is told to close
  if (!removing.value) return;
  const res = await api.deleteWebhook(removing.value.id);
  if (res.ok) {
    toast.success({ title: "Removed" });
    await load();
  } else toast.error({ title: res.error.message });
  removing.value = null;
}

const columns = [
  { key: "id", label: "#" },
  { key: "url", label: "URL" },
  { key: "events", label: "Events" },
  { key: "active", label: "State" },
  { key: "act", label: "" },
];
const rows = () => hooks.value.map((h) => ({ ...h, events: h.events.join(", ") }));
</script>

<template>
  <BlessSection title="Webhooks" subtitle="tell other servers" watermark="hooks">
    <BlessAlert v-if="error" color="danger" title="Can't show the endpoints">{{ error }}</BlessAlert>
    <BlessAlert v-if="secret" color="warning" title="Copy the signing secret now: it is not shown again" dismissible data-testid="secret-box">
      <code data-testid="secret">{{ secret }}</code>
    </BlessAlert>
    <BlessTable v-if="hooks.length" :columns="columns" :rows="rows()" row-key="id" caption="Endpoints" data-testid="hooks">
      <template #cell-active="{ row }">
        <BlessBadge :color="row.active ? 'success' : 'text'">{{ row.active ? "on" : "off" }}</BlessBadge>
      </template>
      <template #cell-act="{ row }">
        <a href="#/webhooks" data-testid="hook-remove" @click.prevent="((removing = row), (confirmRemove = true))">remove</a>
      </template>
    </BlessTable>
    <BlessText v-else as="p" muted>No endpoints yet.</BlessText>

    <form class="new" @submit.prevent="create">
      <BlessField label="URL" required><BlessInput v-model="url" type="url" required placeholder="https://example.com/hooks" data-testid="hook-url" /></BlessField>
      <BlessField label="Events"><BlessCheckbox v-model="events" value="order.created">order.created</BlessCheckbox></BlessField>
      <BlessButton type="submit" color="accent" :loading="creating" data-testid="hook-add">Add endpoint</BlessButton>
    </form>
    <BlessAlert v-if="formError" color="danger" title="Not added">{{ formError }}</BlessAlert>
    <BlessText as="p" size="xs" muted>
      Every request is signed (<code>webhook-signature</code>) and retried with a growing wait if the other side is down;
      a server that keeps failing is left alone for a while. Addresses on private networks are refused unless the
      deployment allows them.
    </BlessText>
  </BlessSection>

  <BlessAlertDialog
    v-model="confirmRemove"
    title="Remove this endpoint?"
    :description="`${removing?.url ?? ''} will stop receiving events. Deliveries still waiting for it are dropped.`"
    confirm-label="Remove"
    color="danger"
    @confirm="remove"
  />
</template>
