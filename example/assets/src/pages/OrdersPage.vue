<script setup lang="ts">
// Orders: the live feed (every order made on any node), a form to make one, and one order's page.
// Staff only. The feed stays mounted when you go to another page (the parent hides it), so you
// stay "online" in the presence list.
import { computed, ref, watch } from "vue";
import { BlessAlert, BlessBadge, BlessButton, BlessField, BlessInput, BlessSection, BlessTable, BlessText, useToast } from "blessing-ui";
import { api, money, type Order } from "../api";
import OrderFeed from "../OrderFeed.vue";
import { route } from "../router";

const emit = defineEmits<{ online: [count: number] }>();
const toast = useToast();

// -- where: #/ (feed + new order) or #/orders/42 (detail)
const orderId = computed(() => {
  const m = route.value.path.match(/^\/orders\/(\d+)$/);
  return m ? Number(m[1]) : null;
});

const feed = ref<InstanceType<typeof OrderFeed>>();

// -- new order
const email = ref("");
const sku = ref("TEA-01");
const quantity = ref(1);
const creating = ref(false);
const createError = ref("");

async function create() {
  creating.value = true;
  createError.value = "";
  const res = await api.createOrder({
    customer_email: email.value,
    // the server prices the order from its products
    items: [{ sku: sku.value, quantity: Number(quantity.value) }],
  });
  creating.value = false;
  if (res.ok) toast.success({ title: `Order #${res.data.id} created` });
  else createError.value = res.error.fields ? JSON.stringify(res.error.fields) : res.error.message;
}

// -- detail
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
  <!-- one root element: the parent shows and hides this page with v-show, which a fragment cannot take -->
  <div>
  <!-- v-show, not v-if: the feed stays joined (and you stay "online") on the detail page -->
  <BlessSection v-show="orderId === null" title="Orders" subtitle="live" watermark="orders">
    <form class="new" @submit.prevent="create">
      <BlessField label="Customer email" required>
        <BlessInput v-model="email" type="email" required placeholder="sari@example.com" data-testid="order-email" />
      </BlessField>
      <BlessField label="SKU" required><BlessInput v-model="sku" required data-testid="order-sku" /></BlessField>
      <BlessField label="Quantity"><BlessInput v-model="quantity" type="number" min="1" /></BlessField>
      <BlessButton type="submit" color="accent" :loading="creating" data-testid="order-create">New order</BlessButton>
    </form>
    <BlessAlert v-if="createError" color="danger" title="Not created" data-testid="order-error">{{ createError }}</BlessAlert>

    <OrderFeed ref="feed" @online="(n) => emit('online', n)" />
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
      <BlessTable :columns="itemColumns" :rows="order.items.map((i) => ({ ...i, price: money(i.price_cents) }))" row-key="sku" caption="Items" />
      <BlessButton v-if="['pending', 'paid'].includes(order.status)" variant="outline" color="danger" :loading="cancelling" @click="cancel">
        Cancel order
      </BlessButton>
    </template>
  </BlessSection>
  </div>
</template>
