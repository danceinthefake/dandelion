<script setup lang="ts">
// The live order feed and who's online: the latest orders when the page
// opens, then every order made on any node the moment it's saved
// (channel "orders:live").
import { computed, onMounted, onUnmounted, ref } from "vue";
import type { Channel } from "phoenix";
import { Presence } from "phoenix";
import { BlessBadge, BlessTable, BlessText } from "blessing-ui";
import { money, type Order } from "./api";
import { socket } from "./socket";

const emit = defineEmits<{ online: [count: number] }>();

const orders = ref<Order[]>([]);
const live = ref(false);
const node = ref(""); // the server node this browser is connected to
let channel: Channel | null = null;

const columns = [
  { key: "id", label: "#" },
  { key: "customer_email", label: "Customer" },
  { key: "status", label: "Status" },
  { key: "total", label: "Total", align: "right" as const },
  { key: "created", label: "Created" },
];
const rows = computed(() =>
  orders.value.map((o) => ({
    ...o,
    total: money(o.total_cents),
    created: new Date(o.created_at).toLocaleTimeString(),
  })),
);

// an order changed elsewhere on the page (cancelled): keep the row in step
defineExpose({ replace: (o: Order) => (orders.value = orders.value.map((x) => (x.id === o.id ? o : x))) });

onMounted(() => {
  channel = socket.channel("orders:live");
  const presence = new Presence(channel);
  presence.onSync(() => emit("online", presence.list().length));
  channel.on("order", (o: Order) => {
    orders.value = [o, ...orders.value.filter((x) => x.id !== o.id)].slice(0, 50);
  });
  // a rejoin (after a dropped connection) replies with the list again
  channel
    .join()
    .receive("ok", ({ orders: latest, node: name }: { orders: Order[]; node: string }) => {
      orders.value = latest;
      node.value = name;
      live.value = true;
    })
    .receive("error", () => (live.value = false));
  channel.onClose(() => (live.value = false));
  channel.onError(() => (live.value = false));
});

onUnmounted(() => channel?.leave());
</script>

<template>
  <div>
    <BlessText as="p" size="sm" muted>
      <BlessBadge :color="live ? 'success' : 'warning'">{{ live ? "live" : "connecting" }}</BlessBadge>
      every order made on any node shows up here at once
      <span v-if="node" data-testid="node">— connected to {{ node }}</span>
    </BlessText>
    <BlessTable :columns="columns" :rows="rows" row-key="id" striped caption="Latest orders">
      <template #cell-id="{ row }">
        <a :href="`#/orders/${row.id}`">#{{ row.id }}</a>
      </template>
    </BlessTable>
  </div>
</template>
