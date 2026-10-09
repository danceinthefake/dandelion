<script setup lang="ts">
// Finding products as you type (Postgres full-text search on the server), and — for staff —
// adding, renaming and removing them. A search that is still on its way when you type the
// next letter is dropped, and only the newest answer is shown.
import { onUnmounted, ref, watch } from "vue";
import {
  BlessAlert,
  BlessAlertDialog,
  BlessBadge,
  BlessButton,
  BlessField,
  BlessInput,
  BlessSection,
  BlessTable,
  BlessText,
  BlessTextarea,
  useToast,
} from "blessing-ui";
import { api, money, type SearchResponse } from "../api";
import { user } from "../auth";
import Snippet from "../components/Snippet.vue";

const toast = useToast();
const q = ref("");
const result = ref<SearchResponse | null>(null);
const searching = ref(false);
const error = ref("");

let timer: ReturnType<typeof setTimeout> | undefined;
let controller: AbortController | null = null;
let latest = 0;

async function search(text: string) {
  controller?.abort();
  if (!text.trim()) {
    result.value = null;
    searching.value = false;
    return;
  }
  const mine = ++latest;
  controller = new AbortController();
  searching.value = true;
  const res = await api.searchProducts(text, controller.signal);
  if (mine !== latest) return; // a newer search has taken over
  searching.value = false;
  if (res.ok) {
    result.value = res.data;
    error.value = "";
  } else error.value = res.error.message;
}

watch(q, (text) => {
  clearTimeout(timer);
  timer = setTimeout(() => search(text), 150);
});
onUnmounted(() => {
  clearTimeout(timer);
  controller?.abort();
});

const columns = [
  { key: "sku", label: "SKU" },
  { key: "name", label: "Name" },
  { key: "snippet", label: "Description" },
  { key: "price", label: "Price", align: "right" as const },
];
const staff = () => user.value?.role === "admin";

// -- staff: add, edit, remove ------------------------------------------------------

const form = ref({ sku: "", name: "", description: "", price: "" });
const creating = ref(false);
const createError = ref("");

async function create() {
  creating.value = true;
  createError.value = "";
  const res = await api.createProduct({
    sku: form.value.sku,
    name: form.value.name,
    description: form.value.description || undefined,
    price_cents: Math.round(Number(form.value.price) * 100),
  });
  creating.value = false;
  if (res.ok) {
    toast.success({ title: `${res.data.name} added` });
    q.value = res.data.name; // and it is found straight away
    form.value = { sku: "", name: "", description: "", price: "" };
  } else createError.value = res.error.fields ? JSON.stringify(res.error.fields) : res.error.message;
}

const editing = ref<{ sku: string; name: string; description: string } | null>(null);
const saving = ref(false);

async function edit(sku: string) {
  const res = await api.product(sku);
  if (res.ok) editing.value = { sku, name: res.data.name, description: res.data.description ?? "" };
}

async function save() {
  if (!editing.value) return;
  saving.value = true;
  const { sku, name, description } = editing.value;
  const res = await api.updateProductDetails(sku, { name, description });
  saving.value = false;
  if (res.ok) {
    toast.success({ title: `${res.data.name} saved` });
    editing.value = null;
    search(q.value);
  } else toast.error({ title: res.error.message });
}

const removing = ref<string | null>(null);
const confirmRemove = ref(false);
async function remove() {
  confirmRemove.value = false; // the dialog stays open until it is told to close
  if (!removing.value) return;
  const res = await api.deleteProduct(removing.value);
  if (res.ok) {
    toast.success({ title: `${removing.value} removed` });
    search(q.value);
  } else toast.error({ title: res.error.message });
  removing.value = null;
}
</script>

<template>
  <BlessSection title="Products" subtitle="search" watermark="search">
    <BlessField label="Search">
      <BlessInput v-model="q" type="search" placeholder="try: gre, or grean tea" autocomplete="off" data-testid="search" />
    </BlessField>
    <BlessText as="p" size="sm" muted data-testid="search-status">
      <template v-if="searching">searching…</template>
      <template v-else-if="result && result.match === 'none'">nothing found for “{{ result.query }}”</template>
      <template v-else-if="result">{{ result.total }} found for “{{ result.query }}”</template>
      <template v-else>words, or the start of words: every word has to match</template>
    </BlessText>
    <BlessAlert v-if="error" color="danger" title="Search failed">{{ error }}</BlessAlert>
    <BlessAlert v-if="result?.match === 'fuzzy'" color="info" title="No exact match" data-testid="fuzzy">
      Showing names that are close to what you typed.
    </BlessAlert>

    <BlessTable
      v-if="result && result.results.length"
      :columns="columns"
      :rows="result.results.map((r) => ({ ...r, price: money(r.price_cents) }))"
      row-key="sku"
      caption="Results"
      data-testid="results"
    >
      <template #cell-snippet="{ row }"><Snippet :text="row.snippet" /></template>
      <template #cell-sku="{ row }">
        {{ row.sku }}
        <template v-if="staff()">
          · <a href="#/products" data-testid="edit" @click.prevent="edit(row.sku)">edit</a>
          · <a href="#/products" data-testid="remove" @click.prevent="((removing = row.sku), (confirmRemove = true))">remove</a>
        </template>
      </template>
    </BlessTable>
  </BlessSection>

  <BlessSection v-if="staff() && editing" :title="`Edit ${editing.sku}`" watermark="edit">
    <form class="new" @submit.prevent="save">
      <BlessField label="Name" required><BlessInput v-model="editing.name" required data-testid="edit-name" /></BlessField>
      <BlessField label="Description"><BlessTextarea v-model="editing.description" :rows="3" data-testid="edit-description" /></BlessField>
      <BlessButton type="submit" color="accent" :loading="saving">Save</BlessButton>
      <BlessButton type="button" variant="outline" @click="editing = null">Cancel</BlessButton>
    </form>
  </BlessSection>

  <BlessSection v-if="staff()" title="Add a product" watermark="new">
    <form class="new" @submit.prevent="create">
      <BlessField label="SKU" required><BlessInput v-model="form.sku" required data-testid="new-sku" /></BlessField>
      <BlessField label="Name" required><BlessInput v-model="form.name" required data-testid="new-name" /></BlessField>
      <BlessField label="Price" required>
        <BlessInput v-model="form.price" type="number" min="0" step="0.01" required data-testid="new-price" />
      </BlessField>
      <BlessField label="Description"><BlessTextarea v-model="form.description" :rows="2" data-testid="new-description" /></BlessField>
      <BlessButton type="submit" color="accent" :loading="creating" data-testid="new-submit">Add</BlessButton>
    </form>
    <BlessAlert v-if="createError" color="danger" title="Not added">{{ createError }}</BlessAlert>
    <BlessText as="p" size="xs" muted>
      A product is searchable the moment it is saved, from every node: there is no index to wait for.
      <BlessBadge color="info">full-text search in Postgres</BlessBadge>
    </BlessText>
  </BlessSection>

  <BlessAlertDialog
    v-model="confirmRemove"
    title="Remove this product?"
    :description="`${removing ?? ''} will no longer be sold or found. Orders keep the lines they were made with.`"
    confirm-label="Remove"
    color="danger"
    @confirm="remove"
  />
</template>
