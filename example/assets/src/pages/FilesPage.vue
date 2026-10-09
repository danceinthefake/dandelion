<script setup lang="ts">
// Your files: send one (with progress), download it, remove it. The server decides what a file
// is from its bytes (PNG, JPEG, PDF or text, up to 5 MB), not from its name.
import { onMounted, ref } from "vue";
import { BlessAlert, BlessButton, BlessFileInput, BlessProgress, BlessSection, BlessTable, BlessText, useToast } from "blessing-ui";
import { api, type StoredFile } from "../api";

const toast = useToast();
const files = ref<StoredFile[]>([]);
const chosen = ref<File[]>([]);
const progress = ref<number | null>(null);
const error = ref("");

async function load() {
  const res = await api.files();
  if (res.ok) files.value = res.data.files;
  else error.value = res.error.message;
}
onMounted(load);

async function upload() {
  const file = chosen.value[0];
  if (!file) return;
  error.value = "";
  progress.value = 0;
  const res = await api.uploadFile(file, (f) => (progress.value = Math.round(f * 100)));
  progress.value = null;
  if (res.ok) {
    toast.success({ title: `${res.data.filename} stored as ${res.data.content_type}` });
    chosen.value = [];
    await load();
  } else error.value = res.error.message;
}

async function download(f: StoredFile) {
  const res = await api.downloadFile(f);
  if (!res.ok) return toast.error({ title: res.error.message });
  const href = URL.createObjectURL(res.data);
  const a = document.createElement("a");
  a.href = href;
  a.download = f.filename;
  a.click();
  URL.revokeObjectURL(href);
}

async function remove(f: StoredFile) {
  const res = await api.deleteFile(f.id);
  if (res.ok) await load();
  else toast.error({ title: res.error.message });
}

const size = (n: number) => (n < 1024 ? `${n} B` : n < 1_048_576 ? `${(n / 1024).toFixed(1)} KB` : `${(n / 1_048_576).toFixed(1)} MB`);
const columns = [
  { key: "filename", label: "File" },
  { key: "type", label: "Type" },
  { key: "size", label: "Size", align: "right" as const },
  { key: "act", label: "" },
];
const rows = () => files.value.map((f) => ({ id: f.id, filename: f.filename, type: f.content_type, size: size(f.size) }));
</script>

<template>
  <BlessSection title="Files" subtitle="yours" watermark="files">
    <BlessFileInput v-model="chosen" accept=".png,.jpg,.jpeg,.pdf,.txt" label="Drop a file here, or choose one" hint="PNG, JPEG, PDF or text, up to 5 MB" list data-testid="file-input" />
    <BlessButton color="accent" :disabled="!chosen.length || progress !== null" data-testid="file-upload" @click="upload">Upload</BlessButton>
    <BlessProgress v-if="progress !== null" :value="progress" show-value label="Sending" data-testid="file-progress" />
    <BlessAlert v-if="error" color="danger" title="Not stored" data-testid="file-error">{{ error }}</BlessAlert>

    <BlessTable v-if="files.length" :columns="columns" :rows="rows()" row-key="id" caption="Your files" data-testid="files">
      <template #cell-act="{ row }">
        <a href="#/files" data-testid="file-download" @click.prevent="download(files.find((f) => f.id === row.id)!)">download</a>
        ·
        <a href="#/files" data-testid="file-remove" @click.prevent="remove(files.find((f) => f.id === row.id)!)">remove</a>
      </template>
    </BlessTable>
    <BlessText v-else as="p" muted>No files yet.</BlessText>
    <BlessText as="p" size="xs" muted>
      Stored on a directory every node sees: a file sent through one node downloads from any. Downloads are
      attachments, never shown as a page.
    </BlessText>
  </BlessSection>
</template>
