<script setup lang="ts">
// The page the email's link opens: /app/#/reset-password?token=…  (the token is after the #, so it
// is never sent to a server in a request line or kept in an access log).
import { computed, ref } from "vue";
import { BlessAlert, BlessButton, BlessField, BlessPasswordInput, BlessSection, BlessText } from "blessing-ui";
import { api } from "../api";
import { route } from "../router";

const token = computed(() => route.value.query.token ?? "");
const password = ref("");
const again = ref("");
const loading = ref(false);
const done = ref(false);
const error = ref("");

async function reset() {
  error.value = "";
  if (password.value !== again.value) {
    error.value = "The two passwords are not the same.";
    return;
  }
  loading.value = true;
  const res = await api.resetPassword(token.value, password.value);
  loading.value = false;
  if (res.ok) done.value = true;
  else {
    const f = res.error.fields as Record<string, string[]> | undefined;
    error.value = f?.password ? `The password ${f.password.join(", ")}.` : res.error.message;
  }
}
</script>

<template>
  <BlessSection title="Choose a new password" watermark="reset">
    <BlessAlert v-if="!token" color="danger" title="No link">Open the link from the email we sent you.</BlessAlert>
    <BlessAlert v-else-if="done" color="success" title="Password changed" data-testid="reset-done">
      Your password is changed and every other sign-in is ended. <a href="#/">Sign in</a> with the new one.
    </BlessAlert>
    <template v-else>
      <form class="new" @submit.prevent="reset">
        <BlessField label="New password" required description="at least 10 characters">
          <BlessPasswordInput v-model="password" meter autocomplete="new-password" data-testid="new-password" />
        </BlessField>
        <BlessField label="Again" required>
          <BlessPasswordInput v-model="again" autocomplete="new-password" data-testid="new-password-again" />
        </BlessField>
        <BlessButton type="submit" color="accent" :loading="loading" data-testid="reset">Change the password</BlessButton>
      </form>
      <BlessAlert v-if="error" color="danger" title="Not changed" data-testid="reset-error">{{ error }}</BlessAlert>
    </template>
    <BlessText as="p" size="sm"><a href="#/forgot-password">Ask for a new link</a></BlessText>
  </BlessSection>
</template>
