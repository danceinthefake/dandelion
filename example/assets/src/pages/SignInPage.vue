<script setup lang="ts">
import { ref } from "vue";
import { BlessAlert, BlessButton, BlessField, BlessInput, BlessSection, BlessText } from "blessing-ui";
import { api } from "../api";

const email = ref("");
const password = ref("");
const loading = ref(false);
const error = ref("");

async function login() {
  loading.value = true;
  error.value = "";
  const res = await api.login(email.value, password.value);
  loading.value = false;
  if (res.ok) {
    password.value = "";
    return;
  }
  // a locked address says how long
  const wait = res.error.retryAfter ? ` Try again in about ${Math.ceil(res.error.retryAfter / 60)} minutes.` : "";
  error.value = res.error.message + wait;
}
</script>

<template>
  <BlessSection title="Sign in" watermark="acme">
    <form class="new" @submit.prevent="login">
      <BlessField label="Email" required>
        <BlessInput v-model="email" type="email" required autocomplete="username" data-testid="email" />
      </BlessField>
      <BlessField label="Password" required>
        <BlessInput v-model="password" type="password" required autocomplete="current-password" data-testid="password" />
      </BlessField>
      <BlessButton type="submit" color="accent" :loading="loading" data-testid="sign-in">Sign in</BlessButton>
    </form>
    <BlessAlert v-if="error" color="danger" title="Not signed in" data-testid="sign-in-error">{{ error }}</BlessAlert>
    <BlessText as="p" size="sm">
      <a href="#/forgot-password" data-testid="forgot-link">Forgot your password?</a> ·
      <a href="#/register" data-testid="register-link">Create an account</a>
    </BlessText>
  </BlessSection>
</template>
