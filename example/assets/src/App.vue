<script setup lang="ts">
// The console: a sidebar, and a page for each thing the service does. Pages are chosen by the
// hash (`router.ts`). Staff see everything; a customer sees products and their own files.
// The pages that emailed links open (reset a password, confirm an address) work without a login.
import { computed, onMounted, ref } from "vue";
import { BlessAlert, BlessBadge, BlessButton, BlessSection, BlessStage, BlessText, BlessToaster, useToast } from "blessing-ui";
import { api } from "./api";
import { clearSession, getToken, user } from "./auth";
import AuditPage from "./pages/AuditPage.vue";
import ConfirmEmailPage from "./pages/ConfirmEmailPage.vue";
import FilesPage from "./pages/FilesPage.vue";
import ForgotPasswordPage from "./pages/ForgotPasswordPage.vue";
import OrdersPage from "./pages/OrdersPage.vue";
import ProductsPage from "./pages/ProductsPage.vue";
import RegisterPage from "./pages/RegisterPage.vue";
import ResetPasswordPage from "./pages/ResetPasswordPage.vue";
import SettingsPage from "./pages/SettingsPage.vue";
import SignInPage from "./pages/SignInPage.vue";
import WebhooksPage from "./pages/WebhooksPage.vue";
import { go, route } from "./router";

const toast = useToast();
const checking = ref(!!getToken());
const online = ref(0);

// a token kept from before this page was opened: is it still good?
onMounted(async () => {
  if (getToken()) {
    const res = await api.me();
    if (res.ok) user.value = res.data;
    else clearSession();
  }
  checking.value = false;
});

function logout() {
  clearSession();
  go("/");
}

const path = computed(() => route.value.path);
const admin = computed(() => user.value?.role === "admin");

// pages that need no login (the emailed links open them), and the sign-up
const open: Record<string, unknown> = {
  "/forgot-password": ForgotPasswordPage,
  "/reset-password": ResetPasswordPage,
  "/confirm-email": ConfirmEmailPage,
  "/register": RegisterPage,
};
const openPage = computed(() => open[path.value]);

// pages for staff
const staff: Record<string, unknown> = {
  "/audit": AuditPage,
  "/settings": SettingsPage,
  "/webhooks": WebhooksPage,
};
// pages for everybody who is signed in
const everyone: Record<string, unknown> = {
  "/products": ProductsPage,
  "/files": FilesPage,
};
const page = computed(() => (admin.value ? staff[path.value] : undefined) ?? everyone[path.value]);
const ordersRoute = computed(() => path.value === "/" || path.value.startsWith("/orders"));
const staffOnly = computed(() => !admin.value && (path.value in staff || path.value.startsWith("/orders")));

async function resend() {
  const res = await api.resendConfirmation();
  if (res.ok) toast.success({ title: "Sent: check your email" });
  else toast.error({ title: res.error.message });
}
</script>

<template>
  <BlessStage>
    <template #sidebar>
      <BlessText as="p" size="lg" weight="bold" class="brand">acme</BlessText>
      <nav v-if="user" class="nav" aria-label="Console">
        <a v-if="admin" href="#/" data-testid="nav-orders">Orders</a>
        <a href="#/products" data-testid="nav-products">Products</a>
        <a href="#/files" data-testid="nav-files">Files</a>
        <a v-if="admin" href="#/audit" data-testid="nav-audit">Audit log</a>
        <a v-if="admin" href="#/settings" data-testid="nav-settings">Settings</a>
        <a v-if="admin" href="#/webhooks" data-testid="nav-webhooks">Webhooks</a>
      </nav>
      <BlessText v-if="admin" as="p" size="xs" muted class="who">
        <BlessBadge color="info">{{ online }}</BlessBadge> online now
      </BlessText>
      <BlessText v-if="user" as="p" size="xs" muted class="me" data-testid="me">
        {{ user.email }} ({{ user.role }})
        <a href="#/" data-testid="sign-out" @click.prevent="logout">Sign out</a>
      </BlessText>
    </template>

    <BlessAlert v-if="user && !user.email_confirmed" color="warning" title="Your email address is not confirmed" data-testid="unconfirmed">
      We sent you a link when you registered.
      <BlessButton size="sm" variant="outline" data-testid="resend" @click="resend">Send it again</BlessButton>
    </BlessAlert>

    <component :is="openPage" v-if="openPage" />

    <template v-else-if="!user">
      <SignInPage v-if="!checking" />
    </template>

    <template v-else>
      <!-- v-show, not v-if: the feed stays joined (and you stay "online") on other pages -->
      <OrdersPage v-if="admin" v-show="ordersRoute" @online="(n: number) => (online = n)" />

      <BlessSection v-if="!admin && path === '/'" title="Welcome" watermark="acme">
        <BlessText as="p">
          Search the <a href="#/products">products</a>, keep your <a href="#/files">files</a>. Orders are made with the API:
          <code>POST /api/orders</code> with your token.
        </BlessText>
      </BlessSection>

      <BlessSection v-if="staffOnly" title="Staff only" watermark="staff" data-testid="staff-only">
        <BlessText as="p">This page is for staff.</BlessText>
      </BlessSection>

      <component :is="page" v-else-if="page" />
    </template>
    <BlessToaster />
  </BlessStage>
</template>

<style>
.brand {
  margin: 0 0 var(--bless-space-6);
  letter-spacing: var(--bless-tracking-wide);
}
.nav a {
  display: block;
  padding: var(--bless-space-2) 0;
}
.who {
  margin-top: var(--bless-space-8);
}
.new {
  display: grid;
  gap: var(--bless-space-4);
  grid-template-columns: repeat(auto-fit, minmax(12rem, 1fr));
  align-items: end;
  margin: var(--bless-space-6) 0;
}
</style>
