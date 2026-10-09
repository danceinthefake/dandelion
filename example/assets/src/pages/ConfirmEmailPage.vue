<script setup lang="ts">
// The page the confirmation email's link opens: /app/#/confirm-email?token=…
import { onMounted, ref } from "vue";
import { BlessAlert, BlessSection, BlessSpinner, BlessText } from "blessing-ui";
import { api } from "../api";
import { user } from "../auth";
import { route } from "../router";

const state = ref<"working" | "ok" | "bad">("working");
const message = ref("");

onMounted(async () => {
  const token = route.value.query.token;
  if (!token) {
    state.value = "bad";
    message.value = "Open the link from the email we sent you.";
    return;
  }
  const res = await api.confirmEmail(token);
  if (res.ok) {
    state.value = "ok";
    if (user.value?.id === res.data.id) user.value = { ...user.value, email_confirmed: true };
  } else {
    state.value = "bad";
    message.value = res.error.message;
  }
});
</script>

<template>
  <BlessSection title="Confirm your email address" watermark="email">
    <BlessSpinner v-if="state === 'working'" label="Confirming" />
    <BlessAlert v-else-if="state === 'ok'" color="success" title="Confirmed" data-testid="confirmed">
      Thank you: this address is confirmed. <a href="#/">Go to the console</a>.
    </BlessAlert>
    <BlessAlert v-else color="danger" title="Not confirmed" data-testid="not-confirmed">{{ message }}</BlessAlert>
    <BlessText as="p" size="sm" muted>A link works once. If it has been used, or is more than three days old, sign in and ask for another.</BlessText>
  </BlessSection>
</template>
