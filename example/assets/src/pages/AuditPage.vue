<script setup lang="ts">
// Who did what: the audit log, newest first, a page at a time. Staff only.
import { onMounted, ref } from "vue";
import { BlessAlert, BlessButton, BlessField, BlessInput, BlessSection, BlessSelect, BlessTable, BlessText } from "blessing-ui";
import { api, type AuditEntry } from "../api";

const families = [
  { value: "", label: "everything" },
  { value: "order.", label: "orders" },
  { value: "product.", label: "products" },
  { value: "flag.", label: "settings" },
  { value: "webhook.", label: "webhooks" },
  { value: "session.", label: "sign-ins" },
  { value: "password.", label: "passwords" },
  { value: "email.", label: "email addresses" },
  { value: "user.", label: "users" },
  { value: "file.", label: "files" },
];

const action = ref("");
const actor = ref("");
const subject = ref("");
const entries = ref<AuditEntry[]>([]);
const next = ref<number | null>(null);
const loading = ref(false);
const error = ref("");

async function load(more = false) {
  loading.value = true;
  error.value = "";
  const res = await api.audit({
    action: action.value || undefined,
    actor: actor.value.trim() || undefined,
    subject: subject.value.trim() || undefined,
    before: more ? (next.value ?? undefined) : undefined,
    limit: 25,
  });
  loading.value = false;
  if (!res.ok) {
    error.value = res.error.message;
    return;
  }
  entries.value = more ? [...entries.value, ...res.data.entries] : res.data.entries;
  next.value = res.data.next_before;
}
onMounted(() => load());

const columns = [
  { key: "when", label: "When" },
  { key: "actor", label: "Who" },
  { key: "action", label: "What" },
  { key: "subject", label: "Of" },
  { key: "details", label: "Details" },
  { key: "request", label: "Request" },
];
const rows = () =>
  entries.value.map((e) => ({
    id: e.id,
    when: new Date(e.at).toLocaleString(),
    actor: e.actor,
    action: e.action,
    subject: e.subject,
    details: Object.keys(e.details).length ? JSON.stringify(e.details) : "",
    request: e.request_id ? e.request_id.slice(0, 8) : "",
  }));
</script>

<template>
  <BlessSection title="Audit log" subtitle="who did what" watermark="audit">
    <form class="new" @submit.prevent="load()">
      <BlessField label="Show"><BlessSelect v-model="action" :options="families" data-testid="audit-action" /></BlessField>
      <BlessField label="Who"><BlessInput v-model="actor" placeholder="user:1" data-testid="audit-actor" /></BlessField>
      <BlessField label="Of"><BlessInput v-model="subject" placeholder="order:42" data-testid="audit-subject" /></BlessField>
      <BlessButton type="submit" color="accent" :loading="loading" data-testid="audit-apply">Show</BlessButton>
    </form>
    <BlessAlert v-if="error" color="danger" title="Can't show the log">{{ error }}</BlessAlert>
    <BlessText v-if="!loading && !entries.length && !error" as="p" muted data-testid="audit-empty">Nothing recorded for that.</BlessText>
    <BlessTable v-if="entries.length" :columns="columns" :rows="rows()" row-key="id" striped caption="Newest first" data-testid="audit-table" />
    <BlessButton v-if="next" variant="outline" :loading="loading" data-testid="audit-older" @click="load(true)">Older</BlessButton>
    <BlessText as="p" size="xs" muted>
      The log is append-only: the database refuses to change or remove an entry. “Request” is the id the server
      sent in <code>x-request-id</code>, the same one in its logs and traces.
    </BlessText>
  </BlessSection>
</template>
