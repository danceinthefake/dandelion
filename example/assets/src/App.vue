<script setup lang="ts">
import { onMounted, onUnmounted, ref, watch } from "vue";
import {
  BlessAlert,
  BlessBadge,
  BlessButton,
  BlessField,
  BlessInput,
  BlessSection,
  BlessStage,
  BlessTable,
  BlessText,
  BlessToaster,
  useToast,
} from "blessing-ui";
import { api, money, type Order } from "./api";
import OrderFeed from "./OrderFeed.vue";

const toast = useToast();

// -- where: #/ (feed + new order) or #/orders/42 (detail) ---------------------

const orderId = ref<number | null>(null);
function followHash() {
  const m = location.hash.match(/^#\/orders\/(\d+)$/);
  orderId.value = m ? Number(m[1]) : null;
}
onMounted(() => {
  followHash();
  addEventListener("hashchange", followHash);
});
onUnmounted(() => removeEventListener("hashchange", followHash));

const online = ref(0);
const feed = ref<InstanceType<typeof OrderFeed>>();

// -- new order ------------------------------------------------------------------

const email = ref("");
const sku = ref("TEA-01");
const quantity = ref(1);
const price = ref(15);
const creating = ref(false);
const createError = ref("");

async function create() {
  creating.value = true;
  createError.value = "";
  const res = await api.createOrder({
    customer_email: email.value,
    items: [{ sku: sku.value, quantity: Number(quantity.value), price_cents: Math.round(Number(price.value) * 100) }],
  });
  creating.value = false;
  if (res.ok) toast.success({ title: `Order #${res.data.id} created` });
  else createError.value = res.error.fields ? JSON.stringify(res.error.fields) : res.error.message;
}

// -- detail -------------------------------------------------------------------

const order = ref<Order | null>(null);
const detailError = ref("");
const cancelling = ref(false);

async function load(id: number) {
  order.value = null;
  detailError.value = "";
  const res = await api.order(id);
  if (res.ok) order.value = res.data;
  else detailError.value = res.error.message;
}

async function cancel() {
  if (!order.value) return;
  cancelling.value = true;
  const res = await api.cancelOrder(order.value.id);
  cancelling.value = false;
  if (res.ok) {
    order.value = res.data;
    feed.value?.replace(res.data);
  } else toast.error({ title: res.error.message });
}

watch(orderId, (id) => id && load(id), { immediate: true });

const itemColumns = [
  { key: "sku", label: "SKU" },
  { key: "quantity", label: "Qty", align: "right" as const },
  { key: "price", label: "Price", align: "right" as const },
];
</script>

<template>
  <BlessStage>
    <template #sidebar>
      <BlessText as="p" size="lg" weight="bold" class="brand">acme</BlessText>
      <nav class="nav">
        <a href="#/">Orders</a>
      </nav>
      <BlessText as="p" size="xs" muted class="who">
        <BlessBadge color="info">{{ online }}</BlessBadge> online now
      </BlessText>
    </template>

    <!-- v-show, not v-if: the feed stays joined (and you stay "online") on the detail page -->
    <BlessSection v-show="orderId === null" title="Orders" subtitle="live" watermark="orders">
      <form class="new" @submit.prevent="create">
        <BlessField label="Customer email" required>
          <BlessInput v-model="email" type="email" required placeholder="sari@example.com" />
        </BlessField>
        <BlessField label="SKU" required><BlessInput v-model="sku" required /></BlessField>
        <BlessField label="Quantity"><BlessInput v-model="quantity" type="number" min="1" /></BlessField>
        <BlessField label="Price"><BlessInput v-model="price" type="number" min="0" step="0.01" /></BlessField>
        <BlessButton type="submit" color="accent" :loading="creating">New order</BlessButton>
      </form>
      <BlessAlert v-if="createError" color="danger" title="Not created">{{ createError }}</BlessAlert>

      <OrderFeed ref="feed" @online="(n) => (online = n)" />
    </BlessSection>

    <BlessSection v-if="orderId !== null" :title="`Order #${orderId}`" :watermark="`#${orderId}`">
      <p><a href="#/">← all orders</a></p>
      <BlessAlert v-if="detailError" color="danger" title="Can't show this order">{{ detailError }}</BlessAlert>
      <template v-else-if="order">
        <BlessText as="p">
          {{ order.customer_email }} —
          <BlessBadge :color="order.status === 'cancelled' ? 'danger' : order.status === 'paid' ? 'success' : 'text'">{{ order.status }}</BlessBadge>
          — total {{ money(order.total_cents) }}
        </BlessText>
        <BlessTable
          :columns="itemColumns"
          :rows="order.items.map((i) => ({ ...i, price: money(i.price_cents) }))"
          row-key="sku"
          caption="Items"
        />
        <BlessButton
          v-if="['pending', 'paid'].includes(order.status)"
          variant="outline"
          color="danger"
          :loading="cancelling"
          @click="cancel"
        >
          Cancel order
        </BlessButton>
      </template>
    </BlessSection>
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
