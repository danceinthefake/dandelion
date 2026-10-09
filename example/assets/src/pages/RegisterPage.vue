<script setup lang="ts">
import { ref } from "vue";
import { BlessAlert, BlessButton, BlessField, BlessInput, BlessPasswordInput, BlessSection, BlessText } from "blessing-ui";
import { api } from "../api";
import { go } from "../router";

const email = ref("");
const password = ref("");
const loading = ref(false);
const error = ref("");

async function register() {
  loading.value = true;
  error.value = "";
  const made = await api.register(email.value, password.value);
  if (!made.ok) {
    loading.value = false;
    const f = made.error.fields as Record<string, string[]> | undefined;
    error.value = f ? Object.entries(f).map(([k, v]) => `${k} ${v.join(", ")}`).join("; ") : made.error.message;
    return;
  }
  const res = await api.login(email.value, password.value);
  loading.value = false;
  if (res.ok) go("/");
  else error.value = res.error.message;
}
</script>

<template>
  <BlessSection title="Create an account" watermark="new">
    <form class="new" @submit.prevent="register">
      <BlessField label="Email" required><BlessInput v-model="email" type="email" required autocomplete="username" data-testid="email" /></BlessField>
      <BlessField label="Password" required description="at least 10 characters">
        <BlessPasswordInput v-model="password" meter autocomplete="new-password" data-testid="password" />
      </BlessField>
      <BlessButton type="submit" color="accent" :loading="loading" data-testid="register">Create the account</BlessButton>
    </form>
    <BlessAlert v-if="error" color="danger" title="Not created" data-testid="register-error">{{ error }}</BlessAlert>
    <BlessText as="p" size="sm">We email a link to confirm the address. <a href="#/">Sign in</a> instead.</BlessText>
  </BlessSection>
</template>
