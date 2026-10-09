<script setup lang="ts">
import { ref } from "vue";
import { BlessAlert, BlessButton, BlessField, BlessInput, BlessSection, BlessText } from "blessing-ui";
import { api } from "../api";

const email = ref("");
const loading = ref(false);
const sent = ref(false);
const error = ref("");

async function ask() {
  loading.value = true;
  error.value = "";
  const res = await api.forgotPassword(email.value);
  loading.value = false;
  if (res.ok) sent.value = true;
  else error.value = res.error.message;
}
</script>

<template>
  <BlessSection title="Forgot your password?" watermark="reset">
    <template v-if="!sent">
      <form class="new" @submit.prevent="ask">
        <BlessField label="Your email address" required><BlessInput v-model="email" type="email" required data-testid="email" /></BlessField>
        <BlessButton type="submit" color="accent" :loading="loading" data-testid="ask">Send me a link</BlessButton>
      </form>
      <BlessAlert v-if="error" color="danger" title="Not sent">{{ error }}</BlessAlert>
    </template>
    <!-- the same words whether or not the address has an account: the server does not say -->
    <BlessAlert v-else color="success" title="Check your email" data-testid="sent">
      If there is an account for that address, an email with a link is on its way. The link works once, for an hour.
    </BlessAlert>
    <BlessText as="p" size="sm"><a href="#/">Back to sign in</a></BlessText>
  </BlessSection>
</template>
